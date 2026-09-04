#!/usr/bin/env python3
"""Offscreen thumbnail lifecycle test; pass a PDF with at least ten pages."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
harness = '''
        Timer {
            interval: 100; running: true; repeat: true
            property int phase: 0
            property int peak: 0
            onTriggered: {
                if (window.busy || window.loadingWorkspace || pages.count < 10) return
                var active = 0
                var rows = pageList.contentItem.children
                for (var i = 0; i < rows.length; i++) if (rows[i].thumbnailActive === true) active++
                peak = Math.max(peak, active)
                if (active > Math.ceil(pageList.height / 184) + 1) throw new Error("Offscreen thumbnails rendered")
                if (phase === 0) {
                    var first = pageList.itemAtIndex(0)
                    if (!first || !first.thumbnailReady) return
                    pageList.currentIndex = pages.count - 1
                    pageList.positionViewAtIndex(pages.count - 1, ListView.End)
                    phase++
                } else if (phase === 1) {
                    var last = pageList.itemAtIndex(pages.count - 1)
                    if (!last || !last.thumbnailReady) return
                    window.sidebarVisible = false
                    phase++
                } else if (phase === 2) {
                    if (active !== 0 || sidebar.width !== 0) throw new Error("Collapsed sidebar retained thumbnails")
                    if (window.currentIndex !== pages.count - 1) throw new Error("Collapse lost selected page")
                    window.sidebarVisible = true
                    phase++
                } else {
                    var selected = pageList.itemAtIndex(pages.count - 1)
                    if (!selected || !selected.thumbnailReady) return
                    if (window.currentIndex !== pages.count - 1) throw new Error("Expand lost selected page")
                    console.log("THUMBNAILS_PASS pages=" + pages.count + " peak=" + peak)
                    Qt.quit()
                }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-thumbnails-') as scratch:
    work = Path(scratch)
    shutil.copytree(root/'ui', work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QSG_RHI_BACKEND='opengl', OMA_PREVIEW_BIN=str(root/'target/debug/oma-preview'),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    with (work/'log').open('w+') as log:
        p = subprocess.Popen(['qs','-p',str(work/'ui')], env=env, stdout=log, stderr=log, start_new_session=True)
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
        finally:
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            p.wait(timeout=5)
        log.seek(0)
        result = log.read()
        if 'THUMBNAILS_PASS' not in result or 'Error:' in result:
            raise SystemExit(result)
        print(next(line for line in result.splitlines() if 'THUMBNAILS_PASS' in line))
