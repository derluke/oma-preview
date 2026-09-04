use anyhow::{Context, Result, anyhow, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Deserialize)]
#[serde(tag = "c", rename_all = "snake_case")]
enum Request {
    RecentsGet {
        id: u64,
    },
    RecentsClear {
        id: u64,
    },
    RecentAdd {
        id: u64,
        path: String,
    },
    Inspect {
        id: u64,
        path: String,
    },
    Export {
        id: u64,
        dest: String,
        pages: Vec<PageRef>,
        #[serde(default)]
        annotations: Vec<Annotation>,
    },
    SignatureGet {
        id: u64,
    },
    SignatureSave {
        id: u64,
        strokes: Vec<Vec<Point>>,
    },
    BookmarksGet {
        id: u64,
        path: String,
    },
    BookmarksSave {
        id: u64,
        path: String,
        pages: Vec<u32>,
    },
    LoadSpec {
        id: u64,
        path: String,
        #[serde(default)]
        allow_saved_signature: bool,
    },
    DraftGet {
        id: u64,
        key: String,
    },
    DraftSave {
        id: u64,
        key: String,
        draft: Value,
    },
    DraftDelete {
        id: u64,
        key: String,
    },
    Quit,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct Point {
    x: f64,
    y: f64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct PageRef {
    path: String,
    page: u32,
    width: f64,
    height: f64,
    key: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
enum Annotation {
    Text {
        page_key: String,
        x: f64,
        y: f64,
        text: String,
        #[serde(default = "default_font_size")]
        size: f64,
        #[serde(default = "default_font_family")]
        font: String,
        #[serde(default = "default_ink_color")]
        color: String,
        #[serde(default)]
        width: f64,
    },
    Signature {
        page_key: String,
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        strokes: Vec<Vec<Point>>,
    },
}

fn default_font_size() -> f64 {
    14.0
}

fn default_font_family() -> String {
    "sans-serif".into()
}

fn default_ink_color() -> String {
    "#111111".into()
}

#[derive(Debug, Serialize)]
struct InspectedPage {
    page: u32,
    width: f64,
    height: f64,
}

fn main() -> Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("--backend") => backend(),
        Some("inspect") => command_inspect(&args[1..]),
        Some("apply") => command_apply(&args[1..]),
        Some("review") => command_review(&args[1..]),
        Some("edit") => command_edit(&args[1..]),
        Some("status") => {
            println!("{}", serde_json::to_string_pretty(&live_state()?)?);
            Ok(())
        }
        Some("verify") => command_verify(&args[1..]),
        Some("agent-help") => {
            print_agent_help();
            Ok(())
        }
        Some("--version") => {
            println!("oma-preview {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("--help") | Some("-h") => {
            print_help();
            Ok(())
        }
        _ => launch_gui(&args),
    }
}

fn print_help() {
    println!(
        "usage: oma-preview [--gui] [PDF ...]\n\
         \x20      oma-preview inspect PDF\n\
         \x20      oma-preview apply SPEC.json [--allow-saved-signature]\n\
         \x20      oma-preview review SPEC.json [--allow-saved-signature]\n\
         \x20      oma-preview edit SPEC.json [--allow-saved-signature]\n\
         \x20      oma-preview status\n\
         \x20      oma-preview verify PDF\n\
         \x20      oma-preview agent-help\n\
         \x20      oma-preview --version"
    );
}

fn print_agent_help() {
    const AGENT_HELP: &str = r##"Oma Preview agent interface (JSON on stdout; diagnostics on stderr)

Intended use: fill non-form PDFs, propose text/signature overlays, and assemble
or slice pages while the user follows along. Default to `review`: it opens the
proposal visibly so the user can correct placement and content before export.

1. `oma-preview inspect input.pdf`
2. Write a JSON spec, using normalized top-left coordinates (0.0 to 1.0).
3. `oma-preview review spec.json` to let the user inspect and adjust before export.
4. Update that running window with `oma-preview edit updated-spec.json`.
   `oma-preview status` returns the actual visible pages and annotations, including
   user corrections. Reconcile these before replacing a proposal. `edit` waits
   for the UI to confirm loading and refuses while the user is typing.
5. Use `oma-preview apply spec.json` only for an explicitly unattended export.
6. `oma-preview verify output.pdf`

Spec:
{
  "output": "result.pdf",
  "sources": [
    {"path": "input.pdf", "pages": "1-2,4"},
    {"path": "append.pdf", "pages": "all"}
  ],
  "annotations": [
    {"kind": "text", "output_page": 1, "x": 0.20, "y": 0.15,
     "text": "Visible text", "size": 12, "font": "serif", "color": "#2563eb"},
    {"kind": "saved_signature", "output_page": 1, "x": 0.18, "y": 0.72,
     "width": 0.28, "height": 0.10}
  ]
}

`pages` accepts `all`, comma-separated pages, and inclusive ranges. Source and
output paths are resolved relative to the spec. `output_page` addresses the
assembled result, starting at 1. Text fonts are `sans-serif`, `serif`, or
`monospace`; colors use `#RRGGBB`. Applying a saved signature is refused unless
the caller also passes `--allow-saved-signature`. Existing files are replaced
atomically; input PDFs are never modified. Text may contain `\n` for explicit
line breaks; in the review UI Shift+Enter inserts a line and Enter finishes."##;
    println!("{AGENT_HELP}");
}

#[derive(Debug, Deserialize)]
struct AgentSpec {
    output: String,
    sources: Vec<AgentSource>,
    #[serde(default)]
    annotations: Vec<AgentAnnotation>,
}

#[derive(Debug, Deserialize)]
struct AgentSource {
    path: String,
    #[serde(default = "default_page_selection")]
    pages: String,
}

fn default_page_selection() -> String {
    "all".into()
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum AgentAnnotation {
    Text {
        output_page: u32,
        x: f64,
        y: f64,
        text: String,
        #[serde(default = "default_font_size")]
        size: f64,
        #[serde(default = "default_font_family")]
        font: String,
        #[serde(default = "default_ink_color")]
        color: String,
    },
    SavedSignature {
        output_page: u32,
        x: f64,
        y: f64,
        #[serde(default = "default_signature_width")]
        width: f64,
        #[serde(default = "default_signature_height")]
        height: f64,
    },
}

fn default_signature_width() -> f64 {
    0.24
}

fn default_signature_height() -> f64 {
    0.09
}

fn command_inspect(args: &[String]) -> Result<()> {
    let path = single_path_arg("inspect", args)?;
    let absolute = fs::canonicalize(path).with_context(|| format!("open {path}"))?;
    let pages = inspect(&absolute)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "ok": true,
            "path": absolute,
            "page_count": pages.len(),
            "pages": pages,
            "coordinates": "normalized from top-left"
        }))?
    );
    Ok(())
}

