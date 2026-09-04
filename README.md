# Folio

Folio is a small PDF reader/editor shaped for Omarchy. Rust handles document
inspection, page assembly, and Unicode-capable vector overlays; Quickshell handles a thin,
theme-aware interface. Rendering is provided by QtQuick.Pdf, while qpdf keeps
page extraction and concatenation structurally safe.

## What works

- Fast PDF reading with keyboard paging and zoom
- Text placed anywhere, including on PDFs with no form fields
- Draw a signature once, retain it locally, and place it again later
- Open several PDFs, reorder or remove pages, and save the result
- Per-document reading bookmarks
- Active Omarchy colors and a native Wayland window

The original documents are never modified. `Save as…` writes a fresh PDF.

## Run and install

```sh
cargo run -- --gui document.pdf
./install.sh
```

The installer is user-local: it puts the binary in `~/.local/bin`, places the
UI and desktop entry under `~/.local/share`, and registers Folio as the default
handler for `application/pdf`. It does not write to `/usr/share/omarchy`.

## Agent CLI

The GUI and agents use the same Rust export implementation. The agent surface
is intentionally file/JSON based, so it is deterministic and does not require
mouse automation:

```sh
folio inspect input.pdf
folio agent-help
folio review edit.json
folio verify result.pdf
```

An edit spec chooses pages from any number of source PDFs, establishing merge,
slice, and order in one operation. It can then place text by normalized
top-left coordinates. A saved signature is available as `saved_signature`, but
Folio refuses to use it unless `--allow-saved-signature` is also passed.
`review` opens the proposal on screen for correction and user-controlled export;
`apply` is the explicitly headless alternative.

See [AGENTS.md](AGENTS.md) for the required inspect/apply/verify/render workflow.

## Controls

- `Ctrl+O`: replace the workspace with one or more PDFs
- `Ctrl+Shift+O`: append PDFs
- Left/Right: previous/next page
- `Ctrl+B`: bookmark the current source page
- Delete: remove the selected annotation, otherwise remove the current page
- `Ctrl+Shift+S`: save a new PDF
- `Ctrl++` / `Ctrl+-`: zoom

Text and signatures can be dragged after placement. Page arrows at the bottom
of the rail change page order; the minus button slices a page out.

Text placement opens the new field immediately with `Text` selected; typing and
pressing Enter commits it and returns to Read. Signature placement returns to
Read as soon as the visible signature is on the page.

## UI regression test

With Folio open, `tests/ui-flow.sh` injects real pointer clicks through uinput,
uses the read-only Quickshell IPC seam to locate controls, types into the actual
text editor, places the saved signature, and removes both test annotations. It
does not invoke UI actions through IPC or export a document.

## Deliberate boundaries

Folio treats filling as visible text/signature overlays instead of exposing the
complexity of PDF form internals. The useful next additions are search/copy,
rotate, undo, and print/share. They should remain secondary commands rather
than becoming permanent toolbar furniture.

Signatures are stored as normalized vector strokes in
`~/.local/share/folio/signature.json`; bookmarks live in
`~/.local/state/folio/bookmarks.json`.
