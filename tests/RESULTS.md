# 0.9.0 release checks

- [Clean Arch build and full suite passed](https://github.com/derluke/oma-preview/actions/runs/34041342949).
- [Fresh install of the public x86-64 package passed](https://github.com/derluke/oma-preview/actions/runs/34041352286):
  dependency installation, installed-file integrity/version, and all 25 UI checks
  against `/usr/bin/oma-preview` and its installed UI (including 47 input cases).
- Local `makepkg` verified the tagged source checksum, built the Rust backend
  and native module, and passed 13 Rust/CLI tests. All 25 UI checks also passed
  against the extracted package. Its hidden Wayland probe reports hold support.
- Package SHA-256: `68b6bdabc095732db88e17f4f2fe06883e9f4d2ff2f1d7e3726a240c868585a1`.
- CI-only setup corrections after the source tag build the release backend
  before integration tests and create the screenshot output directory. No
  released application code or package contents changed for these corrections.
- Published as a normal release, not a prerelease. ARM64 and physical trackpad
  feel remain outside the scope of the automated checks.

# 0.8.2 release checks

- Published x86-64 package installed successfully in a fresh hosted Arch container:
  [install run](https://github.com/derluke/oma-preview/actions/runs/33926108067).
  `pacman -Qkk`, version check, installed-UI dialogs and history rendering pass.
- A second physical Omarchy x86-64 desktop upgraded from 0.8.0 to 0.8.2.
  Package SHA-256 matched the release artifact; all 32 installed files were intact.
  Installed-UI offscreen checks passed, followed by the history rendering test
  in its real Wayland/Vulkan session (Qt 6.11.2, Quickshell 0.3.1).
  This used controlled in-window test actions, not global keyboard/mouse injection;
  it is not a claim of a complete manual interaction sweep on that machine.
- Six Rust/CLI tests and six input-guard unit tests pass locally.
- Offscreen dialog and toolbar tests pass at 640, 800 and 1040px widths.
- `tests/history-render.py` exercises first/last-page deletion, undo, redo and
  reordering in the actual QML UI, requiring a ready PDF image after every step.
  It catches the pre-fix blank-render regression. No global desktop input is used.
- `Released package install` is a manually dispatched CI workflow that installs
  the published Arch package in a fresh hosted environment and runs the same
  dialog/history checks against its installed UI and backend. Consult the run
  result for the specific version; this is not a physical Wayland desktop test.

For a deliberate visible desktop regression run, `OMA_PREVIEW_TEST_PLATFORM=wayland`
opts the history test into Wayland/Vulkan. Offscreen is the safe default.

# Continuous-reader regression checks (working tree, 2026-09-05)

## Hold-to-pause and scroll continuation (2026-09-06)

- Added an app-local Qt plugin for Wayland pointer hold gestures v3, using Qt's
  existing connection/pointer through public Qt 6.11 APIs. It does not read raw
  devices or modify compositor settings. Qt's built-in pointer-gesture adapter
  does not currently expose hold begin/end to QML.
- One/two-finger hold begin pauses motion. A real scroll delta within 250 ms
  may reuse same-direction velocity; a cancellation alone never restarts it.
  A completed lift, long hold, explicit stop or pinch discards the credit.
  Reversing direction ignores the old velocity. Synthesized left/right clicks
  that stop a glide are consumed; ordinary clicks subsequently work normally.
- All 47 private native-event cases pass across Flickable and ListView.
  Hold cases emit the actual native bridge's signals and verify the QML path,
  including stopping before any hold end, one-to-two-finger transitions and
  ignoring contact outside the viewport. This is not hardware event injection
  or validation of physical finger detection.
- The actual Quickshell reader test passes hold-stop/continued-scroll assertions,
  including from a relocated UI staged by `packaging/PKGBUILD`. The native leaf
  module loads from a resolved filesystem directory, avoiding Quickshell's
  virtual QML URLs in the native plugin loader.
- A separate hidden, input-free Wayland probe reports the native bridge loaded
  and hold support available on this machine. The compositor/libinput controls
  hold detection timing; physical trackpad feel remains a manual check.
- The complete 25-check offscreen suite passes, including the 2,048-page model,
  draft/history recovery, bookmarks, reader lifecycle and raster identity/quality.
  Eight Rust unit tests, five CLI tests and six input-guard tests pass as well.

## Tap-to-stop and fast-scroll page identity (2026-09-06)

- A click-only layer consumes the press that stops motion, including its double
  tap, but passes ordinary canvas clicks through. It clears pending fallback
  coasting immediately and ignores subsequent native-momentum updates until a
  new gesture. `native-scroll.py` now covers 27 cases across Flickable/ListView,
  including immediate press-time stop, no click-through and normal clicks after
  the double-click interval. `history-render.py` also taps/double-taps the actual
  app with Add text selected and checks unchanged document content.
- The prior high-DPI raster retained page 1's pixels while requesting page 2 in
  the distinct-page fixture. PdfRaster now recreates the image item when its
  page/source identity changes; resize/zoom still retains the same page's image.
- Above 900 logical pixels/s, the continuous reader requests 240px-wide previews,
  then restores full detail after slowing/stopping. The actual-app input test
  checks both the preview size and restoration of full resolution after a tap.
- `page-raster-identity.py` generates 24 uniquely coloured vector-heavy pages.
  It checks immediate captures and captures after several display frames at
  both 1x/2x and full/preview request sizes. Any painted sample must belong to
  the requested page; intermediate captures may be transparent while loading,
  but the settled last page must be present. This catches false page content,
  not just a matching `currentFrame` property. The fixture deliberately exceeds
  rendering throughput at its fastest cadence; this is not a zero-blank-frame
  guarantee or a physical-GPU performance claim.
- The full isolated suite passed, including the expanded image-identity check,
  2,048-page stress and all scale/zoom pixel comparisons. Installed-UI history
  (including actual canvas stop taps) and all 27 native input cases passed.
  No window restart was requested; the preceding UI is retained at
  `/home/lukas/.local/share/oma-preview-ui-NdVXJB`. Physical tap/scroll feel still
  needs user confirmation.

## Trackpad release and thumbnail paper (2026-09-06)

- Reproduced lost coasting through real `QWheelEvent` delivery to an offscreen
  Qt Quick window: a vertical swipe followed by two opposing horizontal pixels
  produced zero post-release travel. Independent per-axis velocity histories
  preserve the primary swipe through that wobble. Finger-on-pad gain stays 5.3.
- The native-event repeat-swipe test also failed with the pair of WheelHandlers:
  the inactive handler rejects zero-delta ScrollBegin, allowing Flickable to
  cancel existing velocity before the next update. A wheel-only MouseArea
  accepts the complete begin/update/end sequence without taking button presses.
- `tests/native-scroll.py` compiles a small Qt Quick test driver and verifies
  vertical/horizontal wobble, gentle release, additive repeat swipes, missing
  phase/end fallback, native momentum without a second glide, direction reversal,
  cancellation and exact non-coasting mouse-wheel steps on both Flickable and
  ListView (19 scenarios, including an angle-only touchpad). These are real Qt
  dispatch tests, **not a physical trackpad or compositor measurement**.
- Transparent PDF thumbnails now have white paper sized to the page's actual
  proportions; the surrounding sidebar still follows the theme. The new
  `tests/thumbnail-paper.py` checks portrait/landscape/square pages on dark and
  light chrome, with pixel checks for white paper and visible black ink.
- The filename shares the file buttons' vertical centre; `visual-smoke.py`
  checks the alignment and captures both narrow and normal-width layouts.
- The complete isolated regression suite passed, including the 2,048-page
  stress fixture. The expanded native-event matrix passed separately afterward.
- Installed locally without requesting a window restart. Installed-UI history
  and all 19 native-event checks passed; thumbnail paper/ink checks also passed
  at 2x scale against the installed UI. Physical trackpad feel still needs the
  user's confirmation. The prior UI is retained in
  `/home/lukas/.local/share/oma-preview-ui-pnKNU9`.

## Real-document readiness measurements (2026-09-06)

`tests/render-performance.py` runs the actual current UI, debug Rust backend,
offscreen software rendering and private state at 1040×720 logical pixels.
These are warm-filesystem-cache observations, with ten sampled page destinations
and three zooms per run. A 16 ms polling interval and 32 ms settling gate limit
resolution; zoom includes the 140 ms debounce. They do not measure GPU frame
rates, physical input latency, or comparative performance against other readers.

| Document | Scale | First ready | Page median / max | Zoom median / max | Sampled UI peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| W-9, 6 pages | 1x | 468 ms | 33 / 48 ms | 175 / 177 ms | 224 MiB |
| W-9, 6 pages | 2x | 471 ms | 55 / 96 ms | 191 / 208 ms | 291 MiB |
| Bash manual, 214 pages | 1x | 483 ms | 32 / 48 ms | 161 / 161 ms | 227 MiB |
| Bash manual, 214 pages | 2x | 500 ms | 40 / 96 ms | 181 / 187 ms | 293 MiB |
| NASA report, 127 pages | 1x | 725 ms | 168 / 560 ms | 336 / 384 ms | 262 MiB |
| NASA report, 127 pages | 2x | 805 ms | 385 / 718 ms | 416 / 484 ms | 345 MiB |
| Repeated Bash, 2,140 pages | 1x | 771 ms | 33 / 47 ms | 160 / 160 ms | 237 MiB |
| Repeated Bash, 2,140 pages | 2x | 817 ms | 71 / 288 ms | 205 / 226 ms | 304 MiB |

A second NASA/stress pass attributed the longest UI timer gaps (91–154 ms) to
opening. Subsequent page/zoom gaps were at most 17–21 ms in those runs, despite
longer asynchronous image readiness. NASA's 2x page median remained 392 ms;
image-heavy rendering throughput and startup pauses remain optimization targets.
RSS is the sampled Quickshell process high-water mark, not combined UI/backend
memory. Source URLs are listed in the historical corpus section below.

### Multi-document reader memory (2026-09-06)

`tests/reader-session.py` opens distinct private copies of one source in a single
window, waits for each page to render, and finally reopens the first copy. It
checks that reading creates no edit history or working drafts. `/proc` samples
report UI RSS/anonymous/file-backed memory, not combined backend memory or GPU
allocations. The source file's hash is unchanged. Copies use different paths
but identical content, so this is a source-lifetime stress test, not a diverse
40-document corpus.

With 40 copies of the 16 MiB NASA report, the initial 1× shared-reader path grew
from 164.3 MiB RSS to 381.2 MiB after returning to the first document, retaining
all 40 `PdfDocument` instances. A private independent-image-only variant ended
at 185.4 MiB, but a subsequent paired NASA readiness test showed a substantial
1× page-median regression: 144 ms shared versus 255.5 ms independent. That
blanket change was not adopted.

At high DPI the raster already uses the independent image path for correct
scaling. The app now carries only the source URL there, avoiding an unused
shared document and its synchronous load. This preserves 1× shared rendering.
A source-only marker keeps descriptor transitions on the compatible raster
path while delayed window bindings update.

Paired 2× 40-copy observations:

| Stage | Previous RSS | Source-only RSS | Previous / new retained readers |
| --- | ---: | ---: | ---: |
| First document | 185.4 MiB | 182.5 MiB | 1 / 0 |
| 20 documents | 278.9 MiB | 191.5 MiB | 20 / 0 |
| 40 documents | 377.8 MiB | 200.0 MiB | 40 / 0 |
| Return to first | 378.3 MiB | 201.1 MiB | 40 / 0 |

Settled-open observations were roughly 475–550 ms in both 2× runs; these
include a deliberate 150 ms settling wait and are not pure rendering timings.
The isolated suite now checks ten source-only documents at 2×. Raster-quality
checks switch shared → source-only → shared at 1×, 1.25×, 1.5× and 2× and compare
pixels against Qt's standard image path. This is not a physical monitor-move
test. The 1× retention problem and lifetime-safe eviction remain open; documents
previously opened at 1× are not freed merely by moving the window to high DPI.
The full isolated regression suite passed. The UI was then installed locally,
retaining the previous copy without requesting a window restart. Installed-copy
history/editing/bookmark/export and Find flows passed at 2×, as did ten NASA
source copies with zero shared readers and all twelve raster comparisons.

Ownership investigation used Qt's [shared image implementation](https://raw.githubusercontent.com/qt/qtwebengine/6.11/src/pdfquick/qquickpdfpageimage.cpp),
[document implementation](https://raw.githubusercontent.com/qt/qtwebengine/6.11/src/pdfquick/qquickpdfdocument.cpp),
and [asynchronous image queue](https://raw.githubusercontent.com/qt/qtdeclarative/6.11/src/quick/util/qquickpixmapcache.cpp).
No upstream source was copied, and no timed or speculative eviction was added.

### Shared-reader pool (2026-09-06)

Follow-up work replaces unbounded 1× source retention with a soft eight-reader
LRU. Visible rasters hold explicit references; active documents are never
selected for retirement, even if their count exceeds the cache target. A
retired reader switches to a bundled, original, blank 1-point PDF through Qt's
source setter. This releases the source's parsed resources while retaining its
QObject shell and allowing Qt to defer carrier-device cleanup. New sources
reuse idle shells. Shells stay parented to the window; they are not destroyed
on a timer. Missing idle data restores the original source and disables
retirement for that session rather than repeatedly attempting a failed cleanup.

An early private source-switch prototype exposed a return-to-file binding loop.
Pool bookkeeping now uses plain metadata, not QML flags read and changed within
the document lookup binding. The subsequent 40-source NASA session passed:

| Stage | Cached full sources | Allocated shells | UI RSS |
| --- | ---: | ---: | ---: |
| First source | 1 | 1 | 164.3 MiB |
| 10 sources | 8 | 9 | 210.8 MiB |
| 20 sources | 8 | 9 | 210.1 MiB |
| 40 sources | 8 | 9 | 210.0 MiB |
| Return to first | 8 | 9 | 209.5 MiB |

The earlier unbounded 1× session ended at 381.2 MiB. These are repeated copies
of one source, offscreen software rendering and UI-only RSS. The bounded-cache
assertion waits 300 ms after readiness to allow the 200 ms trim timer to run;
its settled-open times therefore cannot be compared directly with the earlier
150 ms settling measurements. A separate pooled NASA rendering run observed
160 ms page median and 335 ms zoom median at 1×, preserving the shared path
instead of adopting the slower independent-only experiment.

`reader-pool.py` verifies pinned readers, retirement, shell reuse, a missing-idle
fallback, and 120 rapid source switches with oversized asynchronous rendering
requests. It allocated three shells for a two-source cache, then revisited all
twelve sources; every captured page matched an independent render. This test
does not prove that every intermediate
frame is correct under every scheduling interleaving. The full app suite also
passed with the pool, including drafts, undo, exports and raster scaling.
The PKGBUILD package function was exercised against a private staging directory;
its UI matched the working tree, the bundled idle PDF passed `qpdf --check`, and
the full isolated suite passed against those staged package files. This does
not constitute a new published package or a clean-machine dependency install.
The matching UI was installed locally without requesting a window restart.
Installed-copy pool/revisit/fallback tests, twelve NASA sources with the settled
eight-reader limit, and document-switch/draft recovery passed. That later run
observed about 1.05–1.30 seconds settled readiness (including the 300 ms wait),
so the earlier timing observations should not be treated as portable guarantees.

## Page-local annotation rendering and interaction (2026-09-06)

`tests/annotation-scale.py` uses 2,000 fictional text annotations across a private
100-page synthetic PDF, with 20 annotations per page. The previous editor
allocated 2,000 Loader delegates even though only 20 belonged to its page. The
editor and neighboring continuous-reading pages now create only their own
annotation delegates. The same fixture's editor count is 20. Source indices
remain document-global for the agent interface.

One baseline setup/settle observation was 269 ms; working-tree runs measured
142–148 ms and the installed-UI recheck 173 ms, using the installed release
backend and offscreen software rendering. This
includes fixture insertion, a history snapshot and a 60 ms polling interval;
it is not a measure of GPU frame rate, typing latency or whole-process memory.

Actual in-window pointer/key events verify selecting and dragging a later-page
box, move undo without viewport drift, double-click editing, retained editor
identity/focus while typing, multiline text, deletion/undo, formatting controls,
new-box focus, Escape cancellation and safely removing an empty box with Enter.
Page reassignment and neighboring-page live text updates are checked too. These
flows caught an existing undo viewport bug: temporarily suspended page metrics
clamped the viewport to zero, so its reading marker then selected page one.
Undo/redo now restore the view before that queued marker update.

Two preliminary offscreen test processes aborted during failure shutdown at
09:35 BST (PIDs 84652 and 84769). Qt reported destruction during an active signal
handler/nested event loop. The extracted core was incomplete and did not yield a
usable full backtrace; there was no OOM evidence. Re-entrant test timer execution
during QtTest's nested input processing was the leading explanation. Guarding
that timer and deferring failure shutdown eliminated the fatal error in later
runs. This was private test state, not a user's window or documents; the extracted
core copy was removed, and system-managed crash retention was left unchanged.

## Keyboard placement (2026-09-06)

`tests/annotation-keys.py` exercises real in-window arrow and Shift-arrow input
on a private text box and empty vector fixture. Arrows move a selected
annotation by one PDF point, Shift by ten, without changing pages; bounds use
the displayed field dimensions. Nearby nudges merge into one undo step, while
a net-zero sequence removes its own step. Every nudge still updates draft state;
there is no delayed, unrecorded edit waiting for a grouping timer.

Tests cover undo/redo, movement at two zoom levels, visual/model agreement,
edge clamping without redundant history, native text caret/selection, focused
toolbar controls, unselected reading arrows and recovery in a separate process.
The document is never exported and source bytes remain identical.

## Search worker and Find UI (2026-09-06)

The private `--search-worker` command accepts one JSON-line request on stdin:
`query` and workspace `pages` containing `path`, 1-based source `page`, and unique
`key`, plus optional 0-based `start_index` (default 0). It emits `search_page` events with the original workspace index/key and
normalized whole-word rectangles grouped by match, followed by `search_done`.
Callers must discard a failed/cancelled generation; final success is explicit.
No source file is changed and extracted text is not persisted.

The worker uses the already-required Poppler extractor, independently of the
renderer and draft service. Its Linux child inherits a parent-death signal;
controlled cancellation tests verify the extractor terminates when the worker
does. The [Qt search implementation](https://github.com/qt/qtwebengine/blob/6.11/src/pdf/qpdfsearchmodel.cpp) advances one page per 100 ms timer
tick; choosing a separate worker avoids that default pacing and main-UI parsing.
This is not a comparative benchmark against a completed Qt-based application.

Release-worker measurements with warm filesystem caches on the local corpus:

| Document / query | First page | First match | Complete | Matches |
| --- | ---: | ---: | ---: | ---: |
| Repeated Bash, 2,140 pages / shell function | 34 ms | 42 ms | 7,728 ms | 980 |
| NASA, 127 pages / space | 20 ms | 20 ms | 627 ms | 307 |
| W-9, 6 pages / taxpayer | 19 ms | 19 ms | 37 ms | 12 |

These measure worker output, not visible-highlight latency or UI responsiveness.
Tests cover real text/phrase/Unicode matching, common ligatures, flow boundaries,
reordered/repeated/removed workspace pages, empty/image-only matches, malformed
requests, explicit 10,000-result truncation and bounded extraction rows. The
source PDFs remain byte-identical. Highlights cover whole words, including when
the query matches a substring. There is no OCR, accent folding, full Unicode case
folding, or draft-overlay search yet.

Find is now connected through a floating Ctrl+F bar confined to the document
area, with next/previous controls, an updating count, and a whole-word highlight.
It reserves space below a restored-draft notice instead of covering it. Each
query owns a separate cancellable process generation; late replies are ignored.
Search refreshes after page operations and undo, and does not steal active text
editing or find-field caret/undo keys. Closing Find clears highlights and stops
work; opening a new PDF clears the old query only after successful inspection.

The generated-fixture interaction test covers actual typing, buttons, F3,
Escape/button cancellation, stale replies, no-match state, Enter retry after a
search error, page move/remove/undo and a 640px window. It also checks that Find
stays below the restored-draft notice and reclaims the space after dismissal.
Light and dark captures were visually checked. Source bytes are
unchanged and searching alone creates no edit history.

Real-document UI observations include the 180 ms typing debounce, page-image
readiness and 16 ms polling, using offscreen software rendering:

| Document / query | First ready highlight | Complete | Largest observed UI timer gap |
| --- | ---: | ---: | ---: |
| Repeated Bash, 2,140 pages / shell function | 268 ms | 8,124 ms | 23 ms |
| NASA, 127 pages / space | 238 ms | 814 ms | 18 ms |

These do not prove physical input latency, GPU frame rate, or responsiveness on
every document. The full isolated regression suite and worker tests pass.

A final 2,140-page rerun observed a 268 ms first highlight, 8,587 ms completion,
and a 26 ms largest UI timer gap while other regression checks were running.
The matching release binary and UI were installed locally without restarting
the user's window; the prior binary and UI were retained for rollback. This is
a local development update, not a new published release.
The full isolated UI suite and search-worker checks also passed against that
installed copy, including draft-notice placement and retry after search failure.

### Current-region search (2026-09-06)

Searching from page 1,900 of the repeated 2,140-page Bash manual exposed a
7,439 ms first-highlight delay (8,334 ms completion): the worker still extracted
from the beginning. The worker now plans contiguous selected-page regions
of at most 128 pages, splitting at the current source page and prioritizing by
cyclic workspace position. Adjacent forward ranges in that schedule share an
extractor: a normal document needs one run, or two when wrapping, independent
of its length. Reordered/interleaved ranges keep bounded priority regions.
Repeated pages share extraction, with the visible copy prioritized; gaps are
not extracted. Source stamps are checked before and
after each batch and again before successful completion. Result indices remain
in workspace order, independent of extraction order.

The initial batched implementation observed a 321 ms first highlight and
8,773 ms completion. Before adjacent-range coalescing, additional runs observed:

| Start page | First match page | First ready highlight | Complete | Largest UI timer gap |
| ---: | ---: | ---: | ---: | ---: |
| 2,140 | 2,140 | 305 ms | 8,736 ms | 25 ms |
| 1 | 3 | 272 ms | 8,703 ms | 25 ms |

Final release build, with adjacent-range coalescing:

| Start page | First match page | First ready highlight | Complete | Largest UI timer gap |
| ---: | ---: | ---: | ---: | ---: |
| 1,900 | 1,906 | 320 ms | 8,240 ms | 24 ms |
| 1 | 3 | 270 ms | 8,207 ms | 24 ms |

These remain local offscreen/software observations, not physical-input or
cross-application benchmarks. Scheduling favors current-region latency and
avoids extracting removed pages; coalescing avoids repeated source parsing for
ordinary linear documents.

The controller now wraps to a known first match as soon as all intervening
pages have been searched, rather than waiting for the whole document. A
controlled streaming-worker test proves that it neither skips unsearched nearby
pages nor changes the chosen match when earlier results arrive. Real-extractor
tests cover 260-page batch boundaries, reversed and sparse workspaces, repeated
source-page identities and invalid starting positions.
The final coalescing build was installed locally, retaining the prior binary/UI
without requesting a window restart. The full isolated suite and worker checks
passed against the installed copy, including current-copy priority at the
10,000-match cap. Rust unit/CLI tests and warning-free Clippy also passed.

## Persistent-history measurements (2026-09-06)

`tests/history-performance.py tmp/corpus/2140-pages.pdf` exercised 100 committed
text changes on the repeated 2,140-page Bash manual, saved through the real
backend, then reopened in a separate process and checked undo/redo. Both runs
used offscreen software rendering, the same debug backend, local temporary
storage and warm filesystem caches. These are observations, not portable timing
guarantees or measurements of physical interaction latency.

| Measurement | Full repeated snapshots | Shared page layouts |
| --- | ---: | ---: |
| Draft size | 54,967,491 bytes | 1,370,824 bytes |
| 100 edits, synchronous total | 2,024 ms | 195–201 ms |
| Slowest edit | 32 ms | 3–4 ms |
| Synchronous save preparation/dispatch | 654 ms | 14–15 ms |
| Save through observed acknowledgement | 3,175 ms | 90–109 ms |
| Reopen process including undo/redo check | 7.028 s | 0.964–0.975 s |
| Reopened undo + redo, synchronous | 1,478 ms | 45–48 ms |

History snapshots now share immutable page layouts, draft JSON stores each
distinct layout once, and text-only undo does not reset the page model. Tests
check snapshot invalidation on dimension changes, reordering and same-count
replacement; old uncompressed schema-2 history migrates without losing undo or
redo. The isolated suite includes a 2,048-page/100-edit persistence regression.
These are the first, layout-sharing measurements; the subsequent page-operation
work below changes the history representation again.

### Page rearrangement history

`tests/history-performance.py tmp/corpus/2140-pages.pdf pages` rotates the first
page to the end 100 times, creating 101 distinct layouts. The former format
repeated page records across those layouts. The current format stores immutable
page records once and represents ordinary moves, insertions and deletions as
validated changes from earlier layouts. Complex changes can still use a full
page order. The same 2,140-page document and offscreen/debug setup were used.

| Measurement | Whole layouts | Compact page operations |
| --- | ---: | ---: |
| Draft size | 51,972,322 bytes | 1,379,030 bytes |
| 100 moves, synchronous total | 1,443 ms | 1,582 ms |
| Slowest move | 26 ms | 27 ms |
| Synchronous save preparation/dispatch | 657 ms | 27 ms |
| Save through observed acknowledgement | 3,137 ms | 130 ms |
| Reopen including undo/redo check | 6.216 s | 1.521 s |
| Reopened undo + redo, synchronous | 2,078 ms | 27 ms |

Undo now applies local page moves/splices where possible and coalesces draft
writes with the same 600 ms debounce used for editing. The last row therefore
compares immediate UI work, not time until the undo has reached disk. Separate
autosave/reopen processes verify the debounced undo and redo stack really persist;
closing still flushes and awaits the latest state. Repeated rearrangement runs
passed. Individual move costs did not materially improve. A follow-up text run
measured 262 ms for 100 edits, 24 ms dispatch and 19 ms for undo/redo, versus the
earlier text-only figures above; this is not an across-the-board speedup claim.

Codec checks cover move, deletion, insertion, changed dimensions, arbitrary
reversal, invalid references and cyclic/forward bases. Both older full snapshots
and page-layout-only drafts still restore. Internal cache metadata is excluded
from draft JSON. Large annotation sets, memory growth in long sessions, and
histories of bulk/random rearrangements still need separate measurements.

### Long-session history retention

`tests/history-retention.py` performs 800 page insert/remove cycles (1,600 edits)
in a private generated one-page workspace. Before the fix, the page-record cache
retained all 801 identities despite the 100-step undo limit. It now periodically
collects records no longer reachable from the current state or either history
stack. The same run retains 85 records between collection points; an explicit
collection retains exactly the 51 still needed by the workspace and history.
Metadata holds a generation token rather than a reference to the entire cache,
so outdated snapshots do not themselves retain discarded cache generations.

The test checks every retained undo/redo step, redo-only page identities,
discarded redo branches, the clean-content baseline, serialized metadata
exclusion, acknowledged persistence and recovery in a separate process. The
source PDF remains byte-identical. These are retained-object counts, not process
RSS measurements or bounds on PDF-renderer memory. The existing 2,048-page
history/save/reopen and full offscreen regression checks also pass.

An uninstalled experimental weak-key cache triggered a SIGSEGV in the isolated
test process at 08:38 BST (PID 55564). The core identified QV4 value comparison
in Qt's JavaScript engine, not a PDF render worker; the journal showed no OOM
kill. The precise engine fault was not resolved from the available stack.
Weak-key caches were removed from the history implementation. Three consecutive
large rearrangement runs and the expanded regression suite then passed without
another coredump. The extracted diagnostic core copy was deleted; the system's
normal coredump retention was left unchanged. No user document or installed UI
was involved in the failed experiment.

## Functional and visual regression checks

- Page-action polish (2026-09-06): the selected thumbnail now has one numbered
  menu caption, rather than a separate number and ambiguous `Page…` label.
  Right-click targets the clicked thumbnail; Shift+F10 opens the current page's
  menu even with the sidebar collapsed. Actual clicks cover bookmark toggling,
  move/remove and undo, while preserving the source PDF. Opening a menu on the
  current page preserves reading position. Undo now targets the page just edited,
  not the earlier reading position stored when the history head was created.
  The click-through test exposed zero-width page/signature menus after the native
  background had been replaced; the shared theme now supplies the missing width
  hint. Menu entries, not just popup visibility, are tested. Signature controls
  enter and cancel placement mode without placing any mark; the drawing dialog
  now uses a modal popup with initial Cancel focus, trapped Tab navigation and
  Escape cancellation. Light/dark menus and the empty dialog were visually checked.

- Draft-safe document switching (2026-09-06): a dirty workspace waits for its
  matching draft-save acknowledgement before inspecting a replacement PDF.
  The real Recent-menu test blocks private draft storage with ENOTDIR and
  verifies unchanged content, a visible error, and cancelled pending switching.
  A successful switch-and-return flow restores the original page edit. Unrelated
  autosave acknowledgements cannot release the switch; source hashes are stable.

- Silent draft closing and persistent history (2026-09-06): normal close waits
  for its exact save acknowledgement without a dialog; older autosave replies
  cannot close the window. Separate process launches restore both history stacks,
  redo from an unchanged document, and the exported clean baseline. Export keeps
  the working draft. Legacy drafts and malformed history retain the visible edits
  with a fresh history. A private ENOTDIR failure keeps the window and edits open.
  Explicit discard still confirms deletion. Source PDF bytes remain unchanged.
  Adding a PDF keeps the original workspace identity, so returning through Recent
  restores the assembled pages and their undo history.
  The full isolated suite passes, and close/reopen recovery also passes against
  the installed user-local UI/backend. Normal closing was not driven through the
  user's desktop. Added-source recovery is now covered by the separate checks below.

- Source-safe recovery (2026-09-06): `source-recovery.py` exercises both visible
  added PDFs and files retained only in redo history. Missing/moved and changed
  sources open a modal recovery prompt, block agent edits, and leave draft bytes
  unchanged. Actual Open/Cancel and Try again buttons are exercised; repairing the
  file restores pages/history in the same process. A copied original with a new
  timestamp is recognized by its saved SHA-256. Backend requests also verify that
  a source changed after inspection prevents save/export, with no output created.
  Corrupt drafts remain intact; older unstamped drafts gain stamps on the next
  successful save. The recovery prompt was visually inspected at 640px width.
  Metadata checks avoid hashing on every edit; first-save hashes and hashes after
  metadata changes support identical-copy recovery. This is not continuous file
  watching, a lock against concurrent writers, or detection of byte changes that
  deliberately preserve both length and modification time. Pre-stamp legacy
  drafts cannot retroactively establish whether an added file's contents changed.

- Zoomed-out navigation (2026-09-06): page positioning is clamped to the scroll
  extent, including last pages shorter than the viewport and documents that fit
  entirely on screen. Explicit navigation retains the chosen page until the
  vertical scroll position changes. The regression reproduced blank-space
  overscroll before the fix and now checks Ctrl+End, Left/Right selection with
  both pages visible, and resumption of automatic page tracking after scrolling.

- Navigation/momentum arbitration (2026-09-06): Ctrl+Home/End and thumbnail
  clicks use the explicit page-jump path, including when that page is already
  selected. Keyboard page/scroll commands cancel queued or active coasting.
  The UI regression reproduced same-page Ctrl+Home drift before the fix and now
  checks first/last-page settling, a pending fallback glide followed by Down,
  and clicking the current thumbnail to return to its top.

- Initial raster sizing (2026-09-06): tracing reproduced completed 1,000-pixel
  neighbor renders immediately followed by 786-pixel renders. Nearby pages now
  receive their initial layout width before loading; the current page sizes its
  raster when its source arrives. Later resizing remains debounced. Traces show
  no 1,000-pixel intermediates, and the first main raster matches the display
  width. The history test checks that first size and that pinch input does not
  change raster size before release. Render-status telemetry now explicitly
  qualifies the image status, avoiding the identically named footer item.
  Follow-up warm local runs measured NASA first-ready at 528/667 ms (1x/2x),
  versus the prior 725/805 ms observations; its 2x page median was 313 ms, with
  a still-slow 704 ms maximum. Repeated Bash first-ready was 649/642 ms.
  These are local observations with the same offscreen harness, not statistical
  guarantees or GPU frame-rate measurements.

- High-DPI raster quality (2026-09-06): a rendered comparison reproduced blurry
  2x output from Qt's shared-document PdfPageImage path. PdfRaster retains that
  path at 1x and uses Qt's standard scalable Image path above 1x, without manual
  double-scaling. Output matches the reference pixel-for-pixel at 1, 1.25, 1.5
  and 2x on both the vector fixture and sample form. The full UI suite passes at
  2x; active thumbnail counts remain bounded. This is offscreen raster evidence,
  not physical monitor-switch or high-DPI frame-time evidence.

- Direct page navigation (2026-09-06): Ctrl+G opens a small themed page-number
  prompt without another toolbar control. The 2,048-page UI fixture tests real
  key input, zero/out-of-range rejection, Enter and Go-button navigation,
  cancellation, and blocking live proposals while the prompt is open. Renderer
  counts remain viewport-bounded. The prompt was visually inspected at 640 px.

- Shared menu themes (2026-09-06): Recent, Bookmarks, page actions and signature
  actions use one themed in-window menu component. The palette test checks live
  background/text/selection propagation to menu items across 24 palettes. An
  open, keyboard-highlighted Bookmarks menu was visually checked before and
  after an isolated dark-to-light palette change. No desktop theme was changed.

- Recent-menu polish (2026-09-06): filenames lead each two-line entry, with the
  parent folder underneath and the full path available on hover/accessibility.
  The menu follows the app palette, stays below the toolbar and within window
  bounds, and supports Home/End. A 20-entry UI regression reaches and opens the
  last item with End/Return. The narrow-window capture includes duplicate names
  in distinct folders and long filenames, and was visually inspected.

- Transactional opening (2026-09-06): inspect responses are collected by request
  ID and committed in requested order only after the entire batch succeeds.
  The real UI test clicks a missing Recent entry with unsaved text present,
  checks unchanged content/draft identity, rejects a mixed valid/missing Add
  batch without partial changes, then opens a valid PDF successfully. The
  previously installed UI loses its page list in this scenario. This is an
  opening/inspection check, not a guarantee against later render failures.

- Restore-notice polish (2026-09-06): Dismiss uses the shared accessible button,
  including visible keyboard focus and Space activation. A constrained-width
  regression checks wrapping and containment; fresh offscreen captures were
  visually inspected at 640 and 1040 px, including the restored-draft notice.

- Gentle coasting (2026-09-06): finger-on-pad gain stays 5.3. Release braking
  scales with velocity, so small swipes settle over roughly 650 ms instead of
  stopping almost instantly. Delayed zero-delta ScrollEnd events preserve the
  release estimate. The offscreen history test verifies unchanged direct travel
  and actual Flickable motion 450 ms after a gentle, delayed release. Horizontal
  wheel input and diagonal release are covered too. Phased trackpad events are
  simulated; this does not establish physical trackpad feel.

- Scroll interruption checks (2026-09-06): a missing-end fallback glide stops
  without a jump when direct movement resumes; reversal discards old momentum.
  A regression reproduced stale native-momentum state after an explicit stop
  (used by zoom and bookmark navigation), suppressing subsequent phase-less
  coasting. Stop now clears the gesture timestamp and native-momentum flag.

- Backend failure isolation (2026-09-06): errors carry request ID and operation.
  CLI tests verify that context for failed inspect/export requests. The actual
  UI test injects a reading-state write failure during a simulated export and
  checks that editing remains locked. Background persistence failures no longer
  clear an unrelated foreground busy state.

- Export recovery (2026-09-06): `tests/export-recovery.py` deletes a fixture page,
  attempts a prohibited source overwrite, retains the draft across an actual
  close/reopen, and retries to a distinct output. It verifies unchanged source
  SHA-256, the restored edit, a one-page output and qpdf validity. Save failures
  leave controls usable, keep their error visible, and clear stale close intent.

- Busy/export states (2026-09-06): continuous geometry and page images remain
  present during export rather than being cleared by the busy flag. The history
  test checks a stable extent/scroll offset, visible save status, and rejection
  of Delete, Undo and Open shortcuts while busy. It then performs a real export,
  waits for completion, and runs qpdf structural validation on the result.

- `tests/offscreen-suite.py` now combines the isolated checks with a generated
  2,048-page fixture. The Arch build workflow invokes it. Release-install checks
  check out the selected release tag's tests to avoid testing an older package
  against unreleased APIs. These workflow changes are local until pushed; a
  hosted CI run has not yet verified them.

- Bookmark navigation (2026-09-06): actual button/menu clicks cover opening,
  jumping and removing a bookmark; Ctrl+B still toggles. The large-document test
  populates 40 entries, uses End to focus the last entry, checks it is within the
  clipped menu viewport, and presses Enter to jump. The bookmark popup is also
  covered by the modal/live-edit rejection checks.

- Secondary-text contrast (2026-09-06): the actual QML palette output is checked
  against its chrome background by `tests/theme-contrast.py`. Four of the 22
  installed palettes failed the 4.5:1 target before the adjustment; all now pass,
  with a measured minimum of 4.645:1. The adjustment increases foreground
  contribution only where needed. This covers secondary labels, not every
  control state or full WCAG conformance. Reference:
  https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html

- Layout work (2026-09-06): `tests/layout-performance.py tmp/corpus/2140-pages.pdf`
  measures 120 synchronous zoom changes and reads the resulting extent. The
  array-rebuilding baseline took 235–239 ms locally; cached source proportions
  took 3–5 ms over repeated runs. This excludes frame presentation and is not an
  FPS or end-to-end pinch-latency benchmark. The same check compares every page
  position with a direct calculation and verifies invalidation after changing
  a page's size and moving it to the end. Source metrics stay identical during
  zoom; rendered geometry is calculated on demand.

- Toolbar keyboard checks (2026-09-06) exercise real QtTest Tab/Backtab, Space,
  Return and Delete events. Focused buttons activate once, show visual focus,
  and reserve reading/deletion keys until focus returns to the document.
  Button roles and symbolic labels are exposed to accessibility APIs; this is
  not a screen-reader validation claim.

- Visual review on 2026-09-06: `tests/visual-smoke.py` captured reading/editing at
  640px and 1040px. The footer now bounds and elides long status messages and
  uses readable secondary text for informative labels. Footer geometry checks
  pass; dark-theme captures were manually inspected. This is not a full theme
  or accessibility audit.

- `tests/reading-position.py` (2026-09-06) closes and reopens the actual UI in
  separate offscreen processes with shared isolated state. It verifies clean
  reading restores page, zoom, sidebar and scroll offset without creating an
  edit draft or showing an unsaved-edits notice. A modified source ignores the
  stale view state. No source PDF is overwritten by the app.

- `tests/history-render.py` passes offscreen with actual QtTest wheel, keyboard
  and pinch input. It checks a known viewport zoom anchor after scrolling.
  Actual zoom-button clicks and keyboard zoom also preserve the reading position
  on the second page of a continuous document.
  Precise trackpad deltas and phase sequences additionally exercise the scroll
  handler directly: travel, release glide, and additive repeat-swipe momentum.
  These checks do not establish physical trackpad feel or native gesture delivery.
- `tests/thumbnail-smoke.py tmp/corpus/2140-pages.pdf` passes with at most four
  active sidebar thumbnails. A new lifecycle assertion verifies that moving the
  visible page range retains overlapping reader containers. The previous
  installed UI fails that assertion; the incremental ListModel implementation
  passes. This measures container retention, not GPU frame timing or every image
  decode (the selected page still switches between reader/editor presentations).
- Dialog/modal regressions pass. These are isolated offscreen checks and send
  no global desktop input. Comparative browser/Preview frame-time and physical
  trackpad measurements remain outstanding; no best-in-class claim is established.

# 0.7.0 desktop validation

Tested on Omarchy, Qt 6.11.2 / Quickshell 0.3.1, Wayland with Vulkan rendering.
Times include process startup, inspection, Qt loading, and IPC polling for the
first visible page. Page-turn measurements include keyboard input and polling,
not just rasterization. These are warm-cache local measurements, not guarantees
for other machines. An initial IRS run took 11.9 seconds; subsequent runs took
0.46–0.48 seconds. That cold-start outlier remains a performance caveat.

| PDF | Pages | Size | Inspect | First visible | Sampled page turns |
| --- | ---: | ---: | ---: | ---: | ---: |
| IRS W-9 (native form) | 6 | 138 KiB | 19–29 ms | 456–481 ms | 70–80 ms |
| Bash reference manual | 214 | 836 KiB | 40 ms | 556 ms | 71–74 ms |
| NASA FY2024 financial report | 127 | 15.7 MiB | 66 ms | 575 ms | 70–243 ms |
| Repeated Bash stress document | 2,140 | 3.3 MiB | 201 ms | 696 ms | 68–73 ms |

The stress document repeats the real manual ten times; shared resources keep
its byte size small. NASA is the image-heavy, larger-byte-size case.

All cases passed bookmark save/reopen and the actual Recent menu click flow.
Exports passed qpdf structural validation and visual checks of the changed
first page. The W-9 preserved all 27 canonical native fields and their values;
Folio overlays do not populate native field values. Export took 0.18 seconds
(W-9), 2.58 seconds (Bash), and 2.12 seconds (NASA).

Sources (download separately; PDFs are not redistributed in this repository):

- https://www.irs.gov/pub/irs-pdf/fw9.pdf
- https://www.gnu.org/software/bash/manual/bash.pdf
- https://www.nasa.gov/wp-content/uploads/2023/11/nasa-fy-2024-afr-1.pdf

Reproduce with `tests/corpus-smoke.py` and `tests/corpus-export.py`. The latter
requires pypdf. UI tests require Hyprland, uinput access, wtype, and a C compiler.
Existing pointer-flow and pinch-flow tests cover text entry, cancel, multiline,
moving, formatting, resizing, synthetic signature placement, delete, and closing.
