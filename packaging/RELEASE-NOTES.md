# Folio 0.7.0

A small PDF reader and editor for Omarchy: text anywhere, reusable signatures,
page assembly, bookmarks, drafts, and visible agent review.

This release adds persistent Recent files, reliable live agent updates with
state readback, draft recovery, contextual editing controls, explicit multiline
text, resize handles, live theme updates, and pinch-to-zoom.

## Install on Arch / Omarchy

Download `folio-pdf-0.7.0-1-x86_64.pkg.tar.zst` from this release, then install it:

```sh
sudo pacman -U ./folio-pdf-0.7.0-1-x86_64.pkg.tar.zst
```

Dependencies are resolved by pacman. If you previously used `install.sh`, run
the repository's `uninstall.sh` first so the old user-local binary does not
shadow the system package. PDF defaults are optional and are not changed by
the package:

```sh
xdg-mime default org.omarchy.folio.desktop application/pdf
```

The AUR recipe and `.SRCINFO` are attached; AUR publication is pending maintainer
account setup. `omarchy pkg aur add folio-pdf` will work only after that upload.
The recipe supports aarch64 source builds, but this release only supplies and
tests the x86_64 binary package.

## Validation

Clean Arch build and tests passed. Desktop tests cover real pointer/keyboard
editing, sizing, multiline text, draft closing, synthetic signatures, pinch,
bookmarks, and reopening from Recent. Tested real PDFs include IRS W-9, the
214-page Bash manual, and NASA's 16 MB annual report, plus a synthetic
2,140-page stress document. All 27 native W-9 fields survive export.

Typical first visible page: 0.46–0.70 seconds on the test machine. An initial
cold IRS run took 11.9 seconds; subsequent runs were below 0.55 seconds. Sampled
page turns were 68–243 ms. See `tests/RESULTS.md` for scope and methodology.

## Current boundaries

Folio fills using overlays, not native form-value editing. Use Shift+Enter for
line breaks. Undo, automatic wrapping, search/copy, rotation and printing are
not yet implemented. Agent edits replace the full proposal; read `folio status`
and preserve user corrections before updating. Export and signing remain under
the user's control. External account connectors belong to the agent host.
