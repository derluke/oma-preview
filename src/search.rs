//! Private, cancellable search process. Never runs in the draft-service queue.
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};

const MAX_INPUT: u64 = 8 * 1024 * 1024;
const MAX_LINE: u64 = 1024 * 1024;
const MAX_PAGE_TEXT: usize = 4 * 1024 * 1024;
const MAX_MATCHES: usize = 10_000;
const BATCH_PAGES: usize = 128;

type PageTargets = BTreeMap<u32, Vec<(usize, String)>>;
struct Batch {
    path: PathBuf,
    pages: PageTargets,
    priority: usize,
}

// Prioritize bounded regions without turning every page into a subprocess.
// Prioritize the reader's current region, then wrap around. Result indices
// remain workspace indices, independent of the order in which batches finish.
fn batches(sources: BTreeMap<PathBuf, PageTargets>, start: usize, total: usize) -> Vec<Batch> {
    let mut batches = Vec::new();
    for (path, selected) in sources {
        let mut batch = Batch {
            path: path.clone(),
            pages: BTreeMap::new(),
            priority: total,
        };
        for (page, mut targets) in selected {
            // Repeated source pages share extraction, but the visible copy
            // must still receive matches before the global result cap is hit.
            targets.sort_by_key(|(index, _)| (index + total - start) % total);
            let priority = (targets[0].0 + total - start) % total;
            let gap = batch
                .pages
                .last_key_value()
                .is_some_and(|(last, _)| last.checked_add(1) != Some(page));
            if !batch.pages.is_empty() && (gap || batch.pages.len() >= BATCH_PAGES || priority == 0)
            {
                batches.push(batch);
                batch = Batch {
                    path: path.clone(),
                    pages: BTreeMap::new(),
                    priority: total,
                };
            }
            batch.priority = batch.priority.min(priority);
            batch.pages.insert(page, targets);
        }
        if !batch.pages.is_empty() {
            batches.push(batch);
        }
    }
    batches.sort_by_key(|batch| batch.priority);
    // After prioritization, adjacent forward ranges can share one extractor.
    // A normal PDF needs only one run (or two when wrapping), regardless of
    // length. Reordered/interleaved workspaces keep bounded priority regions.
    let mut merged: Vec<Batch> = Vec::new();
    for batch in batches {
        if let Some(previous) = merged.last_mut()
            && previous.path == batch.path
            && previous.pages.last_key_value().unwrap().0.checked_add(1)
                == Some(*batch.pages.first_key_value().unwrap().0)
        {
            previous.pages.extend(batch.pages);
            continue;
        }
        merged.push(batch);
    }
    merged
}

#[derive(Deserialize)]
struct Request {
    query: String,
    pages: Vec<Page>,
    #[serde(default)]
    start_index: usize,
}
#[derive(Deserialize)]
struct Page {
    path: PathBuf,
    page: u32,
    key: String,
}
#[derive(Clone, Debug, Serialize)]
struct Rect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}
#[derive(Debug, Serialize)]
struct Match {
    rects: Vec<Rect>,
}
struct Word {
    start: usize,
    end: usize,
    rect: Rect,
}
#[derive(Default)]
struct TextPage {
    number: u32,
    width: f64,
    height: f64,
    text: String,
    words: Vec<Word>,
    flow: Option<(u32, u32)>,
}

fn normalized(text: &str) -> String {
    let mut folded = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            'ﬀ' => folded.push_str("ff"),
            'ﬁ' => folded.push_str("fi"),
            'ﬂ' => folded.push_str("fl"),
            'ﬃ' => folded.push_str("ffi"),
            'ﬄ' => folded.push_str("ffl"),
            _ => folded.extend(c.to_lowercase()),
        }
    }
    folded.split_whitespace().collect::<Vec<_>>().join(" ")
}

