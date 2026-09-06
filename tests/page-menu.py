#!/usr/bin/env python3
"""Actual thumbnail context-menu, keyboard and page-edit flows; no desktop input."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-page-menu-') as scratch:
    work = Path(scratch)
    source = work/'source.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', *[part for _ in range(4) for part in (str(work/'one.pdf'), '1')], '--', str(source)], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        TestCase { id: pageInput; name: "PageMenu"; when: false }
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            property string secondKey: ""
            property double previousY: 0
            onTriggered: {
                try {
                    if (window.busy || window.loadingWorkspace || window.restoringView || renderedPage.status !== Image.Ready) return
                    if (phase === 0) {
                        var second = pageList.itemAtIndex(1)
                        if (!second || !second.thumbnailReady) return
                        secondKey = pages.get(1).key
                        pageInput.mouseClick(second, second.width / 2, 60, Qt.RightButton)
                    } else if (phase === 1) {
                        if (!pageMenu.visible || window.currentIndex !== 1 || window.dirty || pageMenuTitle.text !== "Page 2") throw new Error("Right click did not target the clicked page")
                        if (pageMenu.x < 0 || pageMenu.y < 0 || pageMenu.x + pageMenu.width > window.width || pageMenu.y + pageMenu.height > window.height) throw new Error("Context menu is offscreen")
                        if (window.applyLiveReview("/unused.json", false)) throw new Error("Agent edit bypassed page menu")
                        pageInput.mouseClick(pageBookmark)
                    } else if (phase === 2) {
                        if (!window.isBookmarked() || window.dirty || pageMenu.visible) throw new Error("Context bookmark failed or dirtied the PDF: " + JSON.stringify({bookmarked:window.isBookmarked(), dirty:window.dirty, menu:pageMenu.visible, page:window.currentIndex, bookmarks:window.bookmarks}))
                        previousY = viewport.contentY
                        var button = pageList.itemAtIndex(1).actionsButton
                        if (button.x < 6 || button.x + button.width > sidebar.width - 26 || button.label !== "Page 2 ⌄") throw new Error("Selected page caption overlaps its bookmark")
                        pageInput.mouseClick(button)
                    } else if (phase === 3) {
                        if (!pageMenu.visible || Math.abs(viewport.contentY - previousY) > 0.5 || pageBookmark.text !== "Remove bookmark") throw new Error("Opening actions moved the current page or lost bookmark state")
                        pageInput.mouseClick(pageMoveDown)
                    } else if (phase === 4) {
                        if (window.currentIndex !== 2 || pages.get(2).key !== secondKey || !window.dirty) throw new Error("Move down affected the wrong page")
                        pageInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 5) {
                        if (window.currentIndex !== 1 || pages.get(1).key !== secondKey || window.dirty) throw new Error("Page move did not undo: " + JSON.stringify({index:window.currentIndex, key:pages.get(1).key, expected:secondKey, dirty:window.dirty, undo:window.undoStack.length, redo:window.redoStack.length, modal:window.modalActive}))
                        paper.forceActiveFocus()
                        pageInput.keyClick(Qt.Key_F10, Qt.ShiftModifier)
                    } else if (phase === 6) {
                        if (!pageMenu.visible) throw new Error("Keyboard page actions did not open")
                        pageInput.mouseClick(pageRemove)
                    } else if (phase === 7) {
                        if (pages.count !== 3 || window.pagePayload().some(p => p.key === secondKey)) throw new Error("Remove affected the wrong page")
                        pageInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 8) {
                        if (pages.count !== 4 || pages.get(1).key !== secondKey || !window.isBookmarked() || window.dirty) throw new Error("Removed page/bookmark did not return on undo")
                        pageList.itemAtIndex(1).actionsButton.forceActiveFocus(Qt.TabFocusReason)
                        pageInput.keyClick(Qt.Key_Return)
                    } else if (phase === 9) {
                        if (!pageMenu.visible) throw new Error("Caption did not activate by keyboard")
                        pageInput.keyClick(Qt.Key_Escape)
                    } else if (phase === 10) {
                        if (pageMenu.visible) throw new Error("Escape did not close page actions")
                        window.sidebarVisible = false
                        paper.forceActiveFocus()
                        pageInput.keyClick(Qt.Key_F10, Qt.ShiftModifier)
                    } else if (phase === 11) {
                        if (!pageMenu.visible || pageMenu.x < 0 || pageMenu.x + pageMenu.width > window.width) throw new Error("Collapsed-sidebar page actions failed")
                        if (pageMenu.currentIndex < 0) pageInput.keyClick(Qt.Key_Down)
                        pageInput.keyClick(Qt.Key_Return)
                    } else if (phase === 12) {
                        if (pageMenu.visible || window.isBookmarked()) throw new Error("Page actions did not navigate and activate by keyboard")
                        // Only enter/cancel the tool. No signature is drawn, saved,
                        // placed, read from user storage or exported in this test.
                        window.signature = [[]]
                        pageInput.mouseClick(signButton)
                    } else if (phase === 13) {
                        if (!signatureMenu.visible || signatureMenu.width < 180 || signaturePlace.width < 150) throw new Error("Signature menu has no usable width")
                        pageInput.mouseClick(signaturePlace)
                    } else if (phase === 14) {
                        if (window.tool !== "sign" || signatureMenu.visible || annotations.count) throw new Error("Signature menu did not enter placement mode cleanly")
                        pageInput.keyClick(Qt.Key_Escape)
                        pageInput.mouseClick(signButton)
                    } else if (phase === 15) {
                        pageInput.mouseClick(signatureDraw)
                    } else if (phase === 16) {
                        if (!signatureDialog.visible || !signatureDialog.cancelButton.activeFocus || signatureDialog.saveButton.enabled) throw new Error("Signature dialog did not take safe initial focus")
                        for (var i = 0; i < 6; i++) {
                            pageInput.keyClick(Qt.Key_Tab)
                            if (!signatureDialog.cancelButton.activeFocus && !signatureDialog.clearButton.activeFocus) throw new Error("Signature dialog let Tab escape to the PDF")
                        }
                        pageInput.keyClick(Qt.Key_Escape)
                    } else if (phase === 17) {
                        if (signatureDialog.visible || annotations.count || window.dirty || window.tool !== "read") throw new Error("Cancelling signature controls changed the document")
                        window.jumpToPage(3)
                    } else if (phase === 18) {
                        annotations.append({kind:"text", pageKey:window.currentPage.key, nx:0.1, ny:0.1, value:"Example", size:14,
                            fontFamily:"sans-serif", inkColor:"#111111", nw:0.3, nh:0, strokeData:"[]"})
                        window.markDirty()
                        window.jumpToPage(0)
                    } else if (phase === 19) {
                        pageInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else {
                        if (window.currentIndex !== 3 || annotations.count || window.dirty) throw new Error("Annotation undo did not return to the edited page")
                        running = false; console.log("PAGE_MENU_PASS"); Qt.quit(); return
                    }
                    phase++
                } catch (error) { running = false; console.error("Error: " + error); Qt.quit() }
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
    result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, capture_output=True, text=True, timeout=20)
    log = result.stdout + result.stderr
    if 'PAGE_MENU_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
    assert hashlib.sha256(source.read_bytes()).digest() == original
    print('PASS: thumbnail context/keyboard menus, bookmarks, move/remove/undo focus, signature controls/cancel; source unchanged')
