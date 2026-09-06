#!/usr/bin/env python3
"""Capture the actual UI at two widths without a desktop connection."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
output = Path(tempfile.mkdtemp(prefix='oma-visual-', dir=root/'output'))
harness = '''
        property int visualStep: 0
        property bool visualCapture: false
        Timer {
            interval: 200; running: true; repeat: true
            onTriggered: {
                if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready || window.visualCapture) return
                if (window.visualStep === 0) {
                    window.width = 640; window.height = 720
                    window.say("Saved /documents/a-very-long-output-directory/another-folder/a-very-long-document-name-with-important-details-and-a-long-output-location.pdf", false)
                }
                if (window.visualStep === 2 || window.visualStep === 6) {
                    annotations.clear()
                    annotations.append({kind:"text", pageKey:window.currentPage.key, nx:0.1, ny:0.4, value:"Alex Morgan", size:14, fontFamily:"sans-serif", inkColor:"#111111", nw:0.5, nh:0, strokeData:"[]"})
                    window.selectedAnnotation = 0
                }
                if (window.visualStep === 4) { window.selectedAnnotation = -1; window.width = 1040 }
                if (window.visualStep === 8) { window.selectedAnnotation = -1; window.width = 640; window.draftNoticeVisible = true }
                if (window.visualStep === 10) {
                    window.draftNoticeVisible = false
                    window.recents = ["/home/example/Documents/Clients/North Studio/Project proposal.pdf", "/home/example/Documents/Clients/South Studio/Project proposal.pdf"]
                    for (var i = 0; i < 10; i++) window.recents = window.recents.concat(["/home/example/Documents/Archive/2026/A long document filename with important distinguishing details " + (i + 1) + ".pdf"])
                    recentMenu.open()
                }
                if (window.visualStep === 12) {
                    recentMenu.close()
                    var marked = {}; marked[window.currentPage.path] = [1, 2]; window.bookmarks = marked
                    bookmarkMenu.open(); bookmarkMenu.focusEntry(0)
                }
                if (window.visualStep === 14) Theme.load('background="#f5f5f5"\\nforeground="#333333"\\naccent="#2450a4"')
                if (window.visualStep === 16) { bookmarkMenu.close(); pageJump.open() }
                if (window.visualStep === 18) { pageJump.close(); closeDialog.open() }
                if (window.visualStep === 20) {
                    closeDialog.close()
                    window.draftProblem = "Cannot access source PDF: /home/example/Documents/Clients/North Studio/Supporting documents/Original signed attachment.pdf: No such file or directory"
                    draftRecovery.open()
                }
                if (window.visualStep === 22) { draftRecovery.close(); window.draftProblem = ""; window.openPageActions(window.currentIndex) }
                if (window.visualStep === 24) Theme.load('background="#20222b"\\nforeground="#cdd6f4"\\naccent="#7aa2f7"')
                if (window.visualStep === 26) { pageMenu.close(); window.signature = [[]]; signatureMenu.open() }
                if (window.visualStep === 28) { signatureMenu.close(); signatureDialog.open() }
                if (window.visualStep >= 30) { console.log("VISUAL_SMOKE_PASS"); Qt.quit(); return }
                if (window.visualStep % 2 === 0) { window.visualStep++; return }
                if (statusMessage.x + statusMessage.width + 8 > zoomControls.x || (formatControls.visible && formatControls.x + formatControls.width + 8 > zoomControls.x)) {
                    console.error("Error: Footer controls overlap"); Qt.quit(); return
                }
                if (Math.abs(documentTitle.y + documentTitle.height / 2 - fileControls.y - fileControls.height / 2) > 0.1) {
                    console.error("Error: Document title is not centred with file controls"); Qt.quit(); return
                }
                if (window.visualStep === 9 && (noticeText.x < 0 || noticeText.x + noticeText.width > noticeDismiss.x || noticeText.height > draftNotice.height - 12)) {
                    console.error("Error: Draft notice content does not fit"); Qt.quit(); return
                }
                var names = {1:"narrow-reading", 3:"narrow-editing", 5:"normal-reading", 7:"normal-editing", 9:"narrow-draft-restored",
                    11:"narrow-recents", 13:"bookmarks-dark", 15:"bookmarks-light", 17:"go-to-page", 19:"close-choices", 21:"draft-recovery",
                    23:"page-actions-light", 25:"page-actions-dark", 27:"signature-menu", 29:"signature-dialog"}
                var name = names[window.visualStep]
                window.visualCapture = true
                window.contentItem.grabToImage(function(result) {
                    if (!result.saveToFile(OUTPUT + "/" + name + ".png")) { console.error("Error: Capture failed"); Qt.quit(); return }
                    window.visualCapture = false; window.visualStep++
                })
            }
        }
'''.replace('OUTPUT', json.dumps(str(output)))
with tempfile.TemporaryDirectory(prefix='oma-visual-ui-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, capture_output=True, text=True, timeout=20)
    log = result.stdout + result.stderr
    if 'VISUAL_SMOKE_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
print(output)
