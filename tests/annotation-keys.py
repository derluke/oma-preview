#!/usr/bin/env python3
"""Keyboard placement, grouped undo and persistence without desktop input."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = '''
        TestCase { id: keyInput; name: "AnnotationKeys"; when: false }
        Connections { target: backend; function onQuitReady() { console.log("KEYS_CLOSED") } }
        Timer {
            interval: 60; running: true; repeat: true
            property int phase: 0
            property bool stepping: false
            property int baseSteps: 0
            property int focusWait: 0
            property var editor
            property real unit: 0
            function item(i) { return annotationRepeater.itemForAnnotation(i).item }
            function near(a, b) { return Math.abs(a - b) < 0.000001 }
            onTriggered: {
                if (stepping) return
                stepping = true
                try {
                    if (!window.interactionReady || window.restoringView || renderedPage.status !== Image.Ready) return
                    unit = 1 / window.currentPage.width
                    if (Quickshell.env("KEYS_STAGE") === "restore") {
                        if (!window.draftRestored || !near(annotations.get(0).nx, 0.2 + unit)) throw new Error("Nudge draft not restored")
                        window.travelHistory(false)
                        if (!near(annotations.get(0).nx, 0.2) || window.currentIndex !== 1) throw new Error("Restored nudge cannot undo")
                        draftTimer.stop(); running = false; console.log("KEYS_RESTORE_PASS"); Qt.quit(); return
                    }
                    if (phase === 0) {
                        window.jumpToPage(1)
                        annotations.append({kind:"text", pageKey:pages.get(1).key, nx:0.2, ny:0.2, value:"Sample", size:14,
                            fontFamily:"sans-serif", inkColor:"#111111", nw:0.25, nh:0, strokeData:"[]"})
                        // Empty private vector fixture: no signature is drawn,
                        // read from the user's library, applied or exported.
                        annotations.append({kind:"signature", pageKey:pages.get(1).key, nx:0.55, ny:0.2, value:"", size:0,
                            fontFamily:"sans-serif", inkColor:"#111111", nw:0.24, nh:0.09, strokeData:"[]"})
                        window.markDirty(); baseSteps = window.undoStack.length
                    } else if (phase === 1) {
                        keyInput.mouseClick(item(0), 12, 8)
                        keyInput.keyClick(Qt.Key_Right)
                        keyInput.keyClick(Qt.Key_Right, Qt.ShiftModifier)
                        keyInput.keyClick(Qt.Key_Right, Qt.ShiftModifier)
                    } else if (phase === 2) {
                        if (window.currentIndex !== 1 || !near(annotations.get(0).nx, 0.2 + 21 * unit)
                            || !near(item(0).x, annotations.get(0).nx * paper.width) || window.undoStack.length !== baseSteps + 1)
                            throw new Error("Nudge, visual position or grouped undo failed")
                        keyInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 3) {
                        if (!near(annotations.get(0).nx, 0.2) || window.currentIndex !== 1 || window.undoStack.length !== baseSteps)
                            throw new Error("Nudge gesture did not undo in one step")
                        keyInput.keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
                    } else if (phase === 4) {
                        if (!near(annotations.get(0).nx, 0.2 + 21 * unit)) throw new Error("Nudge redo failed")
                        keyInput.mouseClick(item(0), 12, 8)
                        keyInput.keyClick(Qt.Key_Left)
                        keyInput.keyClick(Qt.Key_Right)
                    } else if (phase === 5) {
                        if (window.undoStack.length !== baseSteps + 1) throw new Error("Net-zero nudges left an undo step")
                        formatFont.forceActiveFocus(Qt.TabFocusReason)
                        keyInput.keyClick(Qt.Key_Right)
                        if (!near(annotations.get(0).nx, 0.2 + 21 * unit) || window.currentIndex !== 1)
                            throw new Error("Annotation shortcuts stole focused-control arrows")
                        paper.forceActiveFocus()
                        keyInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 6) {
                        window.zoom = 0.75; window.positionReadingPage(1, false)
                        keyInput.mouseClick(item(1), 12, 8)
                        keyInput.keyClick(Qt.Key_Right)
                        keyInput.keyClick(Qt.Key_Down, Qt.ShiftModifier)
                    } else if (phase === 7) {
                        if (!near(annotations.get(1).nx, 0.55 + unit) || !near(annotations.get(1).ny, 0.2 + 10 / window.currentPage.height))
                            throw new Error("Signature bounds did not nudge")
                        window.nudgeAnnotation(10000, 10000, true)
                        if (item(1).x + item(1).width > paper.width + 0.001 || item(1).y + item(1).height > paper.height + 0.001)
                            throw new Error("Nudge escaped page bounds")
                        var steps = window.undoStack.length
                        keyInput.keyClick(Qt.Key_Right, Qt.ShiftModifier)
                        if (steps !== window.undoStack.length) throw new Error("Blocked nudge created history")
                        keyInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 8) {
                        if (!near(annotations.get(1).nx, 0.55) || !near(annotations.get(1).ny, 0.2)) throw new Error("Signature nudge group did not undo")
                        editor = item(0)
                        keyInput.mouseDoubleClickSequence(editor, 12, 8)
                    } else if (phase === 9) {
                        if (!editor.activeFocus && focusWait++ < 10) return
                        if (!editor.activeFocus) throw new Error("Text editing did not focus")
                        editor.cursorPosition = 0
                        keyInput.keyClick(Qt.Key_Right)
                        keyInput.keyClick(Qt.Key_Right, Qt.ShiftModifier)
                        if (editor.cursorPosition !== 2 || editor.selectedText !== "a" || !near(annotations.get(0).nx, 0.2))
                            throw new Error("Nudging stole text caret/selection keys")
                        keyInput.keyClick(Qt.Key_Escape)
                    } else if (phase === 10) {
                        window.clearCanvasSelection()
                        keyInput.keyClick(Qt.Key_Left)
                    } else if (phase === 11) {
                        if (window.currentIndex !== 0) throw new Error("Unselected reading arrows stopped working")
                        window.jumpToPage(1)
                    } else if (phase === 12) {
                        keyInput.mouseClick(item(0), 12, 8)
                        keyInput.keyClick(Qt.Key_Right)
                        running = false; console.log("KEYS_PASS"); window.close()
                    }
                    phase++
                } catch (error) { running = false; console.error("Error: phase " + phase + ": " + error); Qt.callLater(Qt.quit) }
                finally { stepping = false }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-annotation-keys-') as scratch:
    work = Path(scratch)
    one, source = work/'one.pdf', work/'source.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(one), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(one), '1', str(one), '1', '--', str(source)], check=True)
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
    for stage in ('edit', 'restore'):
        with (work/(stage+'.log')).open('w+') as stream:
            result = subprocess.run(['qs', '-p', str(work/'ui')], env=dict(env, KEYS_STAGE=stage), stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=40)
            stream.seek(0)
            log = stream.read()
        marker = 'KEYS_CLOSED' if stage == 'edit' else 'KEYS_RESTORE_PASS'
        allowed = (0, -15) if stage == 'edit' else (0,)
        if result.returncode not in allowed or marker not in log or 'Error:' in log or 'Binding loop' in log:
            raise SystemExit(f'Exit {result.returncode}:\n'+log)
    assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source changed'
    print('PASS: precise/fast nudges, grouped undo/redo, bounds, text/control focus, reading keys and draft recovery; source unchanged')
