#!/usr/bin/env python3
"""Measure visible Find readiness and UI timer gaps with private state."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
query = sys.argv[2] if len(sys.argv) > 2 else 'the'
before = hashlib.sha256(source.read_bytes()).digest()
harness = '''
        property bool measuringFind: false
        Timer {
            id: findHeartbeat
            interval: 16; running: true; repeat: true
            property double previous: 0
            property double worst: 0
            onTriggered: {
                var now = Date.now()
                if (window.measuringFind && previous) worst = Math.max(worst, now - previous)
                previous = now
            }
        }
        Timer {
            interval: 16; running: true; repeat: true
            property int phase: 0
            property double began: 0
            property double firstHighlight: -1
            property int startPage: 1
            property int firstMatchPage: -1
            onTriggered: {
                try {
                    if (!window.interactionReady || window.restoringView) return
                    if (phase === 0) {
                        if (renderedPage.status !== Image.Ready) return
                        var start = Number(Quickshell.env("FIND_START_PAGE") || "1") - 1
                        if (!Number.isInteger(start) || start < 0 || start >= pages.count) throw new Error("Invalid FIND_START_PAGE")
                        startPage = start + 1
                        window.jumpToPage(start); phase = 1; return
                    } else if (phase === 1) {
                        if (renderedPage.status !== Image.Ready) return
                        if (window.currentIndex !== startPage - 1) throw new Error("Search did not start on the requested page")
                        window.openFind(); began = Date.now(); window.measuringFind = true
                        findBar.field.text = Quickshell.env("FIND_QUERY"); phase = 2
                    } else {
                        if (searchController.error) throw new Error(searchController.error)
                        if (firstHighlight < 0 && searchController.hit && window.currentIndex === searchController.hit.pageIndex
                            && renderedPage.status === Image.Ready) {
                            firstHighlight = Date.now() - began; firstMatchPage = window.currentIndex + 1
                        }
                        if (searchController.searching) return
                        if (firstHighlight < 0) throw new Error("Expected a visible search match")
                        if (window.dirty || window.undoStack.length || !findBar.field.activeFocus) throw new Error("Search changed editing state/focus")
                        console.log("FIND_PERFORMANCE " + JSON.stringify({pages:pages.count,matches:searchController.results.length,
                            start_page:startPage,first_match_page:firstMatchPage,
                            first_highlight_ms:firstHighlight,total_ms:Date.now()-began,worst_timer_gap_ms:findHeartbeat.worst,
                            truncated:searchController.truncated}))
                        window.measuringFind = false; running = false; Qt.quit()
                    }
                } catch (error) { running = false; console.error("Error: " + error); Qt.callLater(Qt.quit) }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-find-perf-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/release/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='', FIND_QUERY=query,
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    with (work/'test.log').open('w+') as stream:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
        stream.seek(0)
        log = stream.read()
    if result.returncode or 'FIND_PERFORMANCE ' not in log or 'Error:' in log or 'Binding loop' in log:
        raise SystemExit(log)
    assert hashlib.sha256(source.read_bytes()).digest() == before, 'Source changed'
    print(next(line for line in log.splitlines() if 'FIND_PERFORMANCE ' in line))
