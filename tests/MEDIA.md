# Release media

The 0.9.0 film and screenshots use the real app with the fictional three-page
"A slower weekend" booklet. No user document, private signature, desktop theme,
or global input is involved. The illustration is original vector artwork;
Noto fonts are embedded in the sample PDF.

Build the app and native module, then run:

```sh
python tests/media-sample.py
python tests/media-capture.py
python tests/media-encode.py output/release-media-CHOOSE-THE-NEW-RUN
```

The sample builder requires reportlab, fontconfig and Noto Sans/Serif. The
capture requires the ordinary app dependencies and the Tokyo Night,
Catppuccin Latte and Gruvbox palette files from an Omarchy installation.
Encoding requires ffmpeg with drawtext and libx264.

Each capture gets a fresh output directory. The sequence covers continuous
reading, Find, a bookmark, character-by-character text entry, field resizing,
name correction, nudge/undo, three palettes and export. It verifies text/focus
for each character and aborts on unexpected state. The original sample hash
must remain unchanged; the exported PDF passes the application's verifier.

The 595 app frames become a 29.75-second silent H.264 film at 20 fps, with a
small editorial frame and seven chapter captions. A 12-fps, 960px GIF supplies
GitHub's inline preview; the full-resolution MP4 remains downloadable. Neither
is a hardware performance measurement. The README offers a still image when
the browser requests reduced motion. GitHub's native video-player embed needs
a signed-in attachment upload; release-asset URLs are not that attachment flow.

Before publication, render every changed PDF page with pdftoppm and inspect it,
review all chosen screenshots, and check an encoded-film storyboard. Publish
only the selected media and blank sample PDF, not frames, logs or private state.
Append media hashes to the release SHA256SUMS without changing package hashes.
Keep old-version assets intact so historic release links continue to work.
