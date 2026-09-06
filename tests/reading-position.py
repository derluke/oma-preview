#!/usr/bin/env python3
"""Close and reopen a clean PDF in isolated processes; never send desktop input."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-reading-') as scratch:
    work = Path(scratch)
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'),
                    str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    pdf = work/'reading.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', str(work/'one.pdf'), '1',
                    str(work/'one.pdf'), '1', '--', str(pdf)], check=True)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                if (window.busy || window.loadingWorkspace || window.restoringView || pages.count !== 2) return
                if (renderedPage.status !== Image.Ready) return
                if (window.dirty || window.draftNoticeVisible) {
                    console.error("Error: Reading marked the document dirty"); Qt.quit(); return
                }
                if (Quickshell.env("READING_TEST_STAGE") === "save") {
                    if (phase === 0) {
                        window.zoom = 1.5; window.sidebarVisible = false
                        pageList.currentIndex = 1; phase++
                    } else {
                        viewport.contentY = paper.y + paper.height * 0.2
                        console.log("READING_SAVED"); window.close()
                    }
                } else if (Quickshell.env("READING_TEST_STAGE") === "fresh") {
                    if (window.currentIndex !== 0 || window.zoom !== 1 || !window.sidebarVisible) {
                        console.error("Error: Changed source reused stale reading position"); Qt.quit(); return
                    }
                    console.log("READING_FRESH"); window.close()
                } else {
                    var centre = (viewport.contentY + viewport.height / 2 - paper.y) / paper.height
                    var expected = 0.2 + viewport.height / 2 / paper.height
                    if (window.currentIndex !== 1 || Math.abs(window.zoom - 1.5) > 0.001 || window.sidebarVisible || !window.continuous || Math.abs(centre - expected) > 0.002) {
                        console.error("Error: Reading position not restored", window.currentIndex, window.zoom, window.sidebarVisible, centre, expected)
                        Qt.quit(); return
                    }
                    console.log("READING_RESTORED"); window.close()
                }
            }
        }
'''
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(pdf)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    for stage, marker in [('save', 'READING_SAVED'), ('restore', 'READING_RESTORED')]:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, READING_TEST_STAGE=stage),
                                capture_output=True, text=True, timeout=15)
        log = result.stdout + result.stderr
        if marker not in log or 'Error:' in log:
            raise SystemExit(log)
    saved = list((work/'state').rglob('*.view.json'))
    drafts = [p for p in (work/'state').rglob('drafts/*.json') if not p.name.endswith('.view.json')]
    assert len(saved) == 1 and not drafts, 'Reading state must not create an edit draft'
    # A changed source must not inherit a location from a different document version.
    with pdf.open('ab') as changed:
        changed.write(b'\n')
    result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, READING_TEST_STAGE='fresh'),
                            capture_output=True, text=True, timeout=15)
    log = result.stdout + result.stderr
    if 'READING_FRESH' not in log or 'Error:' in log:
        raise SystemExit(log)
    print('PASS: clean close/reopen restores view without a draft; changed source ignores stale position')
