# Oma Preview

A small PDF reader and editor for Omarchy. Read, fill, sign, and rearrange pages.
Work by hand or let an agent fill the document in front of you, then make your
corrections before saving. Your originals stay untouched.

<picture>
  <source media="(prefers-reduced-motion: reduce)" srcset="https://github.com/derluke/oma-preview/releases/download/v0.9.0/01-reading-tokyo-night.png">
  <img alt="Oma Preview 0.9: reading, finding text, filling a page, correcting an edit and switching themes" src="https://github.com/derluke/oma-preview/releases/download/v0.9.0/oma-preview-0.9-demo.gif">
</picture>

A little room to work · 30 seconds.
[Watch the MP4](https://github.com/derluke/oma-preview/releases/download/v0.9.0/oma-preview-0.9-demo.mp4) ·
[Try the sample PDF](https://github.com/derluke/oma-preview/releases/download/v0.9.0/A.slower.weekend.pdf)

Captured from the real 0.9.0 app with fictional content. Scripted actions, edited
timing and an illustrated pointer; not a performance benchmark.

<details>
<summary>Closer look: reading, editing and three themes</summary>

Reading in Tokyo Night.

![Continuous reading with lazy page thumbnails](https://github.com/derluke/oma-preview/releases/download/v0.9.0/01-reading-tokyo-night.png)

Editing in Tokyo Night. Formatting appears only when you need it.

![Text selection, resize handle and contextual formatting](https://github.com/derluke/oma-preview/releases/download/v0.9.0/07-editing-controls.png)

The same document in Catppuccin Latte.

![Filled PDF in Catppuccin Latte](https://github.com/derluke/oma-preview/releases/download/v0.9.0/05-editing-latte.png)

And Gruvbox.

![Filled PDF in Gruvbox](https://github.com/derluke/oma-preview/releases/download/v0.9.0/06-editing-gruvbox.png)

Find what matters, without leaving the page.

![Highlighted search results in the continuous reader](https://github.com/derluke/oma-preview/releases/download/v0.9.0/02-find-tokyo-night.png)

</details>

## What works

- Continuous reading, trackpad momentum and pointer-anchored zoom
- On-demand text search with highlighted matches across the current page order
- Collapsible page-preview sidebar: **Pages** or **F9**; only viewport thumbnails render
- Text placed anywhere, including on PDFs with no form fields
- Draw a signature once, retain it locally, and place it again later
- Open several PDFs, reorder or remove pages, and save the result
- Persistent undo/redo for page assembly and annotation edits (up to 100 changes)
- Per-document reading bookmarks
- Live Omarchy colours and a native Wayland window; running windows follow theme changes
- Contextual text formatting (size, Sans/Serif/Mono, black/blue/red) and signature sizing

The original documents are never modified. `Save as…` writes a fresh PDF.

<details>
<summary>How drafts, undo and recovery work</summary>

Use **Ctrl+Z** to undo and **Ctrl+Shift+Z** or **Ctrl+Y** to redo.
While typing, undo affects the text editor; after
finishing, the text edit is one document-level step. Moves and resizes are
one step per gesture. Deleted pages return with their annotations. Adding PDFs
and live agent proposals are undoable too. Export retains the working draft and
history, but undo does not change an already exported file. Reopening the original
document restores both undo and redo, even after undoing back to an unchanged PDF.
Reading bookmarks and the saved signature library are separate from document history.

Edits are atomically autosaved as private, source-fingerprinted JSON drafts in
`~/.local/state/folio/drafts`. Reopening the same source restores its workspace,
including added PDFs, edits, undo/redo and reading position. Closing (or **Ctrl+W**)
saves the working draft and waits for confirmation, without a dialog. A failed
draft write leaves the window open with an error. The quiet **Draft saved** footer
appears only after an acknowledged write. **Ctrl+Shift+W** explicitly discards the
draft and closes, with a confirmation; original and exported PDFs are kept.
Autosave also helps recover after crashes, though edits
since the last completed autosave can still be lost.
Opening another PDF also waits for the current draft to save; if that fails,
the current document and edits stay open.

Drafts reference their source PDFs, including files used only by undo/redo.
If a required file is missing or changed, recovery pauses without replacing the
draft. Restore the original file at its saved location and choose **Try again**,
or **Open another…**. A byte-identical backup copy is accepted even with a new
timestamp. Damaged drafts are also kept rather than silently replaced.

</details>

## Install

[Download the latest release for Arch / Omarchy](https://github.com/derluke/oma-preview/releases/latest), then install the package:

```sh
sudo pacman -U ./oma-preview-0.9.0-1-x86_64.pkg.tar.zst
```

Requires Qt 6.11+. The package does not change your default PDF app.
[Omarchy repository inclusion](https://github.com/omacom/omarchy-pkgs/pull/305)
is still under review. If you used the local installer before, see the
[migration notes](packaging/README.md) to avoid an old binary shadowing the package.

<details>
<summary>Build from source / user-local install</summary>


Arch packaging is in `packaging/PKGBUILD`. It installs the application system-wide
without modifying home directories or changing PDF defaults. The user-local
installer below remains available for development.

```sh
bash native/build.sh
cargo run -- --gui document.pdf
./install.sh
```

The small native input module requires Qt 6.11+, CMake, a C++ compiler,
pkg-config and `wayland-protocols` to build. It receives Wayland hold gestures
inside the app's existing connection: one or two fingers down pause coasting,
while a quick follow-on scroll can continue it. No raw input access, extra
permissions or compositor configuration is needed. Detection timing belongs
to the compositor/libinput; it is not a promise of zero-latency physical contact.
Without hold-protocol support, mouse-press stopping remains available.

The installer is user-local: it puts the binary in `~/.local/bin`, places the
UI and desktop entry under `~/.local/share`, installs the automatically
discoverable `oma-preview` Codex skill under `~/.codex/skills`, and registers
Oma Preview as the default handler for `application/pdf`. It does not write to
`/usr/share/omarchy`.

</details>

## Agent CLI

The GUI and agents use the same Rust export implementation. The agent surface
is intentionally file/JSON based, so it is deterministic and does not require
mouse automation:

```sh
oma-preview inspect input.pdf
oma-preview agent-help
oma-preview review edit.json
oma-preview status
oma-preview edit edit.json
oma-preview verify result.pdf
```

An edit spec chooses pages from any number of source PDFs, establishing merge,
slice, and order in one operation. It can then place text by normalized
top-left coordinates. A saved signature is available as `saved_signature`, but
Oma Preview refuses to use it unless `--allow-saved-signature` is also passed.
`review` opens the proposal on screen for correction and user-controlled export;
`edit` updates that running review in place without restarting the window;
`apply` is the explicitly headless alternative.

`status` reads the live pages, annotations, selection state, and review revision.
Use it before further edits so manual corrections are not lost: `edit` replaces
the entire proposal, it does not merge changes. Updates wait for the window to
confirm loading and refuse while the user is typing or the document is busy.
They preserve the current page and zoom. Connector installation and sign-in are
handled by the agent host, not Oma Preview; verify access before claiming a lookup ran.

The installed `oma-preview` skill advertises this intended workflow to new Codex
tasks globally, including the preference for visible review, output verification,
multiline text, and the separate authorization required for signatures. Agents
working inside this repository also receive the same policy from `AGENTS.md`.

See [AGENTS.md](AGENTS.md) for the required inspect/apply/verify/render workflow.

## Controls

<details>
<summary>Keyboard shortcuts and editing guide</summary>

- Tab / Shift+Tab: move between buttons; Space or Enter activates the focused
  button. Keyboard focus gets an outline without changing the mouse layout.
- `Ctrl+O`: replace the workspace with one or more PDFs
- `Ctrl+Shift+O`: append PDFs
- **Recent**: reopen one of the last ten PDFs; missing files are hidden and
  **Clear recent files** removes the history. Reopening restores its saved draft.
- Reading position, zoom, layout and sidebar visibility are remembered locally
  when you leave a document—even without edits. Changed source files start fresh.
- Left/Right: previous/next page
- Reading is the default: Up/Down scroll; Page Up/Down or Space/Shift+Space move a
  screenful. Continuous layout scrolls across pages with momentum and loads only
  nearby pages. Toggle **Continuous** for single-page viewing. With a text box or
  signature selected, arrows nudge it; Shift+arrows move in larger steps. While
  typing, arrows still move/select text. Pinch zoom preserves its anchor and sharpens the
  PDF after the gesture instead of rerendering on every change.
- `Ctrl+Home` / `Ctrl+End`: first/last page, stopping any active scroll glide
- `Ctrl+G`: go directly to a page in the current workspace. Enter confirms;
  Escape cancels without changing your position.
- `Ctrl+F`: open Find. Enter / Shift+Enter in the field or F3 / Shift+F3 move
  between matches; Escape closes it. Search starts near the current page and
  wraps around; results appear as it works. Moving/removing pages or undoing
  refreshes the results automatically.
- `Ctrl+B`: bookmark the current source page
- Right-click a thumbnail, click its numbered **Page** caption, or press
  `Shift+F10` while reading: bookmark, move or remove that page. Escape closes the menu.
- **Bookmarks**: mark/unmark the current page or jump to a saved page. Long lists
  scroll; Home/End and Enter work within the menu.
- Delete: remove the selected annotation, otherwise remove the current page
- `Ctrl+Shift+S`: save a new PDF
- `Ctrl++` (or `Ctrl+=`) / `Ctrl+-`: zoom, keeping the centre of the view in place
- Two-finger trackpad pinch: smoothly zoom around the mouse pointer
- Rest one or two fingers on the trackpad to pause a glide. Move again promptly
  in the same direction to continue it; holding still or lifting stops it.
  Requires compositor hold-gesture support; clicking also stops motion.

Text and signatures can be dragged after placement. Selected text shows an
open-hand cursor; drag for a closed hand and constrained page movement. Hover
a selected annotation for a quiet movement hint. Arrow nudges use one
PDF point, or ten with Shift, independent of zoom. A quick sequence is one undo
step, including after closing and reopening the draft. Click
**Edit**, double-click, or press Enter to edit; click outside to finish. Escape
cancels a new field or discards changes to existing text. Delete removes a
selection, either from the keyboard or the visible contextual button. **Move up**
and **Move down** in the page menu change page order; **Remove page** slices a
page out. Undo returns to the page that was edited. The toolbar wraps to fit
narrower windows. The signature dialog keeps keyboard focus inside it; Escape
cancels without saving a signature.

Selected text has a right-edge handle for changing the field width without
changing its font size. Selected signatures have a corner handle that resizes
them proportionally. Both handles use their corresponding resize cursors.

Selecting text reveals a slim bottom formatter for point size, font, and ink
colour. Those choices become the defaults for the next text box. Selecting a
signature shows only smaller/larger controls.

Text placement opens an empty field at the clicked baseline. Typing and pressing
Enter commits it, while Shift+Enter inserts a new line; clicking elsewhere
commits and clears the selection. Signature placement returns to Read as soon as
the visible signature is on the page.

Line breaks are explicit (Shift+Enter); text does not automatically wrap, so
the editor and exported PDF use the same lines.

</details>

## Testing

Run the actual UI in isolated offscreen windows, with private fixtures and state:

```sh
cargo build --locked
cargo build --release --locked
bash native/build.sh
python3 tests/offscreen-suite.py
```

The suite covers real button/key flows, draft recovery, page navigation,
bookmarks, lazy rendering, theme changes and raster quality at four display
scales, plus 100-step draft recovery on a large document. It requires the app
dependencies, Python and ImageMagick; it never sends
input to your desktop or changes an open document.

For local page-readiness and zoom-settling measurements on real documents:

```sh
python3 tests/render-performance.py document.pdf another.pdf
python3 tests/history-performance.py large-document.pdf
python3 tests/history-performance.py large-document.pdf pages
```

These offscreen software-rendering measurements are not GPU frame rates.
See [test results](tests/RESULTS.md) for measured scope and remaining caveats.
The older global-input scripts are restricted to a dedicated test desktop;
read [automation safety](tests/SAFETY.md) before using them.

## Deliberate boundaries

Oma Preview treats filling as visible text/signature overlays instead of exposing the
complexity of PDF form internals. Find searches the text in source PDF pages and
highlights whole matching words; it does not OCR scans or search unexported text
overlays. The useful next additions are copy,
rotate, and print/share. They should remain secondary commands rather
than becoming permanent toolbar furniture.

Signatures are stored as normalized vector strokes in
`~/.local/share/folio/signature.json`; bookmarks live in
`~/.local/state/folio/bookmarks.json`. These legacy Folio storage paths and draft
fingerprints are intentionally retained, so upgrading to Oma Preview preserves
drafts, recents, bookmarks and saved signatures without copying private data.

Built with Rust and Quickshell. QtQuick.Pdf renders documents; qpdf handles
page extraction and concatenation; Rust writes Unicode-capable vector overlays.
