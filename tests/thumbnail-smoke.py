#!/usr/bin/env python3
"""Offscreen thumbnail lifecycle test; pass a PDF with at least ten pages."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
harness = '''
        TestCase { id: bookmarkInput; name: "BookmarkInput"; when: false }
        property int readerCreations: 0
        Timer {
            interval: 100; running: true; repeat: true
            property int phase: 0
            property int peak: 0
            property int readersBefore: 0
            property var previousPages: []
            property double startedAt: Date.now()
            onTriggered: {
                if (window.visibleReadingPages.length > 6) throw new Error("Continuous reader loaded too many pages")
                if (window.busy || window.loadingWorkspace || pages.count < 10) return
                var active = 0
                var rows = pageList.contentItem.children
                for (var i = 0; i < rows.length; i++) if (rows[i].thumbnailActive === true) active++
                peak = Math.max(peak, active)
                if (active > Math.ceil(pageList.height / 184) + 1) throw new Error("Offscreen thumbnails rendered")
                if (phase === 0) {
                    var first = pageList.itemAtIndex(0)
                    if (!first || !first.thumbnailReady) return
                    pageList.currentIndex = pages.count - 1
                    pageList.positionViewAtIndex(pages.count - 1, ListView.End)
                    phase++
                } else if (phase === 1) {
                    var last = pageList.itemAtIndex(pages.count - 1)
                    if (!last || !last.thumbnailReady) return
                    window.sidebarVisible = false
                    phase++
                } else if (phase === 2) {
                    if (active !== 0 || sidebar.width !== 0) throw new Error("Collapsed sidebar retained thumbnails")
                    if (window.currentIndex !== pages.count - 1) throw new Error("Collapse lost selected page")
                    window.sidebarVisible = true
                    phase++
                } else if (phase === 3) {
                    var selected = pageList.itemAtIndex(pages.count - 1)
                    if (!selected || !selected.thumbnailReady) return
                    if (selected.actionsButton.x < 6 || selected.actionsButton.x + selected.actionsButton.width > sidebar.width - 26)
                        throw new Error("Long page number overlaps sidebar actions or bookmark")
                    if (window.currentIndex !== pages.count - 1) throw new Error("Expand lost selected page")
                    viewport.contentY = window.pageGeometry(5).top
                    phase++
                } else if (phase === 4) {
                    readersBefore = window.readerCreations
                    previousPages = window.visibleReadingPages.slice()
                    viewport.contentY = window.pageGeometry(6).top
                    phase++
                } else if (phase === 5) {
                    var added = window.visibleReadingPages.filter(p => previousPages.indexOf(p) < 0).length
                    if (window.readerCreations - readersBefore !== added) throw new Error("Scrolling recreated overlapping page delegates")
                    var all = {}, marked = []
                    for (var page = 1; page <= Math.min(40, pages.count); page++) marked.push(page)
                    all[pages.get(0).path] = marked; window.bookmarks = all
                    bookmarkInput.mouseClick(bookmarkButton)
                    phase++
                } else if (phase === 6) {
                    if (!bookmarkMenu.visible || bookmarkMenu.height > window.height - toolbar.height) throw new Error("Bookmark menu overflows the window")
                    bookmarkInput.keyClick(Qt.Key_End)
                    phase++
                } else if (phase === 7) {
                    var entry = bookmarkMenu.itemAt(window.bookmarkEntries.length + 1)
                    var position = entry.mapToItem(bookmarkMenu.contentItem, 0, 0)
                    if (position.y < -1 || position.y + entry.height > bookmarkMenu.contentItem.height + 1) { console.error("Error: Last bookmark not scrolled into view"); Qt.quit(); return }
                    bookmarkInput.keyClick(Qt.Key_Return)
                    phase++
                } else if (phase === 8) {
                    if (window.currentIndex !== Math.min(40, pages.count) - 1 || bookmarkMenu.visible) { console.error("Error: Long bookmark menu navigation failed", window.currentIndex, bookmarkMenu.visible, bookmarkMenu.currentIndex); Qt.quit(); return }
                    bookmarkInput.keyClick(Qt.Key_G, Qt.ControlModifier)
                    phase++
                } else if (phase === 9) {
                    if (!pageJump.visible || !pageJump.field.activeFocus || window.activeDialog !== "go-to-page") throw new Error("Go to page did not open with input focus")
                    if (window.applyLiveReview("/nonexistent.json", false)) throw new Error("Live edits accepted while choosing a page")
                    bookmarkInput.keyClick(Qt.Key_0)
                    bookmarkInput.keyClick(Qt.Key_Return)
                    if (!pageJump.visible || pageJump.goButton.enabled) throw new Error("Zero page accepted")
                    pageJump.field.text = String(pages.count + 1)
                    bookmarkInput.keyClick(Qt.Key_Return)
                    if (!pageJump.visible || pageJump.goButton.enabled) throw new Error("Out-of-range page accepted")
                    pageJump.field.selectAll()
                    for (var digit of String(pages.count)) bookmarkInput.keyClick(Qt.Key_0 + Number(digit))
                    bookmarkInput.keyClick(Qt.Key_Return)
                    phase++
                } else if (phase === 10) {
                    if (window.currentIndex !== pages.count - 1 || pageJump.visible) throw new Error("Go to last page failed")
                    bookmarkInput.keyClick(Qt.Key_G, Qt.ControlModifier)
                    phase++
                } else if (phase === 11) {
                    bookmarkInput.keyClick(Qt.Key_1)
                    bookmarkInput.keyClick(Qt.Key_Escape)
                    phase++
                } else if (phase === 12) {
                    if (window.currentIndex !== pages.count - 1 || pageJump.visible) throw new Error("Cancelling page jump moved the document")
                    bookmarkInput.keyClick(Qt.Key_G, Qt.ControlModifier)
                    phase++
                } else if (phase === 13) {
                    bookmarkInput.keyClick(Qt.Key_1)
                    bookmarkInput.mouseClick(pageJump.goButton)
                    phase++
                } else {
                    if (window.currentIndex !== 0 || pageJump.visible) throw new Error("Go button did not reach first page")
                    console.log("THUMBNAILS_PASS pages=" + pages.count + " peak=" + peak + " retained-readers=yes elapsed-ms=" + (Date.now() - startedAt))
                    Qt.quit()
                }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-thumbnails-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n').replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('id: readingLoader', 'id: readingLoader\n                            Component.onCompleted: window.readerCreations++')
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QSG_RHI_BACKEND='opengl', OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    with (work/'log').open('w+') as log:
        p = subprocess.Popen(['qs','-p',str(work/'ui')], env=env, stdout=log, stderr=log, start_new_session=True)
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
        finally:
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            p.wait(timeout=5)
        log.seek(0)
        result = log.read()
        if 'THUMBNAILS_PASS' not in result or 'Error:' in result:
            raise SystemExit(result)
        print(next(line for line in result.splitlines() if 'THUMBNAILS_PASS' in line))
