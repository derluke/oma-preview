# 0.9.0

- Continuous reading with keyboard navigation, page jump and highlighted text search.
- Trackpad momentum, additive repeat swipes and pointer-anchored pinch zoom.
  Wayland hold gestures pause coasting before tap completion; a quick continued
  scroll retains same-direction momentum. Mouse wheels remain precise steps.
- Atomic draft saving on close and document switches, with up to 100 undo/redo
  changes restored on reopening. Missing or changed sources pause recovery safely.
- Restore reading position, zoom and sidebar state without creating an edit draft.
- Lazy thumbnails, bounded reader reuse and lightweight fast-scroll previews;
  avoid displaying the previous page's pixels when switching pages at high DPI.
- Quieter controls, readable thumbnails on dark themes, page actions and improved
  annotation keyboard editing, sizing and focus handling.
- Add an app-local native hold-gesture module (Qt 6.11+), packaged with the UI.
- Expand isolated regression coverage for input, search, recovery, rendering and
  2,048-page documents. Physical trackpad feel and ARM64 remain separate checks.

# 0.8.2

- Collapsible page-preview sidebar (Pages/F9), with viewport-only thumbnail
  rendering and renderer release on collapse; verified against 2,140 pages.
- Use Qt Quick Open/Add/Save dialogs instead of the GTK native dialog path.
- Report process identity, active-window and modal state to agents; reject live
  updates and document shortcuts while dialogs are open.
- Gate legacy global-input tests behind a dedicated-test-desktop opt-in.
- Add a fail-closed input guard and offscreen dialog regression tests to CI.

# 0.8.1

- Reject unknown GUI options with CLI help instead of launching Qt.
- Explain missing display sessions (including SSH) before starting Quickshell.
- Keep version/help and document inspection available without a desktop.

# 0.8.0

- Renamed Folio to Oma Preview (`oma-preview`), retaining private saved data.
- Document undo/redo for page assembly, annotations, formatting and live proposals.
- Coalesced text edits and resize gestures, with native undo while typing.
- Removed pages no longer leave orphaned annotations in export payloads.
- Isolated UI test ShellIds; keyboard undo/redo regression on real PDFs.

# 0.7.0

- Persistent Recent menu, with ten deduplicated paths, missing-file filtering,
  history clearing, and draft-safe reopening.
- Arch/AUR packaging, MIT license, and clean Arch CI builds.
- Real-document rendering benchmarks and bookmark/Recent UI regression tests.
- One bookmark/history request per source, rather than per page, in live reviews.

## 0.6.1

Release polish for visible PDF filling and review:

- `folio status` exposes the running document and annotations, including manual corrections.
- Live edits wait for the UI to confirm loading and reject updates during text entry or other document operations.
- Live updates retain the current page and zoom and clear stale selections.
- Arrow keys move the text caret while editing rather than turning PDF pages.
- Cancelled text edits refresh their draft; opening another PDF preserves the previous draft first.
- Discard cancels pending autosave so discarded edits cannot be recreated by a timer.
- Placement follows the selected font size. Explicit line breaks match the export.

Known boundaries: live edits replace the complete proposal (agents must reconcile
`status` first); automatic text wrapping, undo, search/copy, rotation, and printing
are not implemented. Keep line breaks explicit with Shift+Enter. Google Drive and
LinkedIn connections belong to the agent host and are not supplied by Folio.
