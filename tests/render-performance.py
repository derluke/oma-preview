#!/usr/bin/env python3
"""Measure full-UI page readiness/zoom settling on supplied PDFs, without desktop input.

Warm filesystem caches, offscreen software rendering; these are not GPU frame times.
Uses no global input, writes no PDF, and isolates reading/draft state.
"""
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
sources = [Path(arg).resolve(strict=True) for arg in sys.argv[1:]]
if not sources:
    raise SystemExit('Usage: python tests/render-performance.py PDF [PDF ...]')
harness = '''
        Timer {
            interval: 16; running: true; repeat: true
            property int step: -1
            property double requestedAt: PROCESS_STARTED
            property double lastTick: Date.now()
            property double maxGap: 0
            property double operationGap: 0
            property var results: []
            property var destinations: []
            property string operation: "open"
            onTriggered: {
                var now = Date.now()
                maxGap = Math.max(maxGap, now - lastTick)
                operationGap = Math.max(operationGap, now - lastTick); lastTick = now
                if (window.busy || window.loadingWorkspace || window.restoringView || !pages.count) return
                if (renderedPage.status === Image.Error) { console.error("Error: PDF rendering failed"); Qt.quit(); return }
                var expected = Math.round(renderedPage.width)
                var ratio = renderedPage.sourceSize.width > 0 ? expected / renderedPage.sourceSize.width : 0
                if (renderedPage.status !== Image.Ready || ratio < 0.88 || ratio > 1.12 || now - requestedAt < 32) return
                if (renderedPage.currentFrame !== window.currentPage.page - 1) return
                results.push({operation:operation, ms:now - requestedAt, page:window.currentIndex + 1, tickGapMs:operationGap})
                if (step < 0) destinations = [1, 2, 3, Math.floor(pages.count / 2), pages.count - 1, 0, Math.floor(pages.count / 3), pages.count - 2, 1, 0].map(p => Math.max(0, Math.min(pages.count - 1, p)))
                step++
                requestedAt = Date.now()
                operationGap = 0
                if (step < destinations.length) {
                    operation = "page"
                    window.jumpToPage(destinations[step])
                } else if (step < destinations.length + 3) {
                    operation = "zoom"
                    window.zoomTo([1.5, 2, 1][step - destinations.length])
                } else {
                    console.log("RENDER_PERF " + JSON.stringify({pages:pages.count, dpr:window.devicePixelRatio, maxTickGapMs:maxGap, samples:results}))
                    Qt.quit()
                }
            }
        }
'''

for source in sources:
    for scale in (1, 2):
        with tempfile.TemporaryDirectory(prefix='oma-render-perf-') as scratch:
            work = Path(scratch)
            shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
            if os.environ.get('OMA_PREVIEW_RENDER_TRACE') == '1':
                raster = work/'ui/PdfRaster.qml'
                raster.write_text(raster.read_text().replace('    id: root', '''    id: root
    objectName: "trace-" + Math.random()
    onStatusChanged: if (status === Image.Ready) console.log("RASTER_TRACE " + JSON.stringify({item:objectName, page:currentFrame, width:sourceSize.width, displayWidth:width}))'''))
            started = time.time() * 1000
            shell = work/'ui/shell.qml'
            shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                             .replace('        Component.onCompleted: {', harness.replace('PROCESS_STARTED', str(started))+'\n        Component.onCompleted: {'))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                       QT_QUICK_BACKEND='software', QT_SCALE_FACTOR=str(scale),
                       OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
                       OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
                       XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
            env.pop('DISPLAY', None)
            env.pop('WAYLAND_DISPLAY', None)
            log_file = (work/'render.log').open('w+')
            process = subprocess.Popen(['qs', '-p', str(work/'ui')], env=env,
                                       stdout=log_file, stderr=subprocess.STDOUT, text=True)
            deadline = time.monotonic() + 45
            peak_kib = 0
            try:
                while process.poll() is None:
                    try:
                        status = Path(f'/proc/{process.pid}/status').read_text()
                        for line in status.splitlines():
                            if line.startswith('VmHWM:'):
                                peak_kib = max(peak_kib, int(line.split()[1]))
                    except FileNotFoundError:
                        pass
                    if time.monotonic() > deadline:
                        raise TimeoutError(f'Rendering timed out: {source.name} at {scale}x')
                    time.sleep(0.025)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                log_file.close()
            log = (work/'render.log').read_text()
            records = [json.loads(line.split('RENDER_PERF ', 1)[1]) for line in log.splitlines() if 'RENDER_PERF ' in line]
            if process.returncode or len(records) != 1 or 'Error:' in log:
                raise SystemExit(log)
            record = records[0]
            traces = [json.loads(line.split('RASTER_TRACE ', 1)[1]) for line in log.splitlines() if 'RASTER_TRACE ' in line]
            if traces:
                print(json.dumps({'file':source.name, 'scale':scale, 'raster_trace':traces}), flush=True)
            page_times = [s['ms'] for s in record['samples'] if s['operation'] == 'page']
            zoom_times = [s['ms'] for s in record['samples'] if s['operation'] == 'zoom']
            print(json.dumps({'file':source.name, 'scale':scale, 'pages':record['pages'],
                              'open_ms':record['samples'][0]['ms'],
                              'page_median_ms':statistics.median(page_times), 'page_max_ms':max(page_times),
                              'zoom_median_ms':statistics.median(zoom_times), 'zoom_max_ms':max(zoom_times),
                              'max_tick_gap_ms':record['maxTickGapMs'],
                              'worst_tick_operation':max(record['samples'], key=lambda s:s['tickGapMs'])['operation'],
                              'page_tick_max_ms':max(s['tickGapMs'] for s in record['samples'] if s['operation'] == 'page'),
                              'zoom_tick_max_ms':max(s['tickGapMs'] for s in record['samples'] if s['operation'] == 'zoom'),
                              'sampled_peak_rss_mib':round(peak_kib / 1024, 1)}), flush=True)
