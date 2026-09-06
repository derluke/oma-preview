#!/usr/bin/env python3
"""Missing/changed draft dependencies, private fixtures and actual recovery UI."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
harness = '''
        TestCase { id: sourceInput; name: "SourceRecovery"; when: false }
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            onTriggered: {
                try {
                    if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready) return
                    var stage = Quickshell.env("SOURCE_STAGE"), historyOnly = Quickshell.env("SOURCE_MODE") === "history"
                    if (stage === "create") {
                        if (phase === 0) { window.openPaths([Quickshell.env("SOURCE_ADDED")], false); phase++; return }
                        if (pages.count !== 3) throw new Error("Fixture assembly failed")
                        if (historyOnly) window.travelHistory(false)
                        running = false; console.log("SOURCE_CREATE"); window.close(); return
                    }
                    if (stage === "recover" || (stage === "retry" && !window.draftProblem)) {
                        if (!window.draftRestored || draftRecovery.visible || pages.count !== (historyOnly ? 2 : 3)
                            || (historyOnly ? window.redoStack.length !== 1 : window.undoStack.length !== 1)) throw new Error("Source repair did not restore the complete workspace")
                        running = false; console.log("SOURCE_RECOVER"); window.close(); return
                    }
                    if (!window.draftProblem || !draftRecovery.visible || !window.modalActive || window.draftRestored
                        || window.hasWorkingDraft || draftTimer.running) throw new Error("Unavailable draft was silently ignored or made writable")
                    if (window.applyLiveReview("/unused.json", false)) throw new Error("Agent edit bypassed recovery")
                    if (stage === "open-cancel") {
                        if (phase === 0) { sourceInput.mouseClick(draftRecovery.openButton); phase++; return }
                        if (phase === 1) {
                            if (!openDialog.visible) throw new Error("Recovery could not open the file picker")
                            sourceInput.keyClick(Qt.Key_Escape); phase++; return
                        }
                        if (openDialog.visible || !draftRecovery.visible) throw new Error("Cancelling Open escaped draft protection")
                    }
                    if (stage === "retry") {
                        if (phase === 0) { console.log("SOURCE_REPAIR_READY"); phase++; return }
                        sourceInput.mouseClick(draftRecovery.retryButton); return
                    }
                    running = false; console.log("SOURCE_BLOCKED"); window.close()
                } catch (error) { running = false; console.error("Error: " + error); Qt.quit() }
            }
        }
'''

with tempfile.TemporaryDirectory(prefix='oma-source-recovery-') as scratch:
    for mode in ('visible', 'history'):
        work = Path(scratch)/mode
        work.mkdir()
        source, added, backup, away = [work/name for name in ('source.pdf', 'added.pdf', 'original-added.pdf', 'moved.pdf')]
        subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(added), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
        subprocess.run(['qpdf', '--empty', '--pages', str(added), '1', str(added), '1', '--', str(source)], check=True)
        shutil.copy2(added, backup)
        original_hash = hashlib.sha256(source.read_bytes()).digest()
        shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
        shell = work/'ui/shell.qml'
        shell.write_text(shell.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n')
                         .replace('ShellId oma-preview', 'ShellId '+work.parent.name+'-'+mode)
                         .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
        binary = os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview'))
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
                   OMA_PREVIEW_BIN=binary, OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
                   SOURCE_MODE=mode, SOURCE_ADDED=str(added), XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
        env.pop('DISPLAY', None)
        env.pop('WAYLAND_DISPLAY', None)

        def launch(stage, expected):
            with (work/'run.log').open('w+') as stream:
                process = subprocess.Popen(['qs', '-p', str(work/'ui')], env=dict(env, SOURCE_STAGE=stage), stdout=stream, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 20
                repaired = False
                while process.poll() is None and time.monotonic() < deadline:
                    stream.seek(0)
                    if stage == 'retry' and not repaired and 'SOURCE_REPAIR_READY' in stream.read():
                        away.rename(added)
                        repaired = True
                    time.sleep(0.02)
                if process.poll() is None:
                    process.kill(); process.wait()
                stream.seek(0)
                log = stream.read()
                if expected not in log or 'Error:' in log:
                    raise SystemExit(stage+'\n'+log)
            assert hashlib.sha256(source.read_bytes()).digest() == original_hash

        launch('create', 'SOURCE_CREATE')
        drafts = [p for p in (work/'state/folio/drafts').glob('*.json') if not p.name.endswith('.view.json')]
        assert len(drafts) == 1
        draft = drafts[0]
        assert set(json.loads(draft.read_text())['source_stamps']) == {str(source), str(added)}
        before = draft.read_bytes()
        added.rename(away)
        launch('missing', 'SOURCE_BLOCKED')
        assert draft.read_bytes() == before, 'Blocked open changed the saved draft'
        launch('open-cancel', 'SOURCE_BLOCKED')
        assert draft.read_bytes() == before
        launch('retry', 'SOURCE_RECOVER')
        assert added.exists() and not away.exists()

        before = draft.read_bytes()
        added.write_bytes(added.read_bytes()+b'\n% changed fixture\n')
        launch('changed', 'SOURCE_BLOCKED')
        assert draft.read_bytes() == before, 'Changed source caused draft replacement'
        # A real backup copy can have a new timestamp; identical bytes recover.
        shutil.copyfile(backup, added)
        launch('recover', 'SOURCE_RECOVER')

        # The same guards apply if a source changes while the backend is open.
        before = draft.read_bytes()
        with subprocess.Popen([binary, '--backend'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as backend:
            def request(message):
                backend.stdin.write(json.dumps(message)+'\n'); backend.stdin.flush()
                return json.loads(backend.stdout.readline())
            inspected = request({'c':'inspect', 'id':1, 'path':str(added)})
            assert inspected['t'] == 'inspected'
            added.write_bytes(added.read_bytes()+b'\n% live source change\n')
            failed = request({'c':'draft_save', 'id':2, 'key':json.dumps([str(source)], separators=(',', ':')), 'draft':json.loads(before)})
            assert failed['t'] == 'error' and failed['operation'] == 'draft_save'
            page = dict(inspected['pages'][0], path=str(added), key='test-page')
            failed = request({'c':'export', 'id':3, 'dest':str(work/'must-not-export.pdf'), 'pages':[page], 'annotations':[]})
            assert failed['t'] == 'error' and failed['operation'] == 'export'
            request({'c':'quit'})
        assert draft.read_bytes() == before and not (work/'must-not-export.pdf').exists()
        shutil.copy2(backup, added)

        # A damaged draft also stays intact, rather than becoming a fresh draft.
        draft.write_text('{damaged fixture')
        launch('corrupt', 'SOURCE_BLOCKED')
        assert draft.read_text() == '{damaged fixture'
        draft.write_bytes(before)
        launch('recover', 'SOURCE_RECOVER')

        legacy = json.loads(draft.read_text())
        legacy.pop('source_stamps')
        draft.write_text(json.dumps(legacy))
        before = draft.read_bytes()
        added.rename(away)
        launch('missing', 'SOURCE_BLOCKED')
        assert draft.read_bytes() == before
        launch('retry', 'SOURCE_RECOVER')
        assert len(json.loads(draft.read_text())['source_stamps']) == 2, 'Legacy draft did not gain source stamps'
        print(f'PASS: {mode} source dependency protected; actual Retry restored it; live save/export rejected changes; corrupt draft retained', flush=True)
