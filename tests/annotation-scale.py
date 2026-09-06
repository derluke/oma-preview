#!/usr/bin/env python3
"""Exercise page-local annotation rendering and actual editing with private state."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = '''
        TestCase { id: editInput; name: "AnnotationScale"; when: false }
        Timer {
            interval: 60; running: true; repeat: true
            property int phase: 0
            property var editor
            property int target: 1000
            property double began: 0
            property double loadMs: 0
            property real oldX: 0
            property bool stepping: false
            property int focusWait: 0
            property var neighboringReader
            property real beforeUndoY: 0
            function item(index) {
                return annotationRepeater.itemForAnnotation ? annotationRepeater.itemForAnnotation(index) : annotationRepeater.itemAt(index)
            }
            onTriggered: {
                if (stepping) return
                stepping = true
                try {
                    if (!window.interactionReady || window.restoringView || renderedPage.status !== Image.Ready) return
                    if (phase === 0) {
                        began = Date.now()
                        for (var p = 0; p < pages.count; p++) for (var n = 0; n < 20; n++)
                            annotations.append({kind:"text", pageKey:pages.get(p).key, nx:0.1 + (n % 2) * 0.42,
                                ny:0.08 + Math.floor(n / 2) * 0.07, value:"Field " + (p * 20 + n), size:12,
                                fontFamily:"sans-serif", inkColor:"#111111", nw:0.30, nh:0, strokeData:"[]"})
                        window.markDirty(); draftTimer.stop()
                    } else if (phase === 1) {
                        loadMs = Date.now() - began
                        console.log("ANNOTATION_SCALE " + JSON.stringify({marks:annotations.count,
                            edit_delegates:annotationRepeater.count, setup_and_settle_ms:loadMs}))
                        if (annotationRepeater.count !== 20) throw new Error("Editor allocates off-page annotation delegates")
                        window.jumpToPage(50)
                    } else if (phase === 2) {
                        if (annotationRepeater.count !== 20 || !item(target) || !item(target).item) throw new Error("Page-local editor lost global annotation identity")
                        editor = item(target).item
                        oldX = annotations.get(target).nx
                        editInput.mouseClick(editor, 12, 8)
                        if (window.selectedAnnotation !== target) throw new Error("Click selected the wrong annotation")
                        editInput.mousePress(editor, 12, 8)
                        editInput.mouseMove(editor, 32, 8, 20)
                        editInput.mouseMove(editor, 52, 8, 20)
                        editInput.mouseRelease(editor, 52, 8)
                    } else if (phase === 3) {
                        if (!(annotations.get(target).nx > oldX)) throw new Error("Dragging did not move the selected box")
                        beforeUndoY = viewport.contentY
                        editInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 4) {
                        if (Math.abs(annotations.get(target).nx - oldX) > 0.0001) throw new Error("Move did not undo")
                        if (Math.abs(viewport.contentY - beforeUndoY) > 0.5) throw new Error("Undo moved the viewport")
                        if (!item(target)) throw new Error("Undo lost visible field: " + JSON.stringify({page:window.currentIndex,
                            delegates:annotationRepeater.count, indices:annotationIndex.forPage(window.currentPage.key),
                            fieldPage:annotations.get(target).pageKey, pageKey:window.currentPage.key}))
                        editor = item(target).item
                        editInput.mouseDoubleClickSequence(editor, 12, 8)
                    } else if (phase === 5) {
                        if (window.editingAnnotation === target && !editor.activeFocus && focusWait++ < 10) return
                        if (window.editingAnnotation !== target || !editor.activeFocus) throw new Error("Double click did not edit the right field: " + JSON.stringify({editing:window.editingAnnotation,
                            selected:window.selectedAnnotation, text:editor.text, focus:editor.activeFocus, current:window.currentIndex,
                            sameEditor:item(target).item === editor, actualFocus:item(target).item.activeFocus,
                            x:editor.x,y:editor.y,viewportY:viewport.contentY,paperY:paper.y}))
                        editInput.keyClick(Qt.Key_End)
                        editInput.keyClick(Qt.Key_X)
                    } else if (phase === 6) {
                        if (item(target).item !== editor || !editor.activeFocus || annotations.get(target).value !== "Field 1000x")
                            throw new Error("Typing rebuilt the editor or lost text/focus")
                        editInput.keyClick(Qt.Key_Return, Qt.ShiftModifier)
                        editInput.keyClick(Qt.Key_Y)
                        editInput.keyClick(Qt.Key_Return)
                    } else if (phase === 7) {
                        if (annotations.get(target).value !== "Field 1000x\\ny" || window.editingAnnotation >= 0) throw new Error("Multiline edit failed")
                        editInput.keyClick(Qt.Key_Delete)
                    } else if (phase === 8) {
                        if (annotations.count !== 1999 || annotationRepeater.count !== 19) throw new Error("Delete did not update the page-local model")
                        editInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 9) {
                        if (annotations.count !== 2000 || annotationRepeater.count !== 20 || item(target).item.text !== "Field 1000x\\ny")
                            throw new Error("Undo did not restore annotation rendering")
                        annotations.setProperty(target, "pageKey", pages.get(51).key)
                    } else if (phase === 10) {
                        if (annotationRepeater.count !== 19 || item(target)) throw new Error("Page reassignment left an old delegate")
                        window.clearCanvasSelection(); window.jumpToPage(51)
                    } else if (phase === 11) {
                        if (annotationRepeater.count !== 21 || !item(target) || item(target).item.text !== "Field 1000x\\ny")
                            throw new Error("Page reassignment lost its delegate")
                        // New text must focus synchronously enough for the first keystroke.
                        window.tool = "text"
                        focusWait = 0
                        editInput.mouseClick(paper, paper.width * 0.44, paper.height * 0.18)
                    } else if (phase === 12) {
                        var added = annotations.count - 1
                        if (window.editingAnnotation === added && (!item(added) || !item(added).item.activeFocus) && focusWait++ < 10) return
                        if (window.editingAnnotation !== added || !item(added).item.activeFocus) throw new Error("New text did not take focus")
                        editInput.keyClick(Qt.Key_A)
                        editInput.keyClick(Qt.Key_Escape)
                    } else if (phase === 13) {
                        if (annotations.count !== 2000 || window.editingAnnotation >= 0) throw new Error("Escape did not cancel new text")
                        window.zoom = 0.5
                        window.positionReadingPage(51, false)
                    } else if (phase === 14) {
                        for (var r = 0; r < readingRepeater.count; r++) {
                            var reader = readingRepeater.itemAt(r)
                            if (reader.item) {
                                var expected = reader.pageIndex === 50 ? 19 : reader.pageIndex === 51 ? 21 : 20
                                if (reader.item.annotationItems.count !== expected) throw new Error("Neighboring reader allocates off-page annotations: "
                                    + JSON.stringify({page:reader.pageIndex, count:reader.item.annotationItems.count, expected:expected}))
                                if (reader.pageIndex === 52) neighboringReader = reader.item
                            }
                        }
                        if (!neighboringReader) throw new Error("Continuous mode did not load the neighboring page")
                        annotations.setProperty(1040, "value", "Nearby page")
                    } else if (phase === 15) {
                        var readMark = neighboringReader.annotationItems.itemAt(0)
                        if (readMark.index !== 1040 || readMark.item.text !== "Nearby page") throw new Error("Neighboring text did not update live: "
                            + JSON.stringify({index:readMark.index, text:readMark.item.text, value:readMark.value,
                                model:annotations.get(1040).value, page:neighboringReader.page}))
                        target = 1021
                        window.jumpToPage(51)
                    } else if (phase === 16) {
                        editor = item(target).item
                        editInput.mouseClick(editor, 12, 8)
                        if (window.selectedAnnotation !== target) throw new Error("Formatting selected the wrong box")
                        editInput.mouseClick(formatSizeUp)
                        editInput.mouseClick(formatFont)
                        editInput.mouseClick(inkBlue)
                    } else if (phase === 17) {
                        var formatted = annotations.get(target)
                        if (formatted.size !== 14 || editor.font.pixelSize !== Math.round(formatted.size * paper.width / window.currentPage.width)
                            || editor.font.family !== formatted.fontFamily || String(editor.color) !== formatted.inkColor)
                            throw new Error("Formatting controls did not update the visible text")
                        window.clearCanvasSelection(); window.tool = "text"; focusWait = 0
                        editInput.mouseClick(paper, paper.width * 0.44, paper.height * 0.18)
                    } else if (phase === 18) {
                        var blank = annotations.count - 1
                        if (window.editingAnnotation === blank && (!item(blank) || !item(blank).item.activeFocus) && focusWait++ < 10) return
                        if (window.editingAnnotation !== blank || !item(blank).item.activeFocus) throw new Error("Empty text did not focus")
                        editInput.keyClick(Qt.Key_Return)
                    } else if (phase === 19) {
                        if (annotations.count !== 2000 || window.editingAnnotation >= 0) throw new Error("Enter did not remove empty text safely")
                        draftTimer.stop(); running = false; console.log("ANNOTATION_SCALE_PASS"); Qt.quit()
                    }
                    phase++
                } catch (error) { running = false; console.error("Error: phase " + phase + ": " + error); Qt.callLater(Qt.quit) }
                finally { stepping = false }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-annotation-scale-') as scratch:
    work = Path(scratch)
    one, source = work/'one.pdf', work/'source.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(one), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', *[v for _ in range(100) for v in (str(one), '1')], '--', str(source)], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text('import QtTest\n'+shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    with (work/'test.log').open('w+') as stream:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=45)
        stream.seek(0)
        log = stream.read()
    if result.returncode or 'ANNOTATION_SCALE_PASS' not in log or 'Error:' in log or 'Binding loop' in log:
        raise SystemExit(log)
    assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source changed'
    print(next(line for line in log.splitlines() if 'ANNOTATION_SCALE ' in line))
    print('PASS: 2,000 annotations, page-local delegates, actual select/drag/edit/multiline/delete/undo/cancel; source unchanged')
