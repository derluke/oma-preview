# UI automation safety

The old demo sent global input while an unexpected native file dialog remained
open. It continued after focus moved. Do not repeat that workflow.

## Safe default checks (no desktop input)

```
cargo test --locked
bash native/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tests/offscreen-suite.py
```

The suite removes display connections, creates a temporary 2,048-page synthetic
fixture, and runs dialogs, history/input, close/reopen, bookmark/thumbnail,
layout and theme-contrast checks. It fails on the first failing check. Set
`OMA_PREVIEW_TEST_UI` and `OMA_PREVIEW_TEST_BIN` to exercise a matching installed
UI/backend instead of the working tree. Build the development backend first
when testing the working tree (`cargo build --locked`). Real document corpus
and physical trackpad tests remain separate. The native contact module must be
built before UI tests; copied test UIs include it and exercise its real loader.

`python3 tests/native-scroll.py --probe-wayland` is a separate, explicit
read-only compositor check. It creates a hidden Qt window, binds hold gestures
on Qt's existing Wayland connection, and checks availability. It opens no
visible window and sends no input. This proves protocol availability, not
physical finger detection. The ordinary offscreen matrix injects bridge signals
and native Qt events only inside its own process, including one/two-finger hold,
continuation, transition, reversal, lift, long hold and pinch cancellation.

For a long PDF (at least ten pages), `python3 tests/thumbnail-smoke.py INPUT.pdf`
checks viewport-only rendering, navigation to the last page, renderer release
on collapse, selection retention on expand, and retention of overlapping reader
containers while scrolling, all offscreen. `OMA_PREVIEW_TEST_UI` can select an
installed or baseline UI for the same regression check.

The dialog test uses a temporary UI copy, isolated state and Qt's offscreen
platform. It opens/closes the actual Open/Add/Save dialogs and checks that live
review updates are blocked. It never invokes wtype, uinput or the compositor.

`python3 tests/page-menu.py` clicks the actual thumbnail context menu and numbered
caption, exercises keyboard navigation, bookmarks, page edits and undo focus.
It also enters/cancels signature controls using an empty private test-library
entry. It never reads a user's signature, draws one, places one or exports a PDF.
The source fixture is checked for byte-for-byte equality afterward.

`python3 tests/close-recovery.py` blocks only its temporary draft directory to
exercise a real write failure, closes the actual window without a prompt, and
checks matching acknowledgements, restored undo/redo, export baselines, active
text editing, legacy/invalid-history recovery and explicit discard confirmation.
It does not change permissions or storage in the user's state directory.

`python3 tests/open-recovery.py` applies the same private storage-failure fixture
to switching documents through Recent, and checks the successful return to the
original draft, including undoing added PDFs after switching away and back.
Both test PDFs are generated fixtures and remain byte-identical.

`python3 tests/source-recovery.py` creates private PDFs and drafts, then moves,
changes and restores only those fixtures. It covers source files visible in the
workspace or retained only in history, actual recovery buttons, blocked backend
save/export, identical-copy restoration and corrupted/legacy draft handling.
It does not move, corrupt or overwrite any user document or user-state file.

`python3 tests/layout-performance.py LARGE.pdf` measures synchronous QML zoom
work in isolation and checks layout/cache correctness. It supports
`OMA_PREVIEW_TEST_UI` for baseline comparisons. Its timing is not frame rate.

`python3 tests/history-performance.py LARGE.pdf [text|pages]` makes 100 text
changes or page rotations only in an isolated in-memory workspace, persists its
private draft, and starts separate processes to verify recovery and debounced
undo persistence. It never exports or modifies the input PDF. It measures
synchronous editing/save work and acknowledged-save time, not physical input
latency. The suite uses a generated 2,048-page fixture for both workloads.

`python3 tests/native-scroll.py` requires a C++ compiler, pkg-config and Qt Quick
development headers. It sends QWheelEvents only to its own offscreen Qt window,
not to the desktop: trackpad phases, two-axis jitter, repeated/gentle swipes,
fallbacks, native momentum, reversal, cancellation and non-coasting mouse-wheel
steps. It never opens an input device or invokes a compositor/input-injection tool.
The driver also sends mouse press/release/double-click events to that same private
window to check immediate stopping and safe click-through behavior.

