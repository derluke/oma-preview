#!/usr/bin/env python3
"""Check that a dirty workspace is saved successfully before switching PDFs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-open-recovery-') as scratch:
    work = Path(scratch)
    source, target = work/'source.pdf', work/'other.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(target), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(target), '1', str(target), '1', '--', str(source)], check=True)
    originals = {p:hashlib.sha256(p.read_bytes()).digest() for p in (source, target)}
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        TestCase { id: openInput; name: "OpenRecovery"; when: false }
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            property string preserved: ""
            property string originalKey: ""
            onTriggered: {
                try {
                    if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready) return
                    if (phase === 0) {
                        window.deletePage()
                        originalKey = window.draftKey
                        preserved = window.contentKey(window.historySnapshot())
                        window.recents = [TARGET]
                        openInput.mouseClick(recentButton)
                    } else if (phase === 1) {
                        openInput.mouseClick(recentMenu.itemAt(0))
                        if (!window.busy || documentSurface.enabled || window.draftOpenRequest < 0 || window.currentPage.path !== SOURCE)
                            throw new Error("Document switch did not wait for its draft write")
                        backend.receive(JSON.stringify({t:"draft_saved", id:window.draftOpenRequest + 1000}))
                        if (!window.busy || window.currentPage.path !== SOURCE) throw new Error("Unrelated autosave released the switch")
                    } else if (phase === 2) {
                        if (Quickshell.env("OPEN_STAGE") === "fail") {
                            if (!window.statusError || !window.dirty || window.draftOpenRequest >= 0 || window.pendingOpenPaths.length
                                    || window.contentKey(window.historySnapshot()) !== preserved)
                                throw new Error("Failed draft save discarded the open workspace")
                            console.log("OPEN_FAILURE_SAFE"); Qt.quit(); return
                        }
                        if (window.currentPage.path !== TARGET || window.dirty) throw new Error("Acknowledged switch did not open the new PDF")
                        window.replaceWorkspace([SOURCE])
                    } else if (phase === 3) {
                        if (!window.draftRestored || !window.dirty || pages.count !== 1 || window.currentPage.path !== SOURCE)
                            throw new Error("Returning to the original PDF lost its saved edit")
                        if (window.undoStack.length !== 1) throw new Error("Switch lost undo history")
                        window.openPaths([TARGET], false)
                    } else if (phase === 4) {
                        if (pages.count !== 2 || window.draftKey !== originalKey) throw new Error("Adding a PDF changed the workspace identity")
                        window.replaceWorkspace([TARGET])
                    } else if (phase === 5) {
                        window.replaceWorkspace([SOURCE])
                    } else {
                        if (pages.count !== 2 || window.undoStack.length !== 2) throw new Error("Merged draft/history did not reopen under original source")
                        window.travelHistory(false)
                        if (pages.count !== 1) throw new Error("Restored add-PDF undo failed")
                        window.travelHistory(false)
                        if (pages.count !== 2 || window.dirty) throw new Error("Restored page deletion undo failed")
                        console.log("OPEN_RETURN_RESTORED"); Qt.quit(); return
                    }
                    phase++
                } catch (error) { console.error("Error: " + error); Qt.quit() }
            }
        }
'''.replace('SOURCE', json.dumps(str(source))).replace('TARGET', json.dumps(str(target)))
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n')
                     .replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    drafts = work/'state/folio/drafts'
    drafts.parent.mkdir(parents=True)
    drafts.write_text('Private ENOTDIR test fixture')
    for stage, marker in [('fail', 'OPEN_FAILURE_SAFE'), ('switch', 'OPEN_RETURN_RESTORED')]:
        if stage == 'switch':
            drafts.unlink(); drafts.mkdir()
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, OPEN_STAGE=stage), capture_output=True, text=True, timeout=15)
        log = result.stdout + result.stderr
        if marker not in log or 'Error:' in log:
            raise SystemExit(log)
        for path, digest in originals.items():
            assert hashlib.sha256(path.read_bytes()).digest() == digest, 'Source PDF changed'
    print('PASS: failed draft write aborts switching; acknowledged switch/reopen restores edits')