fn command_apply(args: &[String]) -> Result<()> {
    let allow_signature = args.iter().any(|arg| arg == "--allow-saved-signature");
    let spec_path = spec_path_arg("apply", args)?;
    let prepared = prepare_agent_spec(&spec_path, allow_signature)?;
    export(&prepared.output, &prepared.pages, &prepared.annotations)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "ok": true,
            "output": fs::canonicalize(&prepared.output).unwrap_or(prepared.output),
            "pages": prepared.pages.len(),
            "annotations": prepared.annotations.len()
        }))?
    );
    Ok(())
}

fn command_review(args: &[String]) -> Result<()> {
    let allow_signature = args.iter().any(|arg| arg == "--allow-saved-signature");
    let spec_path = spec_path_arg("review", args)?;
    // Parse and validate before showing a window, so agents get a synchronous error.
    let _ = prepare_agent_spec(&spec_path, allow_signature)?;
    launch_quickshell(Vec::new(), Some(spec_path), allow_signature)
}

fn command_edit(args: &[String]) -> Result<()> {
    let allow_signature = args.iter().any(|arg| arg == "--allow-saved-signature");
    let spec_path = spec_path_arg("edit", args)?;
    let _ = prepare_agent_spec(&spec_path, allow_signature)?;
    let before = live_state()?;
    if before["busy"] == true || before["editing"] == true || before["modal"] == true {
        bail!(
            "Oma Preview is busy, the user is typing, or a dialog is open; wait until the current interaction finishes before retrying"
        );
    }
    let revision = before["revision"].as_u64().unwrap_or(0);
    let exe = env::current_exe().context("locate Oma Preview executable")?;
    let ui = ui_dir(&exe)?;
    let result = Command::new("qs")
        .args([
            "-p",
            ui.to_string_lossy().as_ref(),
            "ipc",
            "call",
            "oma-preview",
            "loadReview",
            spec_path.to_string_lossy().as_ref(),
            if allow_signature { "true" } else { "false" },
        ])
        .output()
        .context("contact the running Oma Preview window")?;
    if !result.status.success() || String::from_utf8_lossy(&result.stdout).trim() != "true" {
        let detail = String::from_utf8_lossy(&result.stderr);
        bail!(
            "no running Oma Preview review accepted the edit{}",
            if detail.trim().is_empty() {
                String::new()
            } else {
                format!(": {}", detail.trim())
            }
        );
    }
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        let state = live_state()?;
        if let Some(error) = state["error"].as_str().filter(|s| !s.is_empty()) {
            bail!("Oma Preview could not load the proposal: {error}");
        }
        if state["revision"].as_u64().unwrap_or(0) > revision {
            break;
        }
        if std::time::Instant::now() >= deadline {
            bail!(
                "Oma Preview has not confirmed the update; inspect `oma-preview status` before retrying"
            );
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "ok": true,
            "review": "updated",
            "spec": spec_path
        }))?
    );
    Ok(())
}

