#!/usr/bin/env python3
"""Compare Oma Preview's PDF raster with Qt's standard image path at four scales."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve(strict=True)
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-raster-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
import QtQuick
import QtQuick.Pdf
import Quickshell
import "ui"
ShellRoot {
    Window {
        id: window
        visible: true; width: 660; height: 460
        property int rasterPhase: 0
        PdfDocument { id: pdf; source: SOURCE }
        PdfRaster {
            id: shared
            width: 300; height: 420
            document: window.rasterPhase === 1 ? ({source:SOURCE, sourceOnly:true}) : pdf
            sourceSize.width: 300
            asynchronous: true; fillMode: Image.PreserveAspectFit
        }
        Image {
            id: standard
            x: 330; width: 300; height: 420
            source: SOURCE; sourceSize.width: 300
            asynchronous: true; fillMode: Image.PreserveAspectFit
        }
        Timer {
            id: captureTimer
            interval: 300; running: true; repeat: true
            onTriggered: {
                if (shared.status !== Image.Ready || standard.status !== Image.Ready) return
                stop()
                shared.grabToImage(function(a) {
                    if (!a.saveToFile(OUTPUT + "/actual-" + window.rasterPhase + ".png")) throw new Error("Could not capture raster")
                    standard.grabToImage(function(b) {
                        if (!b.saveToFile(OUTPUT + "/standard.png")) throw new Error("Could not capture standard raster")
                        console.log("RASTER_PASS " + JSON.stringify({dpr:window.devicePixelRatio, phase:window.rasterPhase,
                            actualWidth:shared.implicitWidth, referenceWidth:standard.implicitWidth}))
                        if (window.rasterPhase < 2) { window.rasterPhase++; captureTimer.start() }
                        else Qt.quit()
                    })
                })
            }
        }
    }
}
'''.replace('SOURCE', json.dumps(source.as_uri())).replace('OUTPUT', json.dumps(str(work)))
    (work/'shell.qml').write_text(harness)
    for scale in (1, 1.25, 1.5, 2):
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                   QT_QUICK_BACKEND='software', QT_SCALE_FACTOR=str(scale))
        env.pop('DISPLAY', None)
        env.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=env,
                                capture_output=True, text=True, timeout=10)
        log = result.stdout + result.stderr
        if result.returncode or log.count('RASTER_PASS') != 3 or 'Error:' in log or 'Binding loop' in log:
            raise SystemExit(log)
        for phase in range(3):
            name = f'actual-{phase}.png'
            comparison = subprocess.run(['magick', 'compare', '-metric', 'AE', str(work/name),
                                         str(work/'standard.png'), 'null:'], capture_output=True, text=True)
            print(f'{scale}x phase {phase}: differing pixels={comparison.stderr.strip()}')
            if comparison.returncode:
                (root/'output').mkdir(exist_ok=True)
                diagnostics = Path(tempfile.mkdtemp(prefix='oma-raster-', dir=root/'output'))
                for artifact in (name, 'standard.png'):
                    shutil.copyfile(work/artifact, diagnostics/artifact)
                print(f'Comparison images: {diagnostics}')
                raise SystemExit(f'PDF raster differs from standard Qt rendering at {scale}x phase {phase}')
