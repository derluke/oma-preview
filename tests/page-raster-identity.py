#!/usr/bin/env python3
"""Catch a previous PDF page being displayed during asynchronous page changes."""
import colorsys
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = Path(tempfile.mkdtemp(prefix='page-identity-', dir=root/'output'))
with tempfile.TemporaryDirectory(prefix='oma-page-identity-') as scratch:
    work = Path(scratch)
    count = 24
    colors = [tuple(round(v * 255) for v in colorsys.hsv_to_rgb(i / count, 0.7, 0.85)) for i in range(count)]
    detail = ''.join(f'<circle cx="{i % 100 * 6}" cy="{440 + i // 100 * 7}" r="2" fill="black"/>' for i in range(4000))
    for i, color in enumerate(colors):
        (work/f'{i}.svg').write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800">
<rect width="600" height="800" fill="rgb{color}"/><text x="30" y="70" font-size="40">Page {i + 1}</text>{detail}</svg>''')
        subprocess.run(['rsvg-convert', '--format=pdf', f'--output={work}/{i}.pdf', str(work/f'{i}.svg')], check=True)
    source = work/'distinct-pages.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', *[part for i in range(count) for part in (str(work/f'{i}.pdf'), '1')], '--', str(source)], check=True)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    (work/'shell.qml').write_text('''
import QtQuick
import QtQuick.Pdf
import Quickshell
import "ui"
ShellRoot {
    Window {
        visible: true; width: 360; height: 480
        PdfDocument { id: pdf; source: SOURCE }
        PdfRaster {
            id: raster; width: 300; height: 400
            document: pdf; sourceSize.width: 1200
        }
        Timer {
            interval: 16; running: true; repeat: true
            property int step: 0
            property bool pending: false
            property bool switched: false
            property double lastSwitch: 0
            onTriggered: {
                if (pending || (step === 0 && raster.status !== Image.Ready)) return
                if (step === 24 && raster.sourceSize.width !== 1200) {
                    raster.sourceSize.width = 1200; lastSwitch = Date.now(); return
                }
                if (step === 24 && (raster.status !== Image.Ready || Date.now() - lastSwitch < 300)) return
                if (step > 24) { console.log("PAGE_IDENTITY_PASS"); Qt.quit(); return }
                var frame = step === 24 ? 23 : step
                if (!switched) {
                    if (step === 1) raster.sourceSize.width = Number(Quickshell.env("RAPID_WIDTH"))
                    raster.currentFrame = frame
                    if (step < 24) lastSwitch = Date.now()
                    switched = true
                    if (step < 24) {
                        pending = true
                        let instantName = "instant-" + step + "-" + frame
                        raster.grabToImage(function(result) {
                            if (!result.saveToFile(OUTPUT + "/" + Quickshell.env("IDENTITY_RUN") + "/" + instantName + ".png")) throw new Error("Immediate capture failed")
                            pending = false
                        })
                    }
                    return
                }
                // Give the event loop several frames, as a fast-moving page
                // passes through the viewport; don't only capture the instant
                // before a freshly requested asynchronous image can exist.
                if (step < 24 && Date.now() - lastSwitch < 40) return
                pending = true
                let name = step + "-" + frame
                raster.grabToImage(function(result) {
                    if (!result.saveToFile(OUTPUT + "/" + Quickshell.env("IDENTITY_RUN") + "/" + name + ".png")) throw new Error("Capture failed")
                    pending = false; switched = false; step++
                })
            }
        }
    }
}
'''.replace('SOURCE', json.dumps(source.as_uri())).replace('OUTPUT', json.dumps(str(output))))
    for scale, rapid_width in ((1, 1200), (2, 1200), (1, 240), (2, 240)):
        run = output/f'{scale}x-{rapid_width}'
        run.mkdir()
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software', QT_SCALE_FACTOR=str(scale),
                   RAPID_WIDTH=str(rapid_width), IDENTITY_RUN=run.name)
        env.pop('DISPLAY', None)
        env.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=env, capture_output=True, text=True, timeout=30)
        log = result.stdout + result.stderr
        if 'PAGE_IDENTITY_PASS' not in log or 'Error:' in log or 'Binding loop' in log:
            raise SystemExit(log)
        shown = 0
        for step in range(count + 1):
            frame = min(step, count - 1)
            for prefix in ('', 'instant-') if step < count else ('',):
                path = run/f'{prefix}{step}-{frame}.png'
                sample = subprocess.check_output(['magick', str(path), '-alpha', 'on', '-format', '%[fx:p{w/2,h/4}.r] %[fx:p{w/2,h/4}.g] %[fx:p{w/2,h/4}.b] %[fx:p{w/2,h/4}.a]', 'info:'], text=True)
                r, g, b, alpha = map(float, sample.split())
                if alpha < 0.01:
                    assert 0 < step < count, f'Settled page missing: {path}'
                    continue
                assert all(abs(v * 255 - expected) < 3 for v, expected in zip((r, g, b), colors[frame])), f'{scale}x stale/wrong page at step {step}: {sample}; expected {colors[frame]}; {path}'
                if not prefix:
                    shown += 1
        print(f'PASS {scale}x width {rapid_width}: all 24 page identities correct or not yet painted; {shown} ready captures, final page settled')
print(output)
