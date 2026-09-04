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
