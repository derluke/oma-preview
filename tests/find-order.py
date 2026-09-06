#!/usr/bin/env python3
"""Controlled streaming-order regression for the real QML Find controller."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-find-order-') as scratch:
    work = Path(scratch)
    (work/'ui').mkdir()
    shutil.copy(Path(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'))/'SearchController.qml', work/'ui')
    worker = work/'worker'
    worker.write_text('''#!/usr/bin/env python3
import json, sys, time
request = json.loads(sys.stdin.readline())
wrap = request['query'] == 'wrap'
assert request['start_index'] == (3 if wrap else 1)
order = [3, 0, 2, 1] if wrap else [3, 1, 2, 0]
for completed, index in enumerate(order, 1):
    time.sleep(0.2)
    matches = [] if index == request['start_index'] else [{'rects':[{'x':0.1,'y':0.2,'width':0.2,'height':0.1}]}]
    print(json.dumps(dict(t='search_page', page_index=index, page_key=request['pages'][index]['key'],
                         matches=matches, completed=completed, total=4)), flush=True)
time.sleep(0.2)
print(json.dumps(dict(t='search_done', matches=3, completed=4, total=4, truncated=False)), flush=True)
''')
    worker.chmod(0o700)
    (work/'shell.qml').write_text('''
import QtQuick
import Quickshell
import "ui"
ShellRoot {
    Window {
        id: window
        visible: true; width: 240; height: 160
        property bool interactionReady: true
        property bool modalActive: false
        property int editingAnnotation: -1
        property int currentIndex: 3
        property int pageSnapshotRevision: 0
        property int choices: 0
        property int chosenPage: -1
        function pagePayload() { return [0,1,2,3].map(i => ({path:"unused.pdf",page:i+1,key:"page-"+i})) }
        SearchController {
            id: search
            previewWindow: window
            active: true; mayNavigate: true
            onChosen: match => { window.choices++; window.chosenPage = match.pageIndex }
        }
        Timer {
            interval: 10; running: true; repeat: true
            property int phase: 0
            property bool sawStreamingChoice: false
            onTriggered: {
                try {
                    if (search.error) throw new Error(search.error)
                    if (phase === 0) { search.query = "wrap"; phase = 1; return }
                    if (phase === 1) {
                        if (search.completed === 1 && window.choices) throw new Error("Wrapped past an unsearched page")
                        if (search.completed >= 2 && search.searching && search.hit) {
                            if (window.chosenPage !== 0 || window.choices !== 1) throw new Error("Wraparound did not select the earliest match")
                            sawStreamingChoice = true
                        }
                        if (search.searching || search.job) return
                        if (!sawStreamingChoice || search.current !== 0 || search.results.length !== 3 || window.choices !== 1)
                            throw new Error("Wraparound waited for completion or changed selection")
                        window.currentIndex = 1; window.choices = 0; window.chosenPage = -1
                        sawStreamingChoice = false; search.query = "forward"; phase = 2
                    } else if (phase === 2) {
                        if (search.completed < 3 && window.choices) throw new Error("Skipped an unsearched nearby page")
                        if (search.completed >= 3 && search.searching && search.hit) {
                            if (window.chosenPage !== 2 || window.choices !== 1) throw new Error("Selected the wrong nearby match")
                            sawStreamingChoice = true
                        }
                        if (search.searching || search.job) return
                        if (!sawStreamingChoice || search.current !== 1 || search.hit.pageIndex !== 2 || window.choices !== 1)
                            throw new Error("Earlier results changed the chosen match identity")
                        search.active = false; running = false
                        console.log("FIND_ORDER_PASS"); Qt.callLater(Qt.quit)
                    }
                } catch (error) { running = false; search.active = false; console.error("Error: " + error); Qt.callLater(Qt.quit) }
            }
        }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=str(worker), XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=env, text=True, capture_output=True, timeout=15)
    log = result.stdout + result.stderr
    if result.returncode or 'FIND_ORDER_PASS' not in log or 'Error:' in log or 'Binding loop' in log:
        raise SystemExit(log)
    print('PASS: current-page request, streaming wraparound, no skipped unsearched pages and stable match identity')
