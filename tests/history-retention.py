#!/usr/bin/env python3
"""Bound retained page records over a long private editing session."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = '''
        Timer {
            interval: 16; running: true; repeat: true
            property int cycle: 0
            property int phase: 0
            property string baseline: ""
            onTriggered: {
                try {
                    if (!window.interactionReady || window.restoringView || !pages.count || renderedPage.status !== Image.Ready) return
                    if (Quickshell.env("RETENTION_REOPEN") === "1") {
                        if (!window.draftRestored || window.undoStack.length !== 100 || window.redoStack.length || pages.count !== 1)
                            throw new Error("Compacted draft did not restore")
                        for (var undo = 0; undo < 100; undo++) {
                            window.travelHistory(false)
                            if (pages.count !== (undo % 2 === 0 ? 2 : 1)
                                || (pages.count === 2 && pages.get(1).key !== "retention-" + (800 - Math.floor(undo / 2))))
                                throw new Error("Reopened history lost a page")
                        }
                        window.compactHistoryStorage(true)
                        for (var redo = 0; redo < 100; redo++) window.travelHistory(true)
                        if (pages.count !== 1 || window.dirty) throw new Error("Reopened redo lost the clean baseline")
                        draftTimer.stop(); running = false; console.log("RETENTION_REOPEN_PASS"); Qt.quit(); return
                    }
                    if (phase === 0) {
                        baseline = window.contentKey(window.historySnapshot())
                        phase = 1
                    }
                    if (phase === 1) {
                        for (var n = 0; n < 25; n++) {
                            cycle++
                            var page = Object.assign({}, window.pagePayload()[0], {key:"retention-" + cycle})
                            pages.append(page); window.markDirty()
                            pages.remove(1); window.markDirty()
                        }
                        draftTimer.stop()
                        if (cycle < 800) return
                        console.log("RETENTION_COUNTS " + JSON.stringify({cycles:cycle,
                            records:window.historyStorage.records.length,
                            page_keys:Object.keys(window.historyStorage.byPageKey).length}))
                        if (window.undoStack.length !== 100 || window.redoStack.length !== 0) throw new Error("History limit changed")
                        if (window.historyStorage.records.length > 400 || Object.keys(window.historyStorage.byPageKey).length > 400)
                            throw new Error("Expired page records accumulate beyond retained history")
                        if (window.contentKey(window.historySnapshot()) !== baseline || window.dirty)
                            throw new Error("History maintenance changed the clean baseline")
                        for (var i = 0; i < 100; i++) {
                            window.travelHistory(false)
                            if (pages.count !== (i % 2 === 0 ? 2 : 1)) throw new Error("Undo lost page insertion/removal")
                            if (pages.count === 2 && pages.get(1).key !== "retention-" + (800 - Math.floor(i / 2)))
                                throw new Error("Undo reused an expired page identity")
                        }
                        // All inserted pages are now reachable only through redo.
                        window.compactHistoryStorage(true)
                        if (window.historyStorage.records.length !== 51) throw new Error("Collection lost redo-only pages")
                        for (var j = 0; j < 100; j++) window.travelHistory(true)
                        if (pages.count !== 1 || window.contentKey(window.historySnapshot()) !== baseline || window.dirty)
                            throw new Error("Redo changed the final state")
                        // Keep redo-only pages alive during collection as well.
                        window.travelHistory(false)
                        var before = window.contentKey(window.historySnapshot())
                        window.compactHistoryStorage(true)
                        if (window.historyStorage.records.length !== 51) throw new Error("Collection lost or retained the wrong records")
                        if (window.contentKey(window.historySnapshot()) !== before) throw new Error("Collection changed content")
                        window.travelHistory(true)
                        var encoded = JSON.stringify(window.draftPayload())
                        if (encoded.indexOf("_folio") >= 0) throw new Error("Cache metadata escaped into the draft")
                        var decoded = window.unpackHistory(JSON.parse(encoded).history)
                        if (!decoded || decoded.undo.length !== 100 || window.contentKey(decoded.current) !== baseline)
                            throw new Error("Compacted history cannot round-trip")
                        window.saveDraftNow(); phase = 2
                    } else if (phase === 2 && window.draftPersisted) {
                        for (var k = 0; k < 100; k++) window.travelHistory(false)
                        pages.append(Object.assign({}, window.pagePayload()[0], {key:"branch-page"}))
                        window.markDirty(); window.compactHistoryStorage(true)
                        if (window.redoStack.length || window.undoStack.length !== 1 || window.historyStorage.records.length !== 2
                            || Object.keys(window.historyStorage.byPageKey).length !== 2)
                            throw new Error("Discarded redo branch remains in the cache")
                        window.travelHistory(false); window.travelHistory(true)
                        if (pages.count !== 2 || pages.get(1).key !== "branch-page") throw new Error("New branch cannot undo/redo")
                        // Leave the saved full history for the next process to verify.
                        draftTimer.stop()
                        console.log("RETENTION_PASS"); running = false; Qt.quit()
                    }
                } catch (error) { console.error("Error: " + error); running = false; Qt.quit() }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-history-retention-') as scratch:
    work = Path(scratch)
    source = work/'source.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(source),
                    str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS='["'+str(source)+'"]', OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    for reopen in ('0', '1'):
        with (work/('test-'+reopen+'.log')).open('w+') as stream:
            subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, RETENTION_REOPEN=reopen), stdout=stream,
                           stderr=subprocess.STDOUT, timeout=45, check=True)
            stream.seek(0)
            log = stream.read()
        marker = 'RETENTION_PASS' if reopen == '0' else 'RETENTION_REOPEN_PASS'
        if marker not in log or 'Error:' in log:
            raise SystemExit(log)
        if reopen == '0':
            print(next(line for line in log.splitlines() if 'RETENTION_COUNTS ' in line), flush=True)
    assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source changed'
    print('PASS: 1,600 page edits; bounded records, all retained undo/redo, clean baseline and reopened draft; source unchanged')
