#!/usr/bin/env python3
"""Exercise history in the real offscreen UI; no desktop input."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-history-') as scratch:
    work = Path(scratch)
    pdf = work/'sample.pdf'
    subprocess.run(['qpdf', '--empty', str(pdf)], check=True)
    # Two blank pages with distinct sizes, using the project's PDF tooling.
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'),
                    str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(work/'one.pdf'), '1',
                    str(work/'one.pdf'), '1', '--', str(pdf)], check=True)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                if (window.busy || window.loadingWorkspace) return
                if (renderedPage.status !== Image.Ready || !String(document.source).length) return
                if (window.currentPage.key !== pages.get(window.currentIndex).key) throw new Error("Stale current page")
                if (phase === 0) {
                    if (pages.count !== 2) return
                    window.deletePage()
                } else if (phase === 1) {
                    if (pages.count !== 1) throw new Error("Delete failed")
                    window.travelHistory(false)
                } else if (phase === 2) {
                    if (pages.count !== 2) throw new Error("Undo failed")
                    window.travelHistory(true)
                } else if (phase === 3) {
                    if (pages.count !== 1) throw new Error("Redo failed")
                    window.travelHistory(false)
                } else if (phase === 4) {
                    pageList.currentIndex = 1
                } else if (phase === 5) {
                    window.deletePage()
                } else if (phase === 6) {
                    window.travelHistory(false)
                } else if (phase === 7) {
                    if (pages.count !== 2) throw new Error("Last page restore failed")
                    pageList.currentIndex = 1
                    window.movePage(-1)
                } else if (phase === 8) {
                    window.travelHistory(false)
                } else {
                    console.log("HISTORY_RENDER_PASS"); Qt.quit()
                }
                phase++
            }
        }
'''
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QSG_RHI_BACKEND='opengl', OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(pdf)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    try:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=env,
                                capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as error:
        raise SystemExit(str(error.stdout) + str(error.stderr))
    log = result.stdout + result.stderr
    if 'HISTORY_RENDER_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
    print('PASS: delete first/last page, undo, redo, reorder; PDF remains rendered')
