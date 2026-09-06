#!/usr/bin/env python3
"""Silent close, persistent undo/redo, export baseline and draft-write failure."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-close-recovery-') as scratch:
    work = Path(scratch)
    source = work/'source.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(work/'one.pdf'), '1', str(work/'one.pdf'), '1', '--', str(source)], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        TestCase { id: closeInput; name: "CloseRecovery"; when: false }
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                try {
                    if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready) return
                    var stage = Quickshell.env("CLOSE_STAGE")
                    if (phase === 0) {
                        if (stage === "fail" || stage === "keep") {
                            window.deletePage()
                            if (stage === "keep") {
                                annotations.append({kind:"text", pageKey:pages.get(0).key, nx:0.2, ny:0.2, value:"Draft test", size:14,
                                    fontFamily:"sans-serif", inkColor:"#111111", nw:0.3, nh:0, strokeData:"[]"})
                                window.markDirty()
                                window.travelHistory(false)
                            }
                        } else {
                            if (!window.draftRestored) throw new Error("Draft did not restore")
                            if (stage === "unpacked" || stage === "layouts") {
                                if (window.undoStack.length !== 1 || window.redoStack.length !== 1 || pages.count !== 1)
                                    throw new Error("Original schema-2 history did not migrate")
                            } else if (stage === "undo") {
                                if (pages.count !== 1 || window.undoStack.length !== 1 || window.redoStack.length !== 1) throw new Error("Both history stacks did not restore")
                                window.travelHistory(false)
                                if (pages.count !== 2 || window.dirty || window.redoStack.length !== 2) throw new Error("Undo to original baseline failed")
                            } else if (stage === "redo") {
                                if (pages.count !== 2 || window.dirty || window.redoStack.length !== 2) throw new Error("Clean redo history did not survive closing")
                                window.travelHistory(true); window.travelHistory(true)
                                if (pages.count !== 1 || annotations.count !== 1 || annotations.get(0).value !== "Draft test") throw new Error("Redo did not restore page/text edits")
                            } else if (stage === "export") {
                                if (!window.dirty || window.undoStack.length !== 2) throw new Error("History missing before export")
                                window.saveTo(Quickshell.env("CLOSE_OUTPUT")); phase = 3; return
                            } else if (stage === "saved") {
                                if (window.dirty || window.undoStack.length !== 2) throw new Error("Exported baseline or history not restored")
                                window.travelHistory(false)
                                if (!window.dirty || annotations.count !== 0) throw new Error("Undo after reopening exported draft failed")
                                window.travelHistory(true)
                                if (window.dirty || annotations.count !== 1) throw new Error("Redo did not reach exported baseline")
                            } else if (stage === "editing") {
                                window.beginTextEdit(0, false)
                                annotations.setProperty(0, "value", "Draft test\\nSecond line")
                                window.markDirty()
                            } else if (stage === "legacy" || stage === "invalid") {
                                if (!window.dirty || pages.count !== 1 || annotations.count !== 1 || window.undoStack.length || window.redoStack.length)
                                    throw new Error("Legacy/invalid history fallback lost edits or retained invalid history")
                                if (annotations.get(0).value !== "Draft test\\nSecond line") throw new Error("Closing the active editor lost its latest text")
                            }
                        }
                        if (stage === "discard") {
                            closeDialog.open()
                            closeInput.mouseClick(closeDialog.discardButton)
                        } else window.close()
                        if (closeDialog.visible) throw new Error("Ordinary close opened a dialog")
                        if (!window.busy || window.allowClose || window.draftCloseRequest < 0) throw new Error("Draft choice closed without acknowledgement")
                        // An earlier autosave acknowledgement must not close this request.
                        backend.receive(JSON.stringify({t:stage === "discard" ? "draft_deleted" : "draft_saved", id:window.draftCloseRequest + 1000}))
                        if (!window.busy || window.allowClose) throw new Error("Unrelated acknowledgement completed closing")
                        console.log("CLOSE_WAITING_" + stage); phase = 1
                    } else if (phase === 3) {
                        if (window.dirty || window.statusError) throw new Error("Export failed")
                        console.log("CLOSE_WAITING_export"); window.close(); phase = 4
                    } else if (stage === "fail") {
                        if (!window.visible || window.allowClose || !window.dirty || !window.statusError || window.draftCloseRequest >= 0 || pages.count !== 1)
                            throw new Error("Failed draft save did not keep edits open")
                        console.log("CLOSE_FAILURE_SAFE"); Qt.quit()
                    }
                } catch (error) { console.error("Error: " + error); Qt.quit() }
            }
        }
'''
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
    # ENOTDIR is deterministic even when CI runs as root; no host permissions change.
    drafts.write_text('Blocked draft directory for the private failure test')
    for stage in ('fail', 'keep', 'layouts', 'unpacked', 'undo', 'redo', 'export', 'saved', 'editing', 'legacy', 'invalid', 'discard'):
        if stage == 'keep':
            drafts.unlink()
            drafts.mkdir()
        if stage in ('layouts', 'unpacked', 'legacy', 'invalid'):
            saved = [p for p in drafts.glob('*.json') if not p.name.endswith('.view.json')]
            draft = json.loads(saved[0].read_text())
            if stage == 'layouts':
                history = draft['history']
                records = history.pop('page_records')
                history['layouts'] = [[records[index] for index in layout] for layout in history['layouts']]
            elif stage == 'unpacked':
                history = draft['history']
                layouts = history.pop('layouts')
                if 'page_records' in history:
                    records = history.pop('page_records')
                    layouts = [[records[index] for index in layout] for layout in layouts]
                for snapshot in [history['current'], *history['undo'], *history['redo']]:
                    snapshot['pages'] = layouts[snapshot.pop('layout')]
            elif stage == 'legacy':
                draft['schema'] = 1
                draft.pop('history')
            else:
                draft['history']['undo'] = [{'pages': 'broken'}]
            saved[0].write_text(json.dumps(draft))
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, CLOSE_STAGE=stage, CLOSE_OUTPUT=str(work/'export.pdf')), capture_output=True, text=True, timeout=15)
        log = result.stdout + result.stderr
        if 'CLOSE_WAITING_'+stage not in log or 'Error:' in log or (stage == 'fail' and 'CLOSE_FAILURE_SAFE' not in log):
            raise SystemExit(log)
        assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source PDF changed'
        if stage != 'fail':
            saved = [p for p in drafts.glob('*.json') if not p.name.endswith('.view.json')]
            if stage == 'discard':
                assert not saved, 'Confirmed discard left an edit draft'
            else:
                assert len(saved) == 1 and json.loads(saved[0].read_text())['schema'] == 2, 'Versioned working draft missing'
    subprocess.run(['qpdf', '--check', str(work/'export.pdf')], check=True, capture_output=True)
    assert subprocess.check_output(['qpdf', '--show-npages', str(work/'export.pdf')], text=True).strip() == '1'
    print('PASS: silent acknowledged close; undo/redo and export baseline survive reopening; legacy/invalid history fallback; write failure and discard')
