#!/usr/bin/env python3
"""Exercise actual Qt Quick dialogs offscreen, without compositor/global input."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = '''
        Timer {
            interval: 250; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                var dialogs = [openDialog, addDialog, saveDialog, signatureDialog, closeDialog, draftRecovery, signatureMenu, pageMenu, bookmarkMenu, pageJump]
                var modalSteps = dialogs.length * 2
                if (phase >= modalSteps) {
                    if (window.modalActive) throw new Error("Modal stuck after close")
                    if (phase === modalSteps) { window.width = 640; phase++; return }
                    if (saveButton.x < fileControls.x + fileControls.width + 40)
                        throw new Error("Document header overlaps")
                    var groups = toolbarGroups.children
                    for (var i = 0; i < groups.length; i++) {
                        var a = groups[i]
                        if (a.x + a.width > toolbarGroups.width + 1 || a.y + a.height > toolbar.height - 8 + 1)
                            throw new Error("Toolbar group clipped")
                        for (var j = i + 1; j < groups.length; j++) {
                            var b = groups[j]
                            if (a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height)
                                throw new Error("Toolbar groups overlap")
                        }
                    }
                    if (phase === modalSteps + 1) { window.width = 1040; phase++; return }
                    if (phase === modalSteps + 2) { window.width = 800; phase++; return }
                    console.log("DIALOG_SMOKE_PASS")
                    Qt.quit()
                    return
                }
                var d = dialogs[Math.floor(phase / 2)]
                if (phase % 2 === 0) {
                    if (phase < 6 && !(d.options & FileDialog.DontUseNativeDialog)) throw new Error("Native dialog enabled")
                    d.open()
                } else {
                    if (!d.visible || !window.modalActive) throw new Error("Dialog did not open")
                    if (window.applyLiveReview("/nonexistent.json", false)) throw new Error("Live edit accepted under modal")
                    d.close()
                }
                phase++
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-dialog-test-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root / 'ui'), work / 'ui')
    shell = work / 'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId ' + work.name)
                     .replace('        Component.onCompleted: {', harness + '\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QSG_RHI_BACKEND='opengl', OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root / 'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS='[]', OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    with (work/'log').open('w+') as log:
        p = subprocess.Popen(['qs', '-p', str(work/'ui')], env=env, stdout=log,
                             stderr=log, start_new_session=True)
        try:
            p.wait(timeout=15)
        except subprocess.TimeoutExpired:
            pass
        finally:
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            p.wait(timeout=5)
        log.seek(0)
        output = log.read()
        if 'DIALOG_SMOKE_PASS' not in output or 'Error:' in output:
            raise SystemExit(output)
        print('PASS: open/add/save/signature/close dialogs, modal state, live-edit rejection; no global input')
