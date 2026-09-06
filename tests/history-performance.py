#!/usr/bin/env python3
"""Measure real QML history/save/reopen costs with private state, not desktop FPS."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
workload = sys.argv[2] if len(sys.argv) > 2 else 'text'
if workload not in ('text', 'pages'):
    raise SystemExit('Workload must be text or pages')
harness = '''
        Timer {
            interval: 16; running: true; repeat: true
            property int phase: 0
            property double saveStarted: 0
            property double dispatchMs: 0
            property double editMs: 0
            property double worstEditMs: 0
            onTriggered: {
                try {
                    if (window.busy || window.loadingWorkspace || window.restoringView || !pages.count || renderedPage.status !== Image.Ready) return
                    var rearranging = Quickshell.env("HISTORY_WORKLOAD") === "pages"
                    if (rearranging && pages.count < 102) throw new Error("Page workload requires at least 102 pages")
                    var stage = Quickshell.env("HISTORY_STAGE")
                    if (stage === "autosave") {
                        if (phase === 0) {
                            var before = window.latestDraftSaveRequest
                            window.travelHistory(false)
                            if (!draftTimer.running || window.latestDraftSaveRequest !== before) throw new Error("Undo bypassed autosave debounce")
                            phase++
                        } else if (window.draftPersisted) {
                            running = false; console.log("HISTORY_AUTOSAVE confirmed"); Qt.quit()
                        }
                        return
                    }
                    if (stage === "resume") {
                        running = false
                        if (!window.draftRestored || window.undoStack.length !== 99 || window.redoStack.length !== 1
                            || (rearranging ? pages.get(0).page !== 100 : annotations.get(0).value !== "99")) throw new Error("Debounced undo was not restored")
                        console.log("HISTORY_RESUME confirmed"); Qt.quit(); return
                    }
                    if (Quickshell.env("HISTORY_STAGE") === "restore") {
                        running = false
                        if (!window.draftRestored || window.undoStack.length !== 100 || window.redoStack.length !== 0
                            || annotations.count !== 1 || annotations.get(0).value !== (rearranging ? "0" : "100")) throw new Error("Full history did not restore")
                        if (rearranging && pages.get(0).page !== 101) throw new Error("Rearranged pages did not restore")
                        var started = Date.now()
                        var pageRevision = window.pageSnapshotRevision
                        window.travelHistory(false)
                        if ((rearranging ? pages.get(0).page !== 100 : annotations.get(0).value !== "99") || window.redoStack.length !== 1) throw new Error("Restored undo failed")
                        window.travelHistory(true)
                        if ((rearranging ? pages.get(0).page !== 101 : annotations.get(0).value !== "100") || window.undoStack.length !== 100) throw new Error("Restored redo failed")
                        if (!rearranging && pageRevision !== undefined && window.pageSnapshotRevision !== pageRevision) throw new Error("Text-only undo/redo rebuilt the page model")
                        draftTimer.stop()
                        console.log("HISTORY_RESTORE " + JSON.stringify({pages:pages.count, undo_redo_ms:Date.now()-started}))
                        var original = window.pagePayload(), height = pages.get(0).height
                        pages.setProperty(0, "height", height + 1)
                        var resized = window.pagePayload()
                        if (resized === original || original[0].height !== height || resized[0].height !== height + 1) throw new Error("Page dimension change reused or mutated a historical layout")
                        pages.setProperty(0, "height", height)
                        if (pages.count > 1) {
                            pages.move(0, 1, 1)
                            if (window.pagePayload()[0].key !== original[1].key) throw new Error("Page move did not invalidate layout snapshot")
                            pages.move(1, 0, 1)
                        }
                        var replacement = Object.assign({}, original[0], {height:height + 2})
                        pages.remove(0); pages.insert(0, replacement)
                        if (window.pagePayload()[0].height !== height + 2) throw new Error("Same-count page replacement did not invalidate layout snapshot")
                        // Exercise the codec independently of the measured user
                        // workload: moves, deletion, insertion, resize and fallback.
                        if (original.length >= 16) {
                            var orders = [original.slice(0, 16)], next = orders[0].slice()
                            next.push(next.shift()); orders.push(next)
                            next = next.slice(); next.splice(4, 1); orders.push(next)
                            next = next.slice(); next.splice(3, 0, Object.assign({}, next[0], {key:"codec-insert"})); orders.push(next)
                            next = next.slice(); next[0] = Object.assign({}, next[0], {height:next[0].height + 1}); orders.push(next)
                            orders.push(next.slice().reverse())
                            var snapshots = orders.map(p => ({pages:p, marks:[], current:0, output:""}))
                            var encoded = window.packHistory(snapshots[5], snapshots.slice(0, 5), [])
                            var decoded = window.unpackHistory(JSON.parse(JSON.stringify(encoded)))
                            if (!decoded || decoded.undo.concat([decoded.current]).some((s, index) => window.contentKey(s) !== window.contentKey(snapshots[index])))
                                throw new Error("Page-order codec changed a historical state")
                            if (!encoded.layouts.some(l => !Array.isArray(l) && l.move) || !encoded.layouts.some(l => !Array.isArray(l) && l.splice))
                                throw new Error("Codec did not compact page operations")
                            var broken = JSON.parse(JSON.stringify(encoded)); broken.layouts[1].base = 1
                            if (window.unpackHistory(broken) !== null) throw new Error("Cyclic layout reference accepted")
                            broken = JSON.parse(JSON.stringify(encoded)); broken.layouts[1].move = [-1, 0]
                            if (window.unpackHistory(broken) !== null) throw new Error("Invalid move accepted")
                            broken = JSON.parse(JSON.stringify(encoded)); broken.layouts[0][0] = -1
                            if (window.unpackHistory(broken) !== null) throw new Error("Invalid page reference accepted")
                            broken = JSON.parse(JSON.stringify(encoded)); broken.layouts[3].splice[2] = [-1]
                            if (window.unpackHistory(broken) !== null) throw new Error("Invalid inserted page accepted")
                        }
                        Qt.quit(); return
                    }
                    if (phase === 0) {
                        annotations.append({kind:"text", pageKey:pages.get(0).key, nx:0.1, ny:0.1, value:"0", size:14,
                            fontFamily:"sans-serif", inkColor:"#111111", nw:0.3, nh:0, strokeData:"[]"})
                        window.markDirty()
                        for (var i = 1; i <= 100; i++) {
                            var began = Date.now()
                            if (rearranging) pages.move(0, pages.count - 1, 1)
                            else annotations.setProperty(0, "value", String(i))
                            window.markDirty()
                            var elapsed = Date.now() - began
                            editMs += elapsed; worstEditMs = Math.max(worstEditMs, elapsed)
                        }
                        draftTimer.stop()
                        saveStarted = Date.now()
                        window.saveDraftNow()
                        dispatchMs = Date.now() - saveStarted
                        phase++
                    } else if (window.draftPersisted) {
                        running = false
                        console.log("HISTORY_SAVE " + JSON.stringify({workload:Quickshell.env("HISTORY_WORKLOAD"), pages:pages.count, steps:window.undoStack.length,
                            edit_total_ms:editMs, worst_edit_ms:worstEditMs, dispatch_ms:dispatchMs, acknowledged_ms:Date.now()-saveStarted}))
                        Qt.quit()
                    }
                } catch (error) { console.error("Error: " + error); Qt.quit() }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-history-perf-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               HISTORY_WORKLOAD=workload,
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    for stage in ('save', 'restore', 'autosave', 'resume'):
        started = time.monotonic()
        # A crashing launcher can leave a child holding its stdout open. A file
        # lets us observe launcher completion without waiting on an inherited pipe.
        with (work/(stage+'.log')).open('w+') as stream:
            try:
                result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, HISTORY_STAGE=stage),
                                        stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=60)
            except subprocess.TimeoutExpired:
                stream.seek(0)
                raise SystemExit('History test timed out:\n'+stream.read())
            stream.seek(0)
            log = stream.read()
        marker = 'HISTORY_'+stage.upper()+' '
        if marker not in log or 'Error:' in log:
            raise SystemExit(log)
        print(next(line for line in log.splitlines() if marker in line), flush=True)
        print(f'{stage} process wall time: {time.monotonic()-started:.3f}s', flush=True)
        if stage == 'save':
            drafts = [p for p in (work/'state/folio/drafts').glob('*.json') if not p.name.endswith('.view.json')]
            assert len(drafts) == 1, 'Expected one saved draft'
            print(f'draft bytes: {drafts[0].stat().st_size}', flush=True)
            if os.environ.get('OMA_PREVIEW_ALLOW_LEGACY_HISTORY') != '1':
                history = json.loads(drafts[0].read_text())['history']
                assert '_folio' not in drafts[0].read_text(), 'Internal cache metadata leaked into the draft'
                if workload == 'pages':
                    assert len(history['page_records']) == len(history['layouts'][0]), 'Unchanged page records were duplicated'
                    assert sum(isinstance(layout, dict) and 'move' in layout for layout in history['layouts']) == 100, 'Single-page moves should be compact operations'
                assert len(history['layouts']) == (101 if workload == 'pages' else 1), 'Layout sharing lost or duplicated distinct page arrangements'
                assert all(0 <= s['layout'] < len(history['layouts']) and 'pages' not in s for s in [history['current'], *history['undo']]), 'Snapshots should reference their shared layout'
    print('PASS: full 100-step history persisted and reopened in isolated processes')