`python3 tests/page-raster-identity.py` generates 24 colour-coded, vector-heavy
PDF pages and captures rapid page switches at two screen scales and two render
sizes. ImageMagick checks actual pixels for stale pages and a fully rendered
final page. Its PDF sources/state are private and temporary; diagnostic captures
remain under `output/page-identity-*`. Pending images may be unpainted; wrong-page
pixels and a missing settled page fail the check.

`python3 tests/thumbnail-paper.py` creates three transparent vector PDF fixtures,
captures their thumbnails against dark and light chrome, and checks paper/ink
pixels with ImageMagick. Screenshots are retained under `output/thumbnail-paper-*`;
the source PDFs and application state are temporary and private.

`python3 tests/history-retention.py` performs 1,600 page insert/remove edits in
a private one-page fixture workspace. It counts retained cache records, checks
all 100 undo/redo steps, redo-only pages, discarded branches, clean baselines and
draft encoding. These counts establish cache reachability, not whole-process RSS
or PDF-renderer memory bounds. The input remains byte-identical.

`python3 tests/annotation-scale.py` creates a private 100-page fixture with 2,000
fictional text annotations. In-window QtTest events select, drag, double-click,
type multiline text, format, delete, undo and cancel text boxes. It also checks
page reassignment and live neighboring-page rendering. A re-entry guard prevents
its polling timer from advancing while QtTest is processing nested input events.
It never injects desktop input, exports a document or reads user signatures.

`python3 tests/annotation-keys.py` checks precise and Shift-arrow placement,
zoom-independent movement, grouped undo/redo, page bounds, caret/control focus,
ordinary reading keys, and silent-close/reopen recovery in two isolated
processes. Its signature-shaped annotation is an empty private vector fixture;
it does not draw, save or use a person's signature, or export a PDF.

## Search and Find

Build with `cargo build --release --locked`, then run
`python3 tests/search-worker.py`. Real generated PDFs cover text, phrases,
Unicode, workspace page mappings, current-first batched extraction across 260
pages, sparse/reversed/repeated pages and no-match results. Controlled extractors in
a temporary PATH test result/row limits and cancellation. The cancellation test
terminates only its own worker and checks its resolved child in `/proc`; no
user process or system PATH is changed. Source hashes are checked afterward.

`python3 tests/search-performance.py INPUT.pdf QUERY` measures first streamed page,
first match and total worker time while checking the source hash. It does not
launch a UI, create a draft, persist extracted text or export a PDF. Its streamed
results contain normalized whole-word boxes, not copied document text. The
search worker is separate from the normal document/draft service.

`python3 tests/find-flow.py` uses private generated PDFs and actual in-window
Find field/button/key events. A private pass-through wrapper delays only search
startup, making cancellation deterministic without delaying the draft service.
The test rejects stale replies and checks navigation/highlights, no-match state,
page move/remove/undo, field-local undo, failure retry and narrow layout. Optional
`OMA_PREVIEW_FIND_CAPTURE` saves an offscreen capture to the specified test path;
`FIND_LIGHT=1` changes only that private window's palette.

`python3 tests/find-order.py` tests the real QML controller with a private,
deliberately slow fake search worker. It verifies streaming wraparound before
completion, waiting for unsearched nearby pages, and stable chosen-match identity
when earlier results arrive. It does not read a PDF or connect to the desktop;
real Poppler extraction is covered separately by `search-worker.py`.

`python3 tests/find-performance.py INPUT.pdf QUERY` measures first highlighted
match readiness, completion and a 16 ms UI timer's largest observed gap. It uses
private state and offscreen software rendering, not desktop input or GPU FPS.
Set `FIND_START_PAGE=1900` (1-based) to measure a deep-document starting position;
the harness verifies that navigation completed before starting the search.

