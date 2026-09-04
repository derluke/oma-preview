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
