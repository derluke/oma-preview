# Oma Preview

A small PDF reader and editor for Omarchy. Read, fill, sign, and rearrange pages.
Work by hand or let an agent fill the document in front of you, then make your
corrections before saving. Your originals stay untouched.

![Oma Preview editing a sample PDF in Tokyo Night](https://github.com/derluke/oma-preview/releases/download/v0.8.1/01-tokyo-night.png)

https://github.com/user-attachments/assets/420d8d09-6072-428c-a137-0430f8a41354

A conversation, a correction, and a finished PDF · 52 seconds.
Pauses cut; editing sped up.

<details>
<summary>Light and warm themes</summary>

Catppuccin Latte

![Oma Preview in Catppuccin Latte](https://github.com/derluke/oma-preview/releases/download/v0.8.1/02-catppuccin-latte.png)

Gruvbox

![Oma Preview in Gruvbox](https://github.com/derluke/oma-preview/releases/download/v0.8.1/03-gruvbox.png)

</details>

The screenshots show the 0.8.2 controls; the video predates that polish.
All form details are fictional.

## What works

- Fast PDF reading with keyboard paging and zoom
- Collapsible page-preview sidebar: **Pages** or **F9**; only viewport thumbnails render
- Native touchpad/touchscreen pinch-to-zoom, anchored under the gesture
- Text placed anywhere, including on PDFs with no form fields
- Draw a signature once, retain it locally, and place it again later
- Open several PDFs, reorder or remove pages, and save the result
- In-session undo/redo for page assembly and annotation edits (up to 100 changes)
- Per-document reading bookmarks
- Live Omarchy colours and a native Wayland window; running windows follow theme changes
- Contextual text formatting (size, Sans/Serif/Mono, black/blue/red) and signature sizing

The original documents are never modified. `Save as…` writes a fresh PDF.

Use **Ctrl+Z** to undo and **Ctrl+Shift+Z** or **Ctrl+Y** to redo.
While typing, undo affects the text editor; after
finishing, the text edit is one document-level step. Moves and resizes are
one step per gesture. Deleted pages return with their annotations. Adding PDFs
and live agent proposals are undoable too. Export retains session history,
but undo does not change an already exported file. Opening another document
or restarting starts a new history; drafts preserve the edits, not the undo stack.
Reading bookmarks and the saved signature library are separate from document history.

Edits are atomically autosaved as private, source-fingerprinted JSON drafts in
`~/.local/state/folio/drafts`. Reopening the same source restores its workspace.
Closing with unexported edits offers Save PDF, Keep draft, Discard, and Cancel;
a crash or forced shutdown is covered by the same autosave.

## Run and install

Arch packaging is in `packaging/PKGBUILD`. It installs the application system-wide
without modifying home directories or changing PDF defaults. The user-local
installer below remains available for development.

```sh
cargo run -- --gui document.pdf
./install.sh
```

The installer is user-local: it puts the binary in `~/.local/bin`, places the
UI and desktop entry under `~/.local/share`, installs the automatically
discoverable `oma-preview` Codex skill under `~/.codex/skills`, and registers
Oma Preview as the default handler for `application/pdf`. It does not write to
`/usr/share/omarchy`.

## Agent CLI

The GUI and agents use the same Rust export implementation. The agent surface
is intentionally file/JSON based, so it is deterministic and does not require
mouse automation:

```sh
oma-preview inspect input.pdf
oma-preview agent-help
oma-preview review edit.json
oma-preview edit edit.json
oma-preview status
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

- `Ctrl+O`: replace the workspace with one or more PDFs
- `Ctrl+Shift+O`: append PDFs
- **Recent**: reopen one of the last ten PDFs; missing files are hidden and
  **Clear recent files** removes the history. Reopening restores its saved draft.
- Left/Right: previous/next page
- `Ctrl+Home` / `Ctrl+End`: first/last page
- `Ctrl+B`: bookmark the current source page
- Delete: remove the selected annotation, otherwise remove the current page
- `Ctrl+Shift+S`: save a new PDF
- `Ctrl++` / `Ctrl+-`: zoom
- Two-finger pinch: smoothly zoom around the point under your fingers

Text and signatures can be dragged after placement. Selected text shows an
open-hand cursor; drag for a closed hand and constrained page movement. Click
**Edit**, double-click, or press Enter to edit; click outside to finish. Escape
cancels a new field or discards changes to existing text. Delete removes a
selection, either from the keyboard or the visible contextual button. **Move up**
and **Move down** at the bottom of the sidebar change page order;
**Remove page** slices a page out. The toolbar wraps to fit narrower windows.

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

## UI regression test

With Oma Preview open, `tests/ui-flow.sh` injects real pointer clicks through uinput,
uses the read-only Quickshell IPC seam to locate controls, types into the actual
text editor, places the saved signature, and removes both test annotations. It
also clicks the contextual formatting controls and checks their model updates.
It does not invoke UI actions through IPC or export a document.

`tests/pinch-flow.sh` creates a temporary two-contact Linux input device and
verifies that native pinch-in and pinch-out gestures change the live zoom level.

`python3 tests/corpus-smoke.py FILE.pdf ...` measures inspection, first visible
Qt render, and real-keyboard page turns. It also checks bookmark persistence and
reopening through the actual Recent menu in an isolated state directory.

## Deliberate boundaries

Oma Preview treats filling as visible text/signature overlays instead of exposing the
complexity of PDF form internals. The useful next additions are search/copy,
rotate, and print/share. They should remain secondary commands rather
than becoming permanent toolbar furniture.

Signatures are stored as normalized vector strokes in
`~/.local/share/folio/signature.json`; bookmarks live in
`~/.local/state/folio/bookmarks.json`. These legacy Folio storage paths and draft
fingerprints are intentionally retained, so upgrading to Oma Preview preserves
drafts, recents, bookmarks and saved signatures without copying private data.

Built with Rust and Quickshell. QtQuick.Pdf renders documents; qpdf handles
page extraction and concatenation; Rust writes Unicode-capable vector overlays.
