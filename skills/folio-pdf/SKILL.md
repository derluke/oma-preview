---
name: folio-pdf
description: Fill, sign, merge, slice, reorder, or visibly annotate PDFs with Folio when the user should be able to review and correct proposed edits on screen before export. Use for filling PDFs without form fields; do not use for PDF extraction or analysis alone.
---

# Folio PDF

Use Folio's file/JSON interface to prepare the edit, then open its review UI. Do
not automate the GUI to place fields: the proposal should be deterministic and
the visible UI is for the user to inspect and adjust.

1. Confirm `folio` is installed and run `folio inspect INPUT.pdf`.
2. Render the relevant pages when field positions are not already known. Use
   normalized top-left coordinates in the edit spec.
3. Run `folio agent-help` for the current schema, then write a JSON spec with a
   distinct output path. Text may contain `\n` for multiple lines.
4. Run `folio review SPEC.json` by default. Tell the user Folio is showing the
   proposed edits and leave the window open so they can move, resize, edit, add,
   or delete marks before choosing **Save as…**.
5. For further agent changes, update the spec and run `folio edit SPEC.json` so
   the existing review window changes in place without restarting.
   Read `folio status` first and preserve the user's live corrections. An edit
   replaces the full proposal rather than merging. It waits for UI confirmation
   and refuses while the user is typing or Folio is busy; retry after they finish.
6. After the review is exported, run `folio verify OUTPUT.pdf`, render every
   changed page, and visually inspect the result.

Use `folio apply SPEC.json` only when the user explicitly asks for an unattended
export. Never overwrite the source PDF.

Treat signing as separate authorization. A request to inspect or fill a PDF is
not permission to sign it. Use `saved_signature` and
`--allow-saved-signature` only when the user explicitly asked to sign this
specific document. If no signature is stored, omit it from the proposal and let
the user draw one in the review window.