fn live_state() -> Result<Value> {
    let exe = env::current_exe().context("locate Oma Preview executable")?;
    let ui = ui_dir(&exe)?;
    let result = Command::new("qs")
        .args([
            "-p",
            ui.to_string_lossy().as_ref(),
            "ipc",
            "call",
            "oma-preview",
            "state",
        ])
        .output()
        .context("contact the running Oma Preview window")?;
    if !result.status.success() {
        bail!(
            "cannot read Oma Preview's live state; open a review using this version of Oma Preview first"
        );
    }
    serde_json::from_slice(&result.stdout).context("read Oma Preview live state")
}

struct PreparedSpec {
    output: PathBuf,
    pages: Vec<PageRef>,
    annotations: Vec<Annotation>,
}

fn prepare_agent_spec(spec_path: &Path, allow_signature: bool) -> Result<PreparedSpec> {
    let spec: AgentSpec = serde_json::from_slice(&fs::read(spec_path)?)
        .with_context(|| format!("parse {}", spec_path.display()))?;
    let base = spec_path.parent().unwrap_or(Path::new("."));
    let output = resolve_from(base, &spec.output);
    let mut pages = Vec::new();

    for source in &spec.sources {
        let source_path = resolve_from(base, &source.path);
        let absolute = fs::canonicalize(&source_path)
            .with_context(|| format!("open {}", source_path.display()))?;
        let inspected = inspect(&absolute)?;
        for page_number in parse_page_selection(&source.pages, inspected.len() as u32)? {
            let page = inspected
                .get(page_number as usize - 1)
                .ok_or_else(|| anyhow!("page {page_number} is outside {}", absolute.display()))?;
            let output_page = pages.len() + 1;
            pages.push(PageRef {
                path: absolute.to_string_lossy().into_owned(),
                page: page_number,
                width: page.width,
                height: page.height,
                key: format!("output-{output_page}"),
            });
        }
    }
    if pages.is_empty() {
        bail!("the spec selects no pages");
    }

    let saved_signature: Vec<Vec<Point>> = if spec
        .annotations
        .iter()
        .any(|mark| matches!(mark, AgentAnnotation::SavedSignature { .. }))
    {
        if !allow_signature {
            bail!(
                "the spec requests the saved signature; pass --allow-saved-signature only with explicit signing authorization"
            );
        }
        let strokes: Vec<Vec<Point>> = read_json(&signature_path())
            .context("no saved signature is available; draw one in the Oma Preview GUI first")?;
        if strokes.is_empty() {
            bail!("the saved signature is empty");
        }
        strokes
    } else {
        Vec::new()
    };

    let mut annotations = Vec::new();
    for mark in spec.annotations {
        match mark {
            AgentAnnotation::Text {
                output_page,
                x,
                y,
                text,
                size,
                font,
                color,
            } => {
                validate_output_page(output_page, pages.len())?;
                validate_fraction("text x", x)?;
                validate_fraction("text y", y)?;
                if !(1.0..=200.0).contains(&size) {
                    bail!("text size must be between 1 and 200 points");
                }
                validate_font(&font)?;
                validate_color(&color)?;
                annotations.push(Annotation::Text {
                    page_key: format!("output-{output_page}"),
                    x,
                    y,
                    text,
                    size,
                    font,
                    color,
                    width: 0.0,
                });
            }
            AgentAnnotation::SavedSignature {
                output_page,
                x,
                y,
                width,
                height,
            } => {
                validate_output_page(output_page, pages.len())?;
                validate_fraction("signature x", x)?;
                validate_fraction("signature y", y)?;
                validate_fraction("signature width", width)?;
                validate_fraction("signature height", height)?;
                if x + width > 1.0 || y + height > 1.0 {
                    bail!("saved signature bounds extend outside the page");
                }
                annotations.push(Annotation::Signature {
                    page_key: format!("output-{output_page}"),
                    x,
                    y,
                    width,
                    height,
                    strokes: saved_signature.clone(),
                });
            }
        }
    }
    Ok(PreparedSpec {
        output,
        pages,
        annotations,
    })
}

