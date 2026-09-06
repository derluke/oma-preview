#!/usr/bin/env python3
"""Verify failed save, retained draft, clean retry and unchanged source bytes."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-export-recovery-') as scratch:
    work = Path(scratch)
    source, output = work/'source.pdf', work/'saved.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(work/'one.pdf'), '1', str(work/'one.pdf'), '1', '--', str(source)], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready) return
                if (Quickshell.env("RECOVERY_STAGE") === "fail") {
                    if (phase === 0) {
                        window.deletePage(); window.closeAfterExport = true
                        window.saveTo(SOURCE); phase++
                    } else {
                        if (!window.dirty || !window.statusError || !window.interactionReady || window.closeAfterExport || statusTimer.running || pages.count !== 1) {
                            console.error("Error: Failed save lost edits, stayed busy, or hid the failure"); Qt.quit(); return
                        }
                        window.saveDraftNow()
                        console.log("RECOVERY_DRAFT_SAVED"); window.closeWindow()
                    }
                } else {
                    if (phase === 0) {
                        if (!window.dirty || !window.draftRestored || pages.count !== 1) { console.error("Error: Failed-save draft did not restore"); Qt.quit(); return }
                        window.saveTo(OUTPUT); phase++
                    } else {
                        if (window.dirty || window.statusError || !window.interactionReady) { console.error("Error: Retry did not recover"); Qt.quit(); return }
                        console.log("RECOVERY_RETRY_SAVED"); window.close()
                    }
                }
            }
        }
'''.replace('SOURCE', json.dumps(str(source))).replace('OUTPUT', json.dumps(str(output)))
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    for stage, marker in [('fail', 'RECOVERY_DRAFT_SAVED'), ('retry', 'RECOVERY_RETRY_SAVED')]:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, RECOVERY_STAGE=stage), capture_output=True, text=True, timeout=15)
        log = result.stdout + result.stderr
        if marker not in log or 'Error:' in log:
            raise SystemExit(log)
        assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source PDF changed'
    subprocess.run(['qpdf', '--check', str(output)], check=True, capture_output=True)
    count = subprocess.check_output(['qpdf', '--show-npages', str(output)], text=True).strip()
    assert count == '1', 'Saved result lost the retained page edit'
    print('PASS: failed-save draft restored, retry exported the edit, source unchanged')
