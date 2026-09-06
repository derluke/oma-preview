#!/usr/bin/env python3
"""Measure a single window across many distinct PDF paths, using private state.

Copies the supplied corpus file into an isolated temporary directory. No desktop
input, source edits, exports, or shared drafts. Memory is sampled from /proc.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('count', type=int, nargs='?', default=40)
parser.add_argument('--scale', type=float, default=float(os.environ.get('QT_SCALE_FACTOR', '1')))
parser.add_argument('--expect-source-only', action='store_true')
parser.add_argument('--max-resident-readers', type=int)
args = parser.parse_args()
source = args.source.resolve(strict=True)
count = args.count
if not 2 <= count <= 200:
    raise SystemExit('Use between 2 and 200 documents')
if not 0.5 <= args.scale <= 4:
    parser.error('Use a scale between 0.5 and 4')
before = hashlib.sha256(source.read_bytes()).digest()
harness = '''
        Timer {
            interval: 25; running: true; repeat: true
            property var sources: JSON.parse(Quickshell.env("SESSION_PATHS"))
            property int cursor: 0
            property int phase: 0
            property double readyAt: 0
            property double checkpointAt: 0
            property double openedAt: Date.now()
            onTriggered: {
                try {
                    if (window.statusError || renderedPage.status === Image.Error) throw new Error(window.statusText || "Rendering failed")
                    if (!window.interactionReady || window.restoringView || !pages.count) return
                    var expected = sources[cursor % sources.length]
                    if (window.currentPage.path !== expected || !window.document || String(window.document.source) !== window.fileUri(expected))
                        throw new Error("Reader did not follow the new source")
                    if (renderedPage.status !== Image.Ready || renderedPage.currentFrame !== window.currentPage.page - 1) { readyAt = 0; return }
                    if (phase === 0) {
                        if (!readyAt) readyAt = Date.now()
                        if (Date.now() - readyAt < Number(Quickshell.env("SESSION_SETTLE_MS"))) return
                        if (window.dirty || window.undoStack.length || window.redoStack.length) throw new Error("Reading changed the draft")
                        if (cursor === 0 || (cursor + 1) % 5 === 0 || cursor >= sources.length - 1) {
                            console.log("SESSION_CHECKPOINT " + JSON.stringify({opened:Math.min(cursor+1,sources.length),
                                reopened:cursor === sources.length,readers:Object.keys(window.pdfDocuments).length,
                                residentReaders:Object.keys(window.pdfDocuments).filter(p => String(window.pdfDocuments[p].source) === window.fileUri(p)).length,
                                allocatedReaders:window.pdfReaderStats ? window.pdfReaderStats.allocated : Object.keys(window.pdfDocuments).length,
                                scale:window.devicePixelRatio,
                                ready_ms:Date.now()-openedAt}))
                        }
                        checkpointAt = Date.now(); phase = 1
                    } else if (Date.now() - checkpointAt >= 200) {
                        if (cursor === sources.length) {
                            running = false; console.log("READER_SESSION_PASS"); Qt.callLater(Qt.quit); return
                        }
                        cursor++; readyAt = 0; phase = 0; openedAt = Date.now()
                        window.replaceWorkspace([sources[cursor % sources.length]])
                    }
                } catch (error) { running = false; console.error("Error: " + error); Qt.callLater(Qt.quit) }
            }
        }
'''

with tempfile.TemporaryDirectory(prefix='oma-reader-session-') as scratch:
    work = Path(scratch)
    paths = []
    for index in range(count):
        target = work/f'document-{index:03}.pdf'
        subprocess.run(['cp', '--reflink=auto', str(source), str(target)], check=True)
        paths.append(str(target))
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               QT_SCALE_FACTOR=str(args.scale),
               SESSION_SETTLE_MS='300' if args.max_resident_readers is not None else '150',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/release/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps(paths[:1]), OMA_PREVIEW_REVIEW_SPEC='', SESSION_PATHS=json.dumps(paths),
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    with (work/'session.log').open('w+') as output, (work/'session.log').open() as reader:
        process = subprocess.Popen(['qs', '-p', str(work/'ui')], env=env, stdout=output, stderr=subprocess.STDOUT)
        checkpoints = []
        log = ''
        pending = ''
        deadline = time.monotonic() + max(120, count * 3)
        try:
            while process.poll() is None:
                chunk = reader.read()
                log += chunk
                lines = (pending + chunk).split('\n')
                pending = lines.pop()
                for line in lines:
                    if 'SESSION_CHECKPOINT ' not in line:
                        continue
                    checkpoint = json.loads(line.split('SESSION_CHECKPOINT ', 1)[1])
                    status = Path(f'/proc/{process.pid}/status').read_text()
                    values = {line.split(':', 1)[0]:int(line.split()[1]) for line in status.splitlines()
                              if line.startswith(('VmRSS:', 'RssAnon:', 'RssFile:'))}
                    checkpoint.update({key+'_mib':round(value/1024, 1) for key, value in values.items()})
                    checkpoints.append(checkpoint)
                    print(json.dumps(checkpoint), flush=True)
                if time.monotonic() > deadline:
                    raise TimeoutError('Reader session timed out')
                time.sleep(0.02)
            log += reader.read()
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
    if process.returncode or 'READER_SESSION_PASS' not in log or 'Error:' in log or 'Binding loop' in log:
        raise SystemExit(log)
    assert checkpoints[-1]['reopened'], 'Final memory checkpoint was not sampled'
    assert all(point['scale'] == args.scale for point in checkpoints), 'Requested rendering scale was not used'
    if args.expect_source_only:
        assert all(point['readers'] == 0 for point in checkpoints), 'High-DPI rendering retained redundant shared readers'
    if args.max_resident_readers is not None:
        assert all(point['residentReaders'] <= args.max_resident_readers for point in checkpoints), 'Resident reader cache exceeded its settled limit'
        assert checkpoints[-1]['allocatedReaders'] <= args.max_resident_readers + 1, 'Sequential opening accumulated reader shells'
    assert hashlib.sha256(source.read_bytes()).digest() == before, 'Source changed'
    assert not list((work/'state/folio/drafts').glob('*.json')) or all(
        path.name.endswith('.view.json') for path in (work/'state/folio/drafts').glob('*.json'))
    print('PASS: successive sources and return-to-first render; no edits/drafts/source changes; private UI memory observations only')