fn spec_path_arg(command: &str, args: &[String]) -> Result<PathBuf> {
    let spec_arg = args
        .iter()
        .find(|arg| !arg.starts_with('-'))
        .ok_or_else(|| {
            anyhow!("usage: oma-preview {command} SPEC.json [--allow-saved-signature]")
        })?;
    fs::canonicalize(spec_arg).with_context(|| format!("open {spec_arg}"))
}

fn command_verify(args: &[String]) -> Result<()> {
    let path = single_path_arg("verify", args)?;
    let absolute = fs::canonicalize(path).with_context(|| format!("open {path}"))?;
    let checked = Command::new("qpdf")
        .arg("--check")
        .arg(&absolute)
        .output()
        .context("run qpdf")?;
    let pages = inspect(&absolute)?;
    let report = json!({
        "ok": checked.status.success(),
        "path": absolute,
        "page_count": pages.len(),
        "qpdf": String::from_utf8_lossy(&checked.stdout).trim()
    });
    println!("{}", serde_json::to_string_pretty(&report)?);
    if !checked.status.success() {
        bail!("PDF structural validation failed");
    }
    Ok(())
}

fn single_path_arg<'a>(command: &str, args: &'a [String]) -> Result<&'a str> {
    if args.len() != 1 {
        bail!("usage: oma-preview {command} PDF");
    }
    Ok(&args[0])
}

fn resolve_from(base: &Path, value: &str) -> PathBuf {
    let path = Path::new(value);
    if path.is_absolute() {
        path.to_owned()
    } else {
        base.join(path)
    }
}

fn parse_page_selection(selection: &str, count: u32) -> Result<Vec<u32>> {
    if selection.trim().eq_ignore_ascii_case("all") {
        return Ok((1..=count).collect());
    }
    let mut pages = Vec::new();
    for part in selection
        .split(',')
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        if let Some((start, end)) = part.split_once('-') {
            let start: u32 = start.trim().parse().context("invalid page range start")?;
            let end: u32 = end.trim().parse().context("invalid page range end")?;
            if start == 0 || end < start || end > count {
                bail!("invalid page range {part}; document has {count} pages");
            }
            pages.extend(start..=end);
        } else {
            let page: u32 = part.parse().context("invalid page number")?;
            if page == 0 || page > count {
                bail!("page {page} is outside the 1-{count} range");
            }
            pages.push(page);
        }
    }
    if pages.is_empty() {
        bail!("page selection is empty");
    }
    Ok(pages)
}

fn validate_output_page(page: u32, count: usize) -> Result<()> {
    if page == 0 || page as usize > count {
        bail!("annotation output_page {page} is outside the 1-{count} range");
    }
    Ok(())
}

fn validate_fraction(name: &str, value: f64) -> Result<()> {
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        bail!("{name} must be a finite number between 0.0 and 1.0");
    }
    Ok(())
}

fn validate_font(value: &str) -> Result<()> {
    if !matches!(value, "sans-serif" | "serif" | "monospace") {
        bail!("text font must be sans-serif, serif, or monospace");
    }
    Ok(())
}

fn validate_color(value: &str) -> Result<()> {
    if value.len() != 7
        || !value.starts_with('#')
        || !value.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
    {
        bail!("text color must use #RRGGBB");
    }
    Ok(())
}

