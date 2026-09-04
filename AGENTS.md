# Folio agent workflow

Folio exposes a stable JSON CLI for PDF work. Prefer it to GUI automation.

1. Run `folio inspect INPUT.pdf` and read the returned page sizes/count.
2. Write an apply spec. Coordinates are normalized from the page's top-left:
   `x: 0.5, y: 0.5` is the center regardless of page size.
3. Run `folio review SPEC.json`. This opens the proposed work in Folio so the
   user can follow it, correct text/placement/page order, and choose when to
   export.
4. While that window remains open, update the spec and run `folio edit SPEC.json`
   to replace the visible proposal without restarting Folio.
   First run `folio status` and reconcile any user corrections with the spec.
   The update replaces the proposal; it is not a merge. It waits for UI
   confirmation and refuses while the user is typing or Folio is busy.
5. Use `folio apply SPEC.json` only when the user explicitly requests an
   unattended/headless export.
6. Run `folio verify OUTPUT.pdf` after export.
7. Render every changed page with `pdftoppm` and visually inspect it.

Run `folio agent-help` for the current schema and an example. Paths in a spec
are resolved relative to the spec file. Page selections accept `all`, individual
pages (`2,5`), inclusive ranges (`1-3`), or mixtures (`1-3,7`).

Never apply `saved_signature` unless the user explicitly authorized signing the
specific document. Folio enforces a second gate: the command must include
`--allow-saved-signature`. Do not treat permission to test, fill, or inspect a
document as permission to sign it.

Do not overwrite source documents. Choose a distinct `output` path, preferably
under `output/pdf/` while working in this repository.