impl TextPage {
    fn word(&mut self, fields: &[&str]) -> Result<()> {
        ensure!(
            self.width > 0.0 && self.height > 0.0,
            "Text appeared before page dimensions"
        );
        let flow = (fields[2].parse()?, fields[3].parse()?);
        let text = normalized(fields[11]);
        if text.is_empty() {
            return Ok(());
        }
        let bounds = [
            fields[6].parse::<f64>()?,
            fields[7].parse()?,
            fields[8].parse()?,
            fields[9].parse()?,
        ];
        ensure!(
            bounds.iter().all(|v| v.is_finite()) && bounds[2] >= 0.0 && bounds[3] >= 0.0,
            "Invalid text bounds"
        );
        // Keep phrases across lines, but not across unrelated layout flows.
        if !self.text.is_empty() {
            self.text
                .push(if self.flow == Some(flow) { ' ' } else { '\n' });
        }
        self.flow = Some(flow);
        let start = self.text.len();
        self.text.push_str(&text);
        ensure!(
            self.text.len() <= MAX_PAGE_TEXT,
            "Page text exceeds the search safety limit"
        );
        ensure!(
            self.words.len() < 200_000,
            "Page word count exceeds the search safety limit"
        );
        let x = (bounds[0] / self.width).clamp(0.0, 1.0);
        let y = (bounds[1] / self.height).clamp(0.0, 1.0);
        let right = ((bounds[0] + bounds[2]) / self.width).clamp(x, 1.0);
        let bottom = ((bounds[1] + bounds[3]) / self.height).clamp(y, 1.0);
        self.words.push(Word {
            start,
            end: self.text.len(),
            rect: Rect {
                x,
                y,
                width: right - x,
                height: bottom - y,
            },
        });
        Ok(())
    }
    fn matches(&self, query: &str, limit: usize) -> Vec<Match> {
        let mut found = Vec::new();
        if query.is_empty() {
            return found;
        }
        for (start, _) in self.text.match_indices(query).take(limit) {
            let end = start + query.len();
            let first = self.words.partition_point(|word| word.end <= start);
            let rects = self.words[first..]
                .iter()
                .take_while(|word| word.start < end)
                .map(|word| word.rect.clone())
                .collect();
            found.push(Match { rects });
        }
        found
    }
}

struct Extractor(Child);
impl Drop for Extractor {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn extractor(path: &PathBuf, first: u32, last: u32) -> Result<Extractor> {
    let mut command = Command::new("pdftotext");
    command
        .args([
            "-tsv",
            "-cropbox",
            "-enc",
            "UTF-8",
            "-f",
            &first.to_string(),
            "-l",
            &last.to_string(),
        ])
        .arg(path)
        .arg("-")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    #[cfg(target_os = "linux")]
    {
        use std::os::unix::process::CommandExt;
        let parent = std::process::id() as libc::pid_t;
        // Only Linux syscalls in the post-fork child. If the search worker is
        // cancelled or dies, its extractor must not continue consuming CPU.
        unsafe {
            command.pre_exec(move || {
                if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) != 0 {
                    return Err(io::Error::last_os_error());
                }
                if libc::getppid() != parent {
                    return Err(io::Error::from_raw_os_error(libc::ECHILD));
                }
                Ok(())
            });
        }
    }
    Ok(Extractor(
        command.spawn().context("Start PDF text extraction")?,
    ))
}

fn send(out: &mut impl Write, value: serde_json::Value) -> Result<()> {
    serde_json::to_writer(&mut *out, &value)?;
    out.write_all(b"\n")?;
    out.flush()?;
    Ok(())
}