fn launch_gui(args: &[String]) -> Result<()> {
    let mut filenames = Vec::new();
    let mut positional_only = false;
    for arg in args {
        if !positional_only && arg == "--" {
            positional_only = true;
        } else if !positional_only && arg == "--gui" {
            continue;
        } else if !positional_only && arg.starts_with('-') {
            bail!(
                "Unknown option '{arg}'.\nUse 'oma-preview --version' for the version, or 'oma-preview --help' for usage."
            );
        } else {
            filenames.push(arg);
        }
    }
    let mut paths = filenames
        .into_iter()
        .map(|p| {
            fs::canonicalize(p)
                .unwrap_or_else(|_| PathBuf::from(p))
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    if paths.is_empty() {
        paths.push(String::new());
    }

    launch_quickshell(paths, None, false)
}

fn launch_quickshell(
    paths: Vec<String>,
    review_spec: Option<PathBuf>,
    allow_saved_signature: bool,
) -> Result<()> {
    let has_display = ["WAYLAND_DISPLAY", "DISPLAY"]
        .iter()
        .any(|key| env::var_os(key).is_some_and(|value| !value.is_empty()));
    let platform = env::var("QT_QPA_PLATFORM").unwrap_or_default();
    let headless_platform = matches!(platform.split(':').next(), Some("offscreen" | "minimal"));
    if !has_display && !headless_platform {
        bail!(
            "Oma Preview needs a graphical desktop to open a window.\nNo Wayland or X11 display is available in this session.\nIf you are connected over SSH, open Oma Preview from a terminal on the remote computer's desktop instead.\nCommands such as 'oma-preview --version', 'oma-preview inspect FILE.pdf' and 'oma-preview verify FILE.pdf' work without a display."
        );
    }
    let exe = env::current_exe().context("locate Oma Preview executable")?;
    let ui = ui_dir(&exe)?;

    let mut command = Command::new("qs");
    command
        .args(["-p", ui.to_string_lossy().as_ref()])
        .env("OMA_PREVIEW_BIN", exe)
        .env("OMA_PREVIEW_PATHS", serde_json::to_string(&paths)?);
    if let Some(spec) = review_spec {
        command.env("OMA_PREVIEW_REVIEW_SPEC", spec).env(
            "OMA_PREVIEW_ALLOW_SAVED_SIGNATURE",
            if allow_saved_signature { "1" } else { "0" },
        );
    }
    let status = command
        .status()
        .context("launch Quickshell (is quickshell installed?)")?;
    if !status.success() {
        bail!("Quickshell exited with {status}");
    }
    Ok(())
}

fn ui_dir(exe: &Path) -> Result<PathBuf> {
    let ui = env::var_os("OMA_PREVIEW_UI_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let beside = exe
                .parent()
                .unwrap_or(Path::new("."))
                .join("../share/oma-preview/ui");
            if beside.exists() {
                beside
            } else {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ui")
            }
        });
    if !ui.join("shell.qml").exists() {
        bail!("Oma Preview UI was not found at {}", ui.display());
    }
    Ok(ui)
}

fn backend() -> Result<()> {
    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(v) => v,
            Err(e) => {
                emit(&mut out, json!({"t":"error","msg":e.to_string()}));
                break;
            }
        };
        if line.trim().is_empty() {
            continue;
        }
        let request: Request = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                emit(
                    &mut out,
                    json!({"t":"error","msg":format!("invalid request: {e}")}),
                );
                continue;
            }
        };
        if matches!(request, Request::Quit) {
            emit(&mut out, json!({"t":"quit_ready"}));
            break;
        }
        if let Err(e) = handle(request, &mut out) {
            emit(&mut out, json!({"t":"error","msg":format!("{e:#}")}));
        }
    }
    Ok(())
}

fn emit(out: &mut impl Write, value: Value) {
    let _ = serde_json::to_writer(&mut *out, &value);
    let _ = out.write_all(b"\n");
    let _ = out.flush();
}

