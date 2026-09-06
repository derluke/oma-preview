#!/usr/bin/env python3
"""Pinned-reader accounting, reuse and cancelled-render source identity."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-reader-pool-') as scratch:
    work = Path(scratch)
    sources = []
    for index in range(12):
        svg, pdf = work/f'page-{index}.svg', work/f'page-{index}.pdf'
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="400">'
                       f'<rect width="300" height="400" fill="{["#cc3344", "#338844", "#3344bb"][index % 3]}"/>'
                       f'<text x="20" y="80" fill="white" font-size="36">Source {index}</text></svg>')
        subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(pdf), str(svg)], check=True)
        sources.append(str(pdf))
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    (work/'shell.qml').write_text('''
import QtQuick
import Quickshell
import "ui"
ShellRoot {
    Window {
        id: window
        visible: true; width: 540; height: 360
        property var paths: JSON.parse(Quickshell.env("POOL_PATHS"))
        property var first: null
        property var second: null
        property url expectedSource: ""
        function uri(path) { return "file://" + path }
        PdfDocumentPool { id: pool; hostWindow: window; limit: 1 }
        PdfRaster { id: actual; width: 240; height: 320; sourceSize.width: 240 }
        PdfRaster { id: pinned; x: 500; width: 30; height: 40; sourceSize.width: 30 }
        Image { id: reference; x: 250; width: 240; height: 320; sourceSize.width: 240
            source: window.expectedSource; asynchronous: true; fillMode: Image.PreserveAspectFit; cache: false }
        Timer {
            id: steps
            interval: 16; repeat: true; running: true
            property int phase: 0
            property int switches: 0
            property int verified: 0
            property double settled: 0
            onTriggered: {
                try {
                    if (phase === 0) {
                        window.first = pool.get(window.paths[0], window.uri(window.paths[0]))
                        window.second = pool.get(window.paths[1], window.uri(window.paths[1]))
                        actual.document = window.first; pinned.document = window.second
                        phase = 1
                    } else if (phase === 1) {
                        if (actual.status !== Image.Ready || pinned.status !== Image.Ready) return
                        pool.prune()
                        if (Object.keys(pool.documents).length !== 2 || window.first.leaseEntry.refs !== 1 || window.second.leaseEntry.refs !== 1)
                            throw new Error("Pool evicted a pinned reader or miscounted references")
                        pinned.document = null; phase = 2
                    } else if (phase === 2) {
                        pool.prune()
                        if (Quickshell.env("POOL_MISSING_IDLE") === "1") {
                            if (!pool.stats.retirementFailed || Object.keys(pool.documents).length !== 2
                                || String(window.first.source) !== window.uri(window.paths[0])
                                || String(window.second.source) !== window.uri(window.paths[1]))
                                throw new Error("Missing idle resource did not preserve original readers")
                            running = false; console.log("READER_POOL_FALLBACK_PASS"); Qt.callLater(Qt.quit); return
                        }
                        if (Object.keys(pool.documents).length !== 1 || pool.idle.length !== 1 || pinned.status !== Image.Null)
                            throw new Error("Unused reader was not retired or raster did not detach")
                        var reused = pool.get(window.paths[2], window.uri(window.paths[2]))
                        if (reused !== window.second || pool.stats.allocated !== 2) throw new Error("Pool did not reuse its idle reader")
                        actual.document = reused; window.expectedSource = window.uri(window.paths[2])
                        phase = 3
                    } else if (phase === 3) {
                        if (actual.status !== Image.Ready || reference.status !== Image.Ready) return
                        pool.limit = 2
                        actual.sourceSize.width = 3072
                        phase = 4
                    } else if (phase === 4) {
                        var path = window.paths[switches % window.paths.length]
                        actual.document = pool.get(path, window.uri(path))
                        pool.prune()
                        if (Object.keys(pool.documents).length > 2 || actual.document.leaseEntry.refs !== 1)
                            throw new Error("Rapid switching lost the active reader or exceeded the idle cache")
                        switches++
                        if (switches < 120) return
                        window.expectedSource = window.uri(window.paths[0])
                        actual.document = pool.get(window.paths[0], window.expectedSource)
                        actual.sourceSize.width = 240; settled = Date.now(); phase = 5
                    } else {
                        if (actual.status !== Image.Ready || reference.status !== Image.Ready || Date.now() - settled < 200) return
                        if (pool.stats.allocated > 3) throw new Error("Reader shells accumulate during reuse")
                        running = false
                        actual.grabToImage(function(a) {
                            if (!a.saveToFile(Quickshell.env("POOL_OUTPUT") + "/actual-" + steps.verified + ".png")) throw new Error("Could not capture actual source")
                            reference.grabToImage(function(b) {
                                if (!b.saveToFile(Quickshell.env("POOL_OUTPUT") + "/reference-" + steps.verified + ".png")) throw new Error("Could not capture reference source")
                                steps.verified++
                                if (steps.verified === window.paths.length) {
                                    console.log("READER_POOL_PASS " + JSON.stringify({switches:steps.switches,allocated:pool.stats.allocated,verified:steps.verified}))
                                    Qt.callLater(Qt.quit)
                                } else {
                                    var nextPath = window.paths[steps.verified]
                                    window.expectedSource = window.uri(nextPath)
                                    actual.document = pool.get(nextPath, window.expectedSource)
                                    steps.settled = Date.now(); steps.start()
                                }
                            })
                        })
                    }
                } catch (error) { running = false; console.error("Error: " + error); Qt.callLater(Qt.quit) }
            }
        }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               QT_SCALE_FACTOR='1', POOL_PATHS=json.dumps(sources), POOL_OUTPUT=str(work),
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=env, text=True, capture_output=True, timeout=40)
    log = result.stdout + result.stderr
    if result.returncode or 'READER_POOL_PASS' not in log or 'Error:' in log or 'Binding loop' in log or 'Unable to assign' in log:
        raise SystemExit(log)
    for index in range(len(sources)):
        result = subprocess.run(['magick', 'compare', '-metric', 'AE', str(work/f'actual-{index}.png'),
                                 str(work/f'reference-{index}.png'), 'null:'], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f'Reused reader {index} differs from an independent render: '+result.stderr)
    print(next(line for line in log.splitlines() if 'READER_POOL_PASS' in line))
    (work/'ui/idle.pdf').unlink()  # Only the copied test UI resource.
    fallback = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=dict(env, POOL_MISSING_IDLE='1'),
                              text=True, capture_output=True, timeout=15)
    fallback_log = fallback.stdout + fallback.stderr
    if fallback.returncode or 'READER_POOL_FALLBACK_PASS' not in fallback_log or 'Error:' in fallback_log or 'Binding loop' in fallback_log:
        raise SystemExit(fallback_log)
    print('PASS: pinned readers survive pruning; idle shells reused; 120 rapid switches; all 12 revisited sources match independent rendering')
    print('PASS: missing private idle resource disables retirement and preserves original readers')