pub fn run() -> Result<()> {
    #[cfg(target_os = "linux")]
    unsafe {
        // A search is owned by its UI process, including if that UI exits
        // abruptly before it can cancel its jobs. This does not affect the
        // independent document/draft service.
        let parent = libc::getppid();
        if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) != 0 {
            return Err(io::Error::last_os_error().into());
        }
        ensure!(
            libc::getppid() == parent,
            "Search owner exited during startup"
        );
    }
    let mut input = Vec::new();
    io::stdin()
        .lock()
        .take(MAX_INPUT + 1)
        .read_until(b'\n', &mut input)?;
    ensure!(
        input.len() as u64 <= MAX_INPUT,
        "Search request is too large"
    );
    let request: Request = serde_json::from_slice(&input).context("Read search request")?;
    let query = normalized(&request.query);
    ensure!(
        !query.is_empty() && query.chars().count() <= 512,
        "Search needs 1–512 characters"
    );
    ensure!(
        !request.pages.is_empty() && request.pages.len() <= 20_000,
        "Invalid search page count"
    );
    ensure!(
        request.start_index < request.pages.len(),
        "Invalid search starting page"
    );
    let mut keys = BTreeSet::new();
    let mut sources: BTreeMap<PathBuf, PageTargets> = BTreeMap::new();
    for (index, page) in request.pages.iter().enumerate() {
        ensure!(
            page.page > 0 && !page.key.is_empty() && keys.insert(page.key.clone()),
            "Invalid or duplicate search page"
        );
        let path = std::fs::canonicalize(&page.path).context("Locate search source")?;
        sources
            .entry(path)
            .or_default()
            .entry(page.page)
            .or_default()
            .push((index, page.key.clone()));
    }
    let stamps = sources
        .keys()
        .map(|path| Ok((path.clone(), super::source_stamp(&path.to_string_lossy())?)))
        .collect::<Result<BTreeMap<_, _>>>()?;
    let mut out = io::stdout().lock();
    let mut count = 0;
    let mut completed = 0;
    let mut truncated = false;
    for batch in batches(sources, request.start_index, request.pages.len()) {
        let path = batch.path;
        let selected = batch.pages;
        let stamp = &stamps[&path];
        super::require_source(&path.to_string_lossy(), stamp)?;
        let mut child = extractor(
            &path,
            *selected.first_key_value().unwrap().0,
            *selected.last_key_value().unwrap().0,
        )?;
        let mut reader = BufReader::new(child.0.stdout.take().unwrap());
        let mut page = TextPage::default();
        let mut seen = BTreeSet::new();
        let mut flush = |page: &TextPage| -> Result<bool> {
            let Some(targets) = selected.get(&page.number) else {
                return Ok(false);
            };
            ensure!(seen.insert(page.number), "Extractor repeated a page");
            let matches = page.matches(&query, MAX_MATCHES - count + 1);
            for (index, key) in targets {
                let keep = matches.len().min(MAX_MATCHES - count);
                if keep < matches.len() {
                    truncated = true;
                }
                count += keep;
                completed += 1;
                send(
                    &mut out,
                    json!({"t":"search_page", "page_key":key, "page_index":index,
                    "matches":&matches[..keep], "completed":completed, "total":request.pages.len()}),
                )?;
            }
            Ok(truncated)
        };
        let mut stopped = false;
        loop {
            let mut line = Vec::new();
            let bytes = reader
                .by_ref()
                .take(MAX_LINE + 1)
                .read_until(b'\n', &mut line)?;
            if bytes == 0 {
                break;
            }
            ensure!(
                bytes as u64 <= MAX_LINE,
                "Extracted text row exceeds the search safety limit"
            );
            let line = std::str::from_utf8(&line)
                .context("Read UTF-8 text extraction")?
                .trim_end_matches(['\r', '\n']);
            if line.starts_with("level\t") {
                continue;
            }
            let fields = line.splitn(12, '\t').collect::<Vec<_>>();
            ensure!(fields.len() == 12, "Invalid text extraction row");
            if fields[0] == "1" {
                if flush(&page)? {
                    stopped = true;
                    break;
                }
                page = TextPage {
                    number: fields[1].parse()?,
                    width: fields[8].parse()?,
                    height: fields[9].parse()?,
                    ..Default::default()
                };
                ensure!(
                    page.width.is_finite()
                        && page.height.is_finite()
                        && page.width > 0.0
                        && page.height > 0.0,
                    "Invalid extracted page dimensions"
                );
            } else if fields[0] == "5" && selected.contains_key(&page.number) {
                ensure!(
                    fields[1].parse::<u32>()? == page.number,
                    "Mismatched extracted page number"
                );
                page.word(&fields)?;
            }
        }
        if !stopped {
            flush(&page)?;
            ensure!(
                child.0.wait()?.success(),
                "Could not extract text from {}",
                path.display()
            );
            ensure!(
                seen.len() == selected.len(),
                "A selected source page was not found"
            );
        }
        super::require_source(&path.to_string_lossy(), stamp)?;
        if truncated {
            break;
        }
    }
    for (path, stamp) in stamps {
        super::require_source(&path.to_string_lossy(), &stamp)?;
    }
    send(
        &mut out,
        json!({"t":"search_done", "matches":count, "completed":completed,
        "total":request.pages.len(), "truncated":truncated}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn batches_start_at_reader_and_bound_sparse_or_reordered_ranges() {
        let path = PathBuf::from("manual.pdf");
        let source = (1..=1000)
            .map(|page| (page, vec![(page as usize - 1, page.to_string())]))
            .collect();
        let schedule = batches(BTreeMap::from([(path.clone(), source)]), 899, 1000);
        assert_eq!(*schedule[0].pages.first_key_value().unwrap().0, 900);
        assert_eq!(schedule.len(), 2);
        let mut indices = Vec::new();
        for batch in &schedule {
            let first = *batch.pages.first_key_value().unwrap().0;
            let last = *batch.pages.last_key_value().unwrap().0;
            assert_eq!(last - first + 1, batch.pages.len() as u32);
            indices.extend(batch.pages.values().flatten().map(|(index, _)| *index));
        }
        indices.sort_unstable();
        assert_eq!(indices, (0..1000).collect::<Vec<_>>());

        let source = (1..=1000)
            .map(|page| (page, vec![(1000 - page as usize, page.to_string())]))
            .collect();
        let schedule = batches(BTreeMap::from([(path.clone(), source)]), 0, 1000);
        assert_eq!(*schedule[0].pages.first_key_value().unwrap().0, 1000);
        assert!(
            schedule
                .iter()
                .all(|batch| batch.pages.len() <= BATCH_PAGES)
        );

        let source = (1..=1000)
            .map(|page| (page, vec![(page as usize - 1, page.to_string())]))
            .collect();
        assert_eq!(
            batches(BTreeMap::from([(path.clone(), source)]), 0, 1000).len(),
            1
        );

        let source = BTreeMap::from([
            (1, vec![(2, "last".to_owned())]),
            (
                1000,
                vec![(0, "first".to_owned()), (1, "repeated".to_owned())],
            ),
        ]);
        let schedule = batches(BTreeMap::from([(path, source)]), 1, 3);
        assert_eq!(schedule.len(), 2);
        assert_eq!(*schedule[0].pages.first_key_value().unwrap().0, 1000);
        assert_eq!(schedule[0].pages[&1000].len(), 2);
        assert!(schedule.iter().all(|batch| batch.pages.len() == 1));
    }

    fn word(page: &mut TextPage, text: &str, flow: &str) {
        page.word(&[
            "5", "1", flow, "0", "0", "0", "10", "20", "30", "12", "100", text,
        ])
        .unwrap();
    }
    #[test]
    fn phrases_unicode_ligatures_and_flow_boundaries() {
        let mut page = TextPage {
            number: 1,
            width: 100.0,
            height: 200.0,
            ..Default::default()
        };
        word(&mut page, "Café", "0");
        word(&mut page, "Oﬃce", "0");
        word(&mut page, "Next", "1");
        assert_eq!(page.matches(&normalized("CAFÉ\n office"), 20).len(), 1);
        let matched = &page.matches("office", 20)[0];
        assert_eq!(matched.rects.len(), 1);
        assert_eq!(matched.rects[0].x, 0.1);
        assert_eq!(matched.rects[0].height, 0.06);
        assert!(page.matches("office next", 20).is_empty());
        assert_eq!(page.matches("f", 1).len(), 1);
        assert!(page.matches("", 5).is_empty());
    }
    #[test]
    fn reject_invalid_geometry() {
        let mut page = TextPage::default();
        assert!(
            page.word(&[
                "5", "1", "0", "0", "0", "0", "1", "2", "3", "4", "100", "word"
            ])
            .is_err()
        );
        page.width = 100.0;
        page.height = 100.0;
        assert!(
            page.word(&[
                "5", "1", "0", "0", "0", "0", "NaN", "2", "3", "4", "100", "word"
            ])
            .is_err()
        );
    }
}