fn handle(request: Request, out: &mut impl Write) -> Result<()> {
    match request {
        Request::RecentsGet { id } => {
            emit(out, json!({"t":"recents","id":id,"paths":recent_paths()}));
        }
        Request::RecentsClear { id } => {
            write_json(&state_dir().join("recents.json"), &Vec::<String>::new())?;
            emit(out, json!({"t":"recents","id":id,"paths":[]}));
        }
        Request::RecentAdd { id, path } => {
            let path = fs::canonicalize(path)?.to_string_lossy().into_owned();
            let mut paths = recent_paths();
            paths.retain(|p| p != &path);
            paths.insert(0, path);
            paths.truncate(10);
            write_json(&state_dir().join("recents.json"), &paths)?;
            emit(out, json!({"t":"recents","id":id,"paths":paths}));
        }
        Request::Inspect { id, path } => {
            let pages = inspect(Path::new(&path))?;
            emit(
                out,
                json!({"t":"inspected","id":id,"path":path,"pages":pages}),
            );
        }
        Request::Export {
            id,
            dest,
            pages,
            annotations,
        } => {
            export(Path::new(&dest), &pages, &annotations)?;
            emit(out, json!({"t":"exported","id":id,"path":dest}));
        }
        Request::SignatureGet { id } => {
            let strokes: Vec<Vec<Point>> = read_json(&signature_path()).unwrap_or_default();
            emit(out, json!({"t":"signature","id":id,"strokes":strokes}));
        }
        Request::SignatureSave { id, strokes } => {
            write_json(&signature_path(), &strokes)?;
            emit(out, json!({"t":"signature_saved","id":id}));
        }
        Request::BookmarksGet { id, path } => {
            let all: BTreeMap<String, Vec<u32>> = read_json(&bookmarks_path()).unwrap_or_default();
            emit(
                out,
                json!({"t":"bookmarks","id":id,"path":path,"pages":all.get(&path).cloned().unwrap_or_default()}),
            );
        }
        Request::BookmarksSave { id, path, pages } => {
            let file = bookmarks_path();
            let mut all: BTreeMap<String, Vec<u32>> = read_json(&file).unwrap_or_default();
            all.insert(path, pages);
            write_json(&file, &all)?;
            emit(out, json!({"t":"bookmarks_saved","id":id}));
        }
        Request::LoadSpec {
            id,
            path,
            allow_saved_signature,
        } => {
            let spec_path = fs::canonicalize(&path).with_context(|| format!("open {path}"))?;
            let prepared = prepare_agent_spec(&spec_path, allow_saved_signature)?;
            emit(
                out,
                json!({
                    "t":"review_loaded",
                    "id":id,
                    "output":prepared.output,
                    "pages":prepared.pages,
                    "annotations":prepared.annotations
                }),
            );
        }
        Request::DraftGet { id, key } => {
            let draft: Value = read_json(&draft_path(&key)).unwrap_or(Value::Null);
            emit(out, json!({"t":"draft_loaded","id":id,"draft":draft}));
        }
        Request::DraftSave { id, key, draft } => {
            write_json(&draft_path(&key), &draft)?;
            emit(out, json!({"t":"draft_saved","id":id}));
        }
        Request::DraftDelete { id, key } => {
            let file = draft_path(&key);
            if file.exists() {
                fs::remove_file(file)?;
            }
            emit(out, json!({"t":"draft_deleted","id":id}));
        }
        Request::Quit => unreachable!(),
    }
    Ok(())
}

fn inspect(path: &Path) -> Result<Vec<InspectedPage>> {
    if !path.is_file() {
        bail!("{} is not a file", path.display());
    }
    let count_out = Command::new("qpdf")
        .args(["--show-npages", path.to_string_lossy().as_ref()])
        .output()
        .context("run qpdf")?;
    if !count_out.status.success() {
        bail!("qpdf could not read {}", path.display());
    }
    let count: u32 = String::from_utf8_lossy(&count_out.stdout)
        .trim()
        .parse()
        .context("read page count")?;
    let info = Command::new("pdfinfo")
        .args([
            "-f",
            "1",
            "-l",
            &count.to_string(),
            path.to_string_lossy().as_ref(),
        ])
        .output()
        .context("run pdfinfo")?;
    if !info.status.success() {
        bail!("pdfinfo could not read {}", path.display());
    }
    let text = String::from_utf8_lossy(&info.stdout);
    let mut sizes = BTreeMap::<u32, (f64, f64)>::new();
    for line in text.lines() {
        let words = line.split_whitespace().collect::<Vec<_>>();
        if words.len() >= 6
            && words[0] == "Page"
            && words[2] == "size:"
            && words[4] == "x"
            && let (Ok(n), Ok(w), Ok(h)) = (words[1].parse(), words[3].parse(), words[5].parse())
        {
            sizes.insert(n, (w, h));
        }
    }
    Ok((1..=count)
        .map(|page| {
            let (width, height) = sizes.get(&page).copied().unwrap_or((595.0, 842.0));
            InspectedPage {
                page,
                width,
                height,
            }
        })
        .collect())
}

