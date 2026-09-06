#!/usr/bin/env python3
"""Verify transparent PDFs have light paper, correct proportions and dark ink."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = Path(tempfile.mkdtemp(prefix='thumbnail-paper-', dir=root/'output'))
with tempfile.TemporaryDirectory(prefix='oma-thumbnail-paper-') as scratch:
    work = Path(scratch)
    for index, (width, height) in enumerate(((300, 420), (420, 300), (300, 300))):
        # No background rectangle: the PDF raster has transparent paper.
        (work/f'{index}.svg').write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">
<text x="20" y="60" font-family="sans-serif" font-size="30" fill="black">Readable ink</text>
<rect x="20" y="90" width="100" height="12" fill="black"/>
</svg>''')
        subprocess.run(['rsvg-convert', '--format=pdf', f'--output={work}/{index}.pdf', str(work/f'{index}.svg')], check=True)
    source = work/'transparent.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', *[part for i in range(3) for part in (str(work/f'{i}.pdf'), '1')], '--', str(source)], check=True)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        function findPaper(item) {
            if (item.objectName === "test-thumbnail-paper") return item
            for (var child of item.children || []) { var found = findPaper(child); if (found) return found }
            return null
        }
        Timer {
            interval: 100; running: true; repeat: true
            property int stage: 0
            property int captured: 0
            property bool pending: false
            onTriggered: {
                if (window.busy || window.loadingWorkspace || window.restoringView || pages.count !== 3 || pending) return
                if (stage === 0 || stage === 2) {
                    window.height = 900
                    Theme.load(stage === 0 ? 'background="#151515"\\nforeground="#eeeeee"\\naccent="#99bbff"'
                                           : 'background="#fafafa"\\nforeground="#222222"\\naccent="#2255aa"')
                    stage++; return
                }
                if (stage === 4) { console.log("THUMBNAIL_PAPER_PASS"); Qt.quit(); return }
                for (var index = 0; index < 3; index++) {
                    var row = pageList.itemAtIndex(index)
                    if (!row || !row.thumbnailReady) return
                }
                var mode = stage === 1 ? "dark" : "light"
                captured = 0; pending = true
                for (let i = 0; i < 3; i++) {
                    let paper = window.findPaper(pageList.itemAtIndex(i))
                    if (!paper || Math.abs(paper.width / paper.height - pages.get(i).width / pages.get(i).height) > 0.001) {
                        console.error("Error: Thumbnail paper proportions changed"); Qt.quit(); return
                    }
                    paper.grabToImage(function(result) {
                        if (!result.saveToFile(OUTPUT + "/" + mode + "-" + i + ".png")) {
                            console.error("Error: Thumbnail capture failed"); Qt.quit(); return
                        }
                        captured++
                        if (captured === 3) { pending = false; stage++ }
                    })
                }
            }
        }
'''.replace('OUTPUT', json.dumps(str(output)))
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('id: thumbnailPaper', 'id: thumbnailPaper; objectName: "test-thumbnail-paper"')
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, capture_output=True, text=True, timeout=15)
    log = result.stdout + result.stderr
    if 'THUMBNAIL_PAPER_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
    for mode in ('dark', 'light'):
        for index in range(3):
            path = output/f'{mode}-{index}.png'
            white = float(subprocess.check_output(['magick', str(path), '-crop', '4x4+0+0', '-format', '%[fx:mean]', 'info:'], text=True))
            ink = float(subprocess.check_output(['magick', str(path), '-threshold', '30%', '-format', '%[fx:mean]', 'info:'], text=True))
            assert white > 0.99, f'Paper is not white: {path}'
            assert 0.8 < ink < 0.995, f'Missing or unreadable ink: {path}'
print('PASS: transparent portrait, landscape and square thumbnails on dark/light chrome')
print(output)
