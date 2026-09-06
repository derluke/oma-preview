#!/usr/bin/env python3
"""Actual Find controls, highlights, cancellation and page-edit integration."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
binary = os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/release/oma-preview'))
harness = '''
        TestCase { id: findInput; name: "FindFlow"; when: false }
        Timer {
            interval: 60; running: true; repeat: true
            property int phase: 0
            property bool stepping: false
            property int ticks: 0
            property int oldEpoch: -1
            property string firstKey: ""
            property string secondKey: ""
            function type(keys) {
                findBar.field.forceActiveFocus()
                findInput.keyClick(Qt.Key_A, Qt.ControlModifier)
                for (var key of keys) findInput.keyClick(key)
            }
            onTriggered: {
                if (stepping) return
                stepping = true
                try {
                    if (++ticks > 400) throw new Error("Find flow timed out at " + phase)
                    if (!window.interactionReady || window.restoringView || renderedPage.status !== Image.Ready) return
                    if (phase === 0) {
                        firstKey = pages.get(0).key; secondKey = pages.get(1).key
                        findInput.keyClick(Qt.Key_F, Qt.ControlModifier)
                    } else if (phase === 1) {
                        if (!findBar.opened || !findBar.field.activeFocus || window.currentIndex !== 0) throw new Error("Find did not open in place with focus")
                        type([Qt.Key_A, Qt.Key_L, Qt.Key_P, Qt.Key_H, Qt.Key_A])
                    } else if (phase === 2) {
                        if (searchController.searching) return
                        if (searchController.error || searchController.results.length !== 3 || !findBar.field.activeFocus
                            || !searchController.hit || searchController.hit.pageKey !== firstKey) throw new Error("Initial search/focus failed: " + searchController.error)
                        if (window.dirty || window.undoStack.length) throw new Error("Searching modified the document")
                        findInput.mouseClick(findBar.nextButton)
                    } else if (phase === 3) {
                        if (window.currentIndex !== 1 || searchController.current !== 1 || searchHighlight.hit.pageKey !== secondKey)
                            throw new Error("Next match did not navigate/highlight")
                        var rect = searchController.hit.rects[0]
                        var y = paper.y + rect.y * paper.height - viewport.contentY
                        if (y < 0 || y > viewport.height) throw new Error("Match is outside the viewport")
                        findInput.keyClick(Qt.Key_F3)
                    } else if (phase === 4) {
                        if (searchController.current !== 2 || window.currentIndex !== 1) throw new Error("F3 did not advance within page")
                        findInput.keyClick(Qt.Key_F3, Qt.ShiftModifier)
                        type([Qt.Key_B, Qt.Key_E, Qt.Key_T, Qt.Key_A])
                    } else if (phase === 5) {
                        if (!searchController.job) return
                        oldEpoch = searchController.generation
                        type([Qt.Key_G, Qt.Key_A, Qt.Key_M, Qt.Key_M, Qt.Key_A])
                        searchController.receive(oldEpoch, JSON.stringify({t:"search_done",matches:999,completed:4,truncated:true}))
                    } else if (phase === 6) {
                        if (searchController.searching) return
                        if (searchController.error || searchController.results.length !== 1 || searchController.truncated
                            || searchController.hit.pageIndex !== 2 || window.currentIndex !== 2)
                            throw new Error("Old query replaced current results")
                        findInput.keyClick(Qt.Key_Home, Qt.ControlModifier)
                        if (window.currentIndex !== 2 || !findBar.field.activeFocus) throw new Error("Find field lost caret keys to reading navigation: "
                            + JSON.stringify({page:window.currentIndex,cursor:findBar.field.cursorPosition,focus:findBar.field.activeFocus,control:window.controlHasFocus}))
                        findInput.keyClick(Qt.Key_Home)
                        if (findBar.field.cursorPosition !== 0) throw new Error("Find field lost native Home key")
                        type([Qt.Key_N, Qt.Key_O, Qt.Key_N, Qt.Key_E])
                    } else if (phase === 7) {
                        if (searchController.searching) return
                        if (searchController.error || searchController.results.length || searchController.hit || findBar.nextButton.enabled)
                            throw new Error("No-match state is not clean")
                        type([Qt.Key_A, Qt.Key_L, Qt.Key_P, Qt.Key_H, Qt.Key_A])
                    } else if (phase === 8) {
                        if (!searchController.job) return
                        oldEpoch = searchController.generation
                        findInput.keyClick(Qt.Key_Escape)
                    } else if (phase === 9) {
                        if (findBar.opened || searchController.searching || searchController.job || searchController.results.length)
                            throw new Error("Escape did not cancel/clear Find")
                        searchController.receive(oldEpoch, JSON.stringify({t:"search_done",matches:999,completed:4,truncated:true}))
                        if (searchController.truncated) throw new Error("Closed search accepted late output")
                        findInput.keyClick(Qt.Key_F, Qt.ControlModifier)
                    } else if (phase === 10) {
                        if (searchController.searching) return
                        if (findBar.field.text !== "alpha" || searchController.results.length !== 3) throw new Error("Find did not remember/restart query")
                        window.openPageActions(1)
                    } else if (phase === 11) {
                        if (!pageMenu.visible) return
                        findInput.mouseClick(pageMoveUp)
                    } else if (phase === 12) {
                        if (searchController.searching) return
                        if (pages.get(0).key !== secondKey || searchController.results.length !== 3
                            || searchController.results[0].pageKey !== secondKey || searchController.results[0].pageIndex !== 0)
                            throw new Error("Reordered pages left stale match indices")
                        findInput.mouseClick(findBar.nextButton)
                    } else if (phase === 13) {
                        if (window.currentIndex !== 0 || searchController.hit.pageKey !== secondKey) throw new Error("Reordered result jumped to the wrong page")
                        window.openPageActions(0)
                    } else if (phase === 14) {
                        if (!pageMenu.visible) return
                        findInput.mouseClick(pageRemove)
                    } else if (phase === 15) {
                        if (searchController.searching) return
                        if (searchController.results.length !== 1 || searchController.results[0].pageKey !== firstKey)
                            throw new Error("Removed pages remain searchable")
                        paper.forceActiveFocus(); findInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 16) {
                        if (searchController.searching) return
                        if (pages.count !== 4 || searchController.results.length !== 3) throw new Error("Undo did not refresh search: "
                            + JSON.stringify({pages:pages.count,matches:searchController.results.length,query:searchController.query,
                                error:searchController.error,opened:findBar.opened,undo:window.undoStack.length,redo:window.redoStack.length}))
                        window.width = 640
                        if (Quickshell.env("FIND_LIGHT") === "1") Theme.load('background="#f5f5f5"\\nforeground="#333333"\\naccent="#2450a4"')
                        findBar.field.forceActiveFocus()
                        findInput.keyClick(Qt.Key_End)
                        findInput.keyClick(Qt.Key_Z)
                        findInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    } else if (phase === 17) {
                        if (searchController.searching) return
                        if (pages.count !== 4 || pages.get(0).key !== secondKey || findBar.field.text === "alphaz") throw new Error("Find-field undo modified the PDF or lost native undo: "
                            + JSON.stringify({pages:pages.count,first:pages.get(0).key,expected:secondKey,text:findBar.field.text,
                                focus:findBar.field.activeFocus,undo:window.undoStack.length}))
                        type([Qt.Key_A, Qt.Key_L, Qt.Key_P, Qt.Key_H, Qt.Key_A])
                    } else if (phase === 18) {
                        if (searchController.searching) return
                        findInput.mouseClick(findBar.nextButton)
                    } else if (phase === 19) {
                        searchController.fail(searchController.generation, "Private search failure fixture")
                        findBar.field.forceActiveFocus()
                    } else if (phase === 20) {
                        if (!searchController.error || searchController.results.length || !findBar.opened) throw new Error("Search failure did not keep a usable Find bar")
                        findInput.keyClick(Qt.Key_Return)
                    } else if (phase === 21) {
                        if (searchController.searching) return
                        if (searchController.error || searchController.results.length !== 3) throw new Error("Enter did not retry a failed search")
                    } else if (phase === 22) {
                        var barBounds = window.itemRect(findBar)
                        if (barBounds.x < sidebar.width || barBounds.x + barBounds.width > window.width || findBar.field.width < 100)
                            throw new Error("Find controls do not fit a narrow window")
                        window.draftNoticeVisible = true
                    } else if (phase === 23) {
                        var noticeBounds = window.itemRect(draftNotice)
                        var findBounds = window.itemRect(findBar)
                        if (findBounds.y < noticeBounds.y + noticeBounds.height + 8)
                            throw new Error("Find covers the restored-draft notice")
                        findInput.mouseClick(noticeDismiss)
                    } else if (phase === 24) {
                        if (window.draftNoticeVisible || findBar.y !== 8) throw new Error("Find did not reclaim dismissed notice space")
                        findInput.mouseClick(findBar.closeButton)
                    } else if (phase === 25) {
                        if (findBar.opened || searchController.results.length || searchController.job)
                            throw new Error("Close search button did not clear the session")
                        findInput.keyClick(Qt.Key_F, Qt.ControlModifier)
                    } else if (phase === 26) {
                        if (searchController.searching) return
                        if (!findBar.field.activeFocus || searchController.results.length !== 3)
                            throw new Error("Reopening Find lost query or focus")
                        var destination = Quickshell.env("FIND_CAPTURE")
                        if (destination) {
                            window.contentItem.grabToImage(function(result) { result.saveToFile(destination); console.log("FIND_CAPTURED"); Qt.quit() })
                        } else Qt.quit()
                        running = false; console.log("FIND_FLOW_PASS")
                    }
                    phase++
                } catch (error) { running = false; console.error("Error: phase " + phase + ": " + error); Qt.callLater(Qt.quit) }
                finally { stepping = false }
            }
        }
'''
with tempfile.TemporaryDirectory(prefix='oma-find-flow-') as scratch:
    work = Path(scratch)
    pieces = []
    for index, words in enumerate(('alpha first', 'alpha again alpha', 'gamma middle', 'beta last')):
        svg, pdf = work/f'page-{index}.svg', work/f'page-{index}.pdf'
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="500">'
                       '<rect width="400" height="500" fill="white"/><text x="30" y="200" '
                       'font-family="sans-serif" font-size="22">'+words+'</text></svg>')
        subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(pdf), str(svg)], check=True)
        pieces.extend((str(pdf), '1'))
    source = work/'source.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', *pieces, '--', str(source)], check=True)
    original = hashlib.sha256(source.read_bytes()).digest()
    # Delay only search startup so cancellation is exercised against a real,
    # live process. The normal document service passes through immediately.
    wrapper = work/'backend'
    wrapper.write_text('#!/usr/bin/env python3\nimport os, sys, time\n'
                       'if "--search-worker" in sys.argv: time.sleep(0.3)\n'
                       'os.execv('+repr(binary)+', ['+repr(binary)+'] + sys.argv[1:])\n')
    wrapper.chmod(0o700)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    shell = work/'ui/shell.qml'
    shell.write_text('import QtTest\n'+shell.read_text().replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
               OMA_PREVIEW_BIN=str(wrapper), OMA_PREVIEW_PATHS=json.dumps([str(source)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'),
               FIND_CAPTURE=os.environ.get('OMA_PREVIEW_FIND_CAPTURE', ''))
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    with (work/'test.log').open('w+') as stream:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=45)
        stream.seek(0)
        log = stream.read()
    if result.returncode or 'FIND_FLOW_PASS' not in log or 'Error:' in log or 'Binding loop' in log:
        raise SystemExit(log)
    if env['FIND_CAPTURE']:
        assert 'FIND_CAPTURED' in log and Path(env['FIND_CAPTURE']).is_file()
    assert hashlib.sha256(source.read_bytes()).digest() == original, 'Source changed'
    print('PASS: Find input/buttons/keys, highlights, cancellation/stale replies, failure retry, page move/remove/undo, narrow layout and draft notice; source unchanged')
