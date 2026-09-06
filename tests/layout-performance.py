#!/usr/bin/env python3
"""Measure synchronous zoom/layout work in the actual isolated QML UI, not FPS."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
harness = '''
        Timer {
            interval: 200; running: true; repeat: true
            onTriggered: {
                if (window.busy || window.loadingWorkspace || window.restoringView || !pages.count || renderedPage.status !== Image.Ready) return
                running = false
                window.zooming = true
                var started = Date.now(), original = window.zoom
                var cache = window.pageMetrics
                var checksum = 0
                for (var i = 0; i < 120; i++) {
                    window.zoom = 0.75 + (i % 30) / 20
                    checksum += window.pageLayout.height
                }
                var elapsed = Date.now() - started
                if (cache && cache !== window.pageMetrics) { console.error("Error: Zoom rebuilt document metrics"); Qt.quit(); return }
                window.zoom = original
                var top = 24, width = Math.max(120, Math.min(900, viewport.width - 64)) * window.zoom
                for (var j = 0; j < pages.count; j++) {
                    var geometry = typeof window.pageGeometry === "function" ? window.pageGeometry(j) : window.pageLayout.items[j]
                    if (Math.abs(geometry.top - top) > 0.001) { console.error("Error: Page layout drift", j); Qt.quit(); return }
                    top += width * pages.get(j).height / pages.get(j).width + 24
                }
                if (Math.abs(window.pageLayout.height - top) > 0.001 || !isFinite(checksum)) { console.error("Error: Invalid layout extent"); Qt.quit(); return }
                if (cache) {
                    // Dimension edits and reordering must invalidate source metrics.
                    pages.setProperty(0, "height", pages.get(0).height * 1.4)
                    for (var scenario = 0; scenario < 2; scenario++) {
                        if (scenario === 1) pages.move(0, pages.count - 1, 1)
                        var expectedTop = 24
                        for (var p = 0; p < pages.count; p++) {
                            var g = window.pageGeometry(p)
                            var expectedHeight = width * pages.get(p).height / pages.get(p).width
                            if (Math.abs(g.top - expectedTop) > 0.001 || Math.abs(g.height - expectedHeight) > 0.001) {
                                console.error("Error: Stale metrics after document change", scenario, p); Qt.quit(); return
                            }
                            expectedTop += expectedHeight + 24
                        }
                        if (Math.abs(window.pageLayout.height - expectedTop) > 0.001) { console.error("Error: Stale document extent"); Qt.quit(); return }
                    }
                }
                window.zooming = false
                console.log("LAYOUT_PASS pages=" + pages.count + " zoom-steps=120 elapsed-ms=" + elapsed)
                Qt.quit()
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-layout-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, capture_output=True, text=True, timeout=30)
    log = result.stdout + result.stderr
    if 'LAYOUT_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
    print(next(line for line in log.splitlines() if 'LAYOUT_PASS' in line))
