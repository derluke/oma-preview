A calmer reader, smoother scrolling, and drafts that remember your work.

- Continuous reading, page jump and highlighted text search.
- Trackpad momentum and pointer-anchored zoom. Rest one or two fingers to pause;
  a quick same-direction scroll continues the glide instead of starting over.
- Drafts save automatically, including up to 100 undo/redo changes. Reopening
  restores your work and reading position. Original PDFs remain untouched.
- Lazy thumbnails, bounded reader reuse and lightweight previews during fast
  scrolling, with corrected high-DPI page identity and rendering.
- Quieter controls, improved keyboard editing and live Omarchy theme support.

## Install on Arch / Omarchy

Download the x86-64 package below, then run:

```sh
sudo pacman -U ./oma-preview-0.9.0-1-x86_64.pkg.tar.zst
oma-preview --version
```

The accompanying PKGBUILD is pinned to the tagged source archive and SHA-256.
The native input module requires Qt 6.11+. Hold-to-pause depends on compositor
hold-gesture support; detection timing belongs to the compositor/libinput.
Click-to-stop remains available where hold gestures are unsupported.

The isolated 25-check UI suite includes 47 input cases,
draft/undo recovery, bookmarks, search, raster checks and a 2,048-page fixture.
The local Wayland probe confirms hold support without injecting desktop input.
Physical trackpad feel and ARM64 are not established by these automated tests.

[Clean Arch build passed](https://github.com/derluke/oma-preview/actions/runs/34041342949).
[Fresh installation of this public package passed](https://github.com/derluke/oma-preview/actions/runs/34041352286),
including installed-file integrity, version and all 25 UI regressions.

Reopen existing windows after upgrading. If you used the user-local installer,
its `~/.local/bin/oma-preview` can shadow the system package; see the
[installation notes](https://github.com/derluke/oma-preview/blob/main/packaging/README.md).
Omarchy repository inclusion is still under maintainer review.

## A little room to work

![Oma Preview 0.9.0: read, find, fill, correct and switch themes](https://github.com/derluke/oma-preview/releases/download/v0.9.0/oma-preview-0.9-demo.gif)

30 seconds in the real app. Fictional sample, scripted actions, edited timing
and an illustrated pointer; not a performance benchmark.

[Full-resolution MP4](https://github.com/derluke/oma-preview/releases/download/v0.9.0/oma-preview-0.9-demo.mp4) ·
[Try the sample PDF](https://github.com/derluke/oma-preview/releases/download/v0.9.0/A.slower.weekend.pdf) ·
[Current theme screenshots](https://github.com/derluke/oma-preview#readme)