fn export(dest: &Path, pages: &[PageRef], annotations: &[Annotation]) -> Result<()> {
    if pages.is_empty() {
        bail!("there are no pages to save");
    }
    if let Ok(destination) = fs::canonicalize(dest) {
        for page in pages {
            if fs::canonicalize(&page.path).ok().as_ref() == Some(&destination) {
                bail!("choose a different output file; Oma Preview never overwrites a source PDF");
            }
        }
    }
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp = tempfile::tempdir().context("create export workspace")?;
    let assembled = temp.path().join("pages.pdf");
    let overlay = temp.path().join("marks.pdf");

    let mut select = Command::new("qpdf");
    // The first source is primary so its metadata, outlines, tags, and AcroForm
    // structure survive page composition. `--empty` would discard all of them.
    select.arg(&pages[0].path).arg("--pages");
    for p in pages {
        select.arg(&p.path).arg(p.page.to_string());
    }
    let status = select
        .arg("--")
        .arg(&assembled)
        .status()
        .context("assemble pages with qpdf")?;
    if !status.success() {
        bail!("qpdf could not assemble the selected pages");
    }

    if annotations.is_empty() {
        atomic_copy(&assembled, dest)?;
        return Ok(());
    }
    create_overlay(&overlay, pages, annotations)?;
    let staged = temp.path().join("finished.pdf");
    let status = Command::new("qpdf")
        .arg(&assembled)
        .arg("--overlay")
        .arg(&overlay)
        .arg("--repeat=1-z")
        .arg("--")
        .arg(&staged)
        .status()
        .context("apply annotations with qpdf")?;
    if !status.success() {
        bail!("qpdf could not apply annotations");
    }
    atomic_copy(&staged, dest)
}

fn atomic_copy(source: &Path, dest: &Path) -> Result<()> {
    let parent = dest.parent().unwrap_or(Path::new("."));
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    let mut input = fs::File::open(source)?;
    io::copy(&mut input, &mut staged)?;
    staged.as_file_mut().sync_all()?;
    staged.persist(dest).map_err(|e| anyhow!(e.error))?;
    Ok(())
}

fn create_overlay(path: &Path, pages: &[PageRef], annotations: &[Annotation]) -> Result<()> {
    let temp = tempfile::tempdir().context("create annotation workspace")?;
    let mut rendered = Vec::new();
    for (index, page) in pages.iter().enumerate() {
        let mut elements = String::new();
        for mark in annotations {
            match mark {
                Annotation::Text {
                    page_key,
                    x,
                    y,
                    text,
                    size,
                    font,
                    color,
                    ..
                } if page_key == &page.key => {
                    let px = x.clamp(0.0, 1.0) * page.width;
                    let py = y.clamp(0.0, 1.0) * page.height + size;
                    elements.push_str(&svg_text_elements(px, py, text, *size, font, color));
                }
                Annotation::Signature {
                    page_key,
                    x,
                    y,
                    width,
                    height,
                    strokes,
                } if page_key == &page.key => {
                    let ox = x.clamp(0.0, 1.0) * page.width;
                    let oy = y.clamp(0.0, 1.0) * page.height;
                    let w = width.clamp(0.01, 1.0) * page.width;
                    let h = height.clamp(0.01, 1.0) * page.height;
                    for stroke in strokes {
                        if !stroke.is_empty() {
                            let points = stroke
                                .iter()
                                .map(|point| {
                                    format!("{:.2},{:.2}", ox + point.x * w, oy + point.y * h)
                                })
                                .collect::<Vec<_>>()
                                .join(" ");
                            elements.push_str(&format!(
                                "<polyline points=\"{points}\" fill=\"none\" stroke=\"#111111\" stroke-width=\"1.35\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
                            ));
                        }
                    }
                }
                _ => {}
            }
        }
        let svg = format!(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{:.3}pt\" height=\"{:.3}pt\" viewBox=\"0 0 {:.3} {:.3}\">{elements}</svg>",
            page.width, page.height, page.width, page.height
        );
        let svg_path = temp.path().join(format!("page-{index}.svg"));
        let pdf_path = temp.path().join(format!("page-{index}.pdf"));
        fs::write(&svg_path, svg)?;
        let status = Command::new("rsvg-convert")
            .arg("--format=pdf")
            .arg("--output")
            .arg(&pdf_path)
            .arg(&svg_path)
            .status()
            .context("render Unicode annotations")?;
        if !status.success() {
            bail!(
                "the annotation renderer could not create page {}",
                index + 1
            );
        }
        rendered.push(pdf_path);
    }

    let mut combine = Command::new("qpdf");
    combine.arg("--empty").arg("--pages");
    for page in &rendered {
        combine.arg(page).arg("1");
    }
    let status = combine
        .arg("--")
        .arg(path)
        .status()
        .context("assemble annotation pages")?;
    if !status.success() {
        bail!("qpdf could not assemble the annotation layer");
    }
    Ok(())
}