`python3 tests/render-performance.py PDF [PDF ...]` measures full-UI page readiness
and zoom settling at 1x/2x, with private state and display connections removed.
It samples ten page destinations and three zoom changes per document, with a
16 ms polling interval and a 32 ms minimum settling gate. Zoom measurements
include the app's debounce. Process memory is sampled from `/proc`; the backend
process is not included. Caches are not flushed. No pages or annotations are
changed, and no exports occur. Results are not GPU frame or physical input times.
Set `OMA_PREVIEW_RENDER_TRACE=1` to log completed raster sizes from the temporary
UI copy. This diagnostic traces image completions, not every attempted decode;
it does not instrument or reconnect to the running user window.

`python3 tests/reader-session.py INPUT.pdf 40 --scale 2 --expect-source-only`
checks a longer single-window reading session. It opens distinct temporary
copies of the source, returns to the first, and samples only its own UI process
memory from `/proc`. State is private and the input hash is verified unchanged.
`--expect-source-only` rejects any retained shared readers; omit it for baseline
measurements of earlier builds or the 1× shared path. The suite uses ten copies
of its generated fixture. Results are lifecycle observations, not a universal
RSS bound or proof of performance across diverse content.
`--max-resident-readers 8` additionally checks settled cache size and shell reuse
at 1×, with a 300 ms settling wait; ordinary observations use 150 ms.

`python3 tests/reader-pool.py` uses generated coloured sources in a standalone
offscreen window. It checks reference pinning, cache retirement, shell reuse,
120 rapid oversized render requests and all twelve revisited pages against an
independent renderer. It also removes only the copied UI's idle resource to
exercise fallback. No user app, source PDF, or installed resource is modified.

`python3 tests/theme-contrast.py` reads installed palette files and evaluates the
app's secondary text and live menu-palette inheritance in a separate offscreen
QML process. It does not activate themes on the desktop. It checks selected
colour roles, not complete accessibility.

## Real interaction tests and recordings

`python3 tests/raster-quality.py SAMPLE.pdf` compares the app's PDF raster with
Qt's standard scalable-image renderer at 1x, 1.25x, 1.5x and 2x. It uses isolated
offscreen windows and ImageMagick (`magick compare`), not desktop scale changes.
Each run switches shared → source-only → shared descriptors and compares every
phase, including a source-only descriptor at 1× during a delayed binding update.
On failure it keeps the two comparison images in a fresh `output/oma-raster-*`
directory. It reads the first PDF page only and does not edit the source.

`python3 tests/visual-smoke.py SAMPLE.pdf` captures narrow/normal reading and
editing layouts into a fresh `output/oma-visual-*` directory. It uses fictional
annotation text, temporary state, and an offscreen Qt process with the display
environment removed. It checks footer geometry; inspect the resulting images
for visual quality. It does not change the desktop theme or export the PDF.

Use a disposable VM or dedicated test desktop, not a daily-use desktop with
terminals, chats, browsers or private documents open. Existing `ui-flow.sh`,
`pinch-flow.sh` and `corpus-smoke.py` are legacy global-input tests. They refuse
to run unless `OMA_PREVIEW_DEDICATED_TEST_DESKTOP=1` is explicitly set. That
variable is an operator assertion, not an isolation mechanism, and those tests
are not a safe recording driver for a shared desktop.

New recording drivers must use `input_guard.py` around input, with bounded
app/compositor queries and exact PID + window-address matching. Require an
expected precondition and observed postcondition for every action. Typing
requires the exact selected text editor and confirmation after each character.
Missing fields, timeouts, dialogs, focus loss or changed process identity must
terminate input, without retries or Escape/Return recovery. Recording teardown
must target only the recorder process created by that driver.

Do not select windows by class or title alone. Do not assume monitor geometry,
fullscreen state, a closed dialog, or successful focus. Validate coordinates
against the target window and monitor immediately before using them. Do not
capture until a visual preflight confirms only the intended sample is visible.

A check followed by global input has an unavoidable race: focus can change
between the two. The guard reduces risk; only a dedicated input environment
keeps unrelated applications out of reach. Do not describe focus checks as
absolute isolation. The failed temporary demo runner is disabled, not repaired
or approved for reuse. No replacement recording has been validated yet.