fn xml_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn svg_text_elements(
    x: f64,
    baseline: f64,
    text: &str,
    size: f64,
    font: &str,
    color: &str,
) -> String {
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    normalized
        .split('\n')
        .enumerate()
        .map(|(line, value)| {
            format!(
                "<text x=\"{x:.2}\" y=\"{:.2}\" font-family=\"{}\" font-size=\"{size:.2}\" fill=\"{}\">{}</text>\n",
                baseline + line as f64 * size * 1.2,
                safe_font(font),
                safe_color(color),
                xml_escape(value)
            )
        })
        .collect()
}

fn safe_font(value: &str) -> &str {
    match value {
        "serif" => "serif",
        "monospace" => "monospace",
        _ => "sans-serif",
    }
}

fn safe_color(value: &str) -> &str {
    if validate_color(value).is_ok() {
        value
    } else {
        "#111111"
    }
}

fn data_dir() -> PathBuf {
    // Preserve Folio's private storage across the application rename.
    dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("folio")
}
fn state_dir() -> PathBuf {
    dirs::state_dir().unwrap_or_else(data_dir).join("folio")
}
fn signature_path() -> PathBuf {
    data_dir().join("signature.json")
}
fn bookmarks_path() -> PathBuf {
    state_dir().join("bookmarks.json")
}

fn recent_paths() -> Vec<String> {
    let mut paths: Vec<String> = read_json(&state_dir().join("recents.json")).unwrap_or_default();
    paths.retain(|path| Path::new(path).is_file());
    paths.truncate(10);
    paths
}

fn draft_path(key: &str) -> PathBuf {
    let mut digest = Sha256::new();
    digest.update(b"folio-draft-v1\0");
    digest.update(key.as_bytes());
    if let Ok(paths) = serde_json::from_str::<Vec<String>>(key) {
        for path in paths {
            digest.update(b"\0");
            digest.update(path.as_bytes());
            if let Ok(meta) = fs::metadata(&path) {
                digest.update(meta.len().to_le_bytes());
                if let Ok(changed) = meta.modified()
                    && let Ok(duration) = changed.duration_since(std::time::UNIX_EPOCH)
                {
                    digest.update(duration.as_nanos().to_le_bytes());
                }
            }
        }
    }
    state_dir()
        .join("drafts")
        .join(format!("{:x}.json", digest.finalize()))
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let bytes = serde_json::to_vec_pretty(value)?;
    let parent = path.parent().unwrap_or(Path::new("."));
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    staged.write_all(&bytes)?;
    staged.as_file_mut().sync_all()?;
    staged.persist(path).map_err(|e| anyhow!(e.error))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn annotation_text_is_xml_escaped_without_losing_unicode() {
        assert_eq!(xml_escape("Jörg & 李 <3"), "Jörg &amp; 李 &lt;3");
        let lines = svg_text_elements(
            10.0,
            20.0,
            "line one\nline & two",
            10.0,
            "sans-serif",
            "#111111",
        );
        assert!(lines.contains("y=\"20.00\""));
        assert!(lines.contains("y=\"32.00\""));
        assert!(lines.contains(">line &amp; two</text>"));
    }

    #[test]
    fn generated_overlay_has_one_page_per_source_page() {
        let temp = tempfile::tempdir().unwrap();
        let output = temp.path().join("overlay.pdf");
        let pages = vec![
            PageRef {
                path: "a.pdf".into(),
                page: 1,
                width: 595.0,
                height: 842.0,
                key: "a1".into(),
            },
            PageRef {
                path: "b.pdf".into(),
                page: 2,
                width: 612.0,
                height: 792.0,
                key: "b2".into(),
            },
        ];
        let marks = vec![Annotation::Text {
            page_key: "a1".into(),
            x: 0.1,
            y: 0.2,
            text: "Héllo (PDF)".into(),
            size: 14.0,
            font: "sans-serif".into(),
            color: "#111111".into(),
            width: 0.0,
        }];

        create_overlay(&output, &pages, &marks).unwrap();
        let result = Command::new("qpdf")
            .args(["--show-npages", output.to_str().unwrap()])
            .output()
            .unwrap();
        assert!(result.status.success());
        assert_eq!(String::from_utf8_lossy(&result.stdout).trim(), "2");
    }

    #[test]
    fn agent_page_ranges_are_expanded_in_requested_order() {
        assert_eq!(
            parse_page_selection("2,4-5,1", 5).unwrap(),
            vec![2, 4, 5, 1]
        );
        assert!(parse_page_selection("0", 5).is_err());
        assert!(parse_page_selection("4-2", 5).is_err());
    }
}
