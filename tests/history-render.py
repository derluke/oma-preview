#!/usr/bin/env python3
"""Exercise history in the real offscreen UI; no desktop input."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-history-') as scratch:
    work = Path(scratch)
    pdf = work/'sample.pdf'
    subprocess.run(['qpdf', '--empty', str(pdf)], check=True)
    # Two blank pages with distinct sizes, using the project's PDF tooling.
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(work/'one.pdf'),
                    str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    subprocess.run(['qpdf', '--empty', '--pages', str(work/'one.pdf'), '1',
                    str(work/'one.pdf'), '1', '--', str(pdf)], check=True)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    harness = '''
        property real firstMainRasterWidth: -1
        TestCase { id: readingInput; name: "ReadingInput"; when: false }
        Timer {
            interval: 150; running: true; repeat: true
            property int phase: 0
            property real wheelStart: 0
            property real wheelStartX: 0
            property var touch: null
            property real pinchZoom: 1
            property real heldRasterWidth: 0
            property real centreY: 0
            property string preservedContent: ""
            property string preservedDraftKey: ""
            property int exportedPageCount: 0
            onTriggered: {
                try {
                if (window.busy || window.loadingWorkspace) return
                if (renderedPage.status !== Image.Ready || !window.document || !String(window.document.source).length) return
                if (window.currentPage.key !== pages.get(window.currentIndex).key) throw new Error("Stale current page")
                if (phase === 0) {
                    if (pages.count !== 2) return
                    if (window.firstMainRasterWidth !== Math.round(renderedPage.width)) throw new Error("Initial page raster used the wrong layout size: " + window.firstMainRasterWidth + " vs " + renderedPage.width)
                    window.continuous = false
                    window.deletePage()
                } else if (phase === 1) {
                    if (pages.count !== 1) throw new Error("Delete failed")
                    window.travelHistory(false)
                } else if (phase === 2) {
                    if (pages.count !== 2) throw new Error("Undo failed")
                    window.travelHistory(true)
                } else if (phase === 3) {
                    if (pages.count !== 1) throw new Error("Redo failed")
                    window.travelHistory(false)
                } else if (phase === 4) {
                    pageList.currentIndex = 1
                } else if (phase === 5) {
                    window.deletePage()
                } else if (phase === 6) {
                    window.travelHistory(false)
                } else if (phase === 7) {
                    if (pages.count !== 2) throw new Error("Last page restore failed")
                    pageList.currentIndex = 1
                    window.movePage(-1)
                } else if (phase === 8) {
                    window.travelHistory(false)
                } else if (phase === 9) {
                    pageList.currentIndex = 0
                    window.zoom = 2
                } else if (phase === 10) {
                    paper.forceActiveFocus()
                    readingInput.keyClick(Qt.Key_Down)
                    if (viewport.contentY <= 0 || window.currentIndex !== 0) throw new Error("Reading scroll failed")
                    viewport.contentY = viewport.contentHeight - viewport.height
                    readingInput.mouseWheel(paper, paper.width / 2, paper.height - 50, 0, -120)
                } else if (phase === 11) {
                    if (window.currentIndex !== 1 || viewport.contentY !== 0) throw new Error("Wheel next page failed")
                    readingInput.keyClick(Qt.Key_Up)
                } else if (phase === 12) {
                    if (window.currentIndex !== 0 || viewport.contentY < 1) throw new Error("Previous page bottom failed")
                    window.tool = "text"
                    var before = viewport.contentY
                    readingInput.keyClick(Qt.Key_Right)
                    if (viewport.contentY !== before || window.currentIndex !== 0) throw new Error("Reading stole edit input")
                    window.tool = "read"
                    window.turnReadingPage(-1, false)
                    if (window.currentIndex !== 0) throw new Error("Navigated before first page")
                } else if (phase === 13) {
                    window.zoom = 1
                    window.continuous = true
                } else if (phase === 14) {
                    if (viewport.contentHeight <= viewport.height) throw new Error("Continuous layout missing")
                    viewport.contentY = window.pageGeometry(1).top
                } else if (phase === 15) {
                    if (window.currentIndex !== 1) throw new Error("Scroll selection failed")
                    var beforeY = viewport.contentY
                    readingInput.keyClick(Qt.Key_Up)
                    if (viewport.contentY >= beforeY) throw new Error("Continuous key scroll failed")
                    window.turnReadingPage(-1, false)
                } else if (phase === 16) {
                    if (window.currentIndex !== 0 || viewport.contentY !== 0) throw new Error("Continuous page navigation failed")
                } else if (phase === 17) {
                    wheelStart = viewport.contentY
                    readingInput.mouseWheel(paper, 60, 60, 0, -120)
                    if (viewport.contentY <= wheelStart) throw new Error("Wheel step did not move")
                    wheelStart = viewport.contentY
                } else if (phase === 18) {
                    if (viewport.flicking || Math.abs(viewport.contentY - wheelStart) > 0.1) throw new Error("Discrete wheel unexpectedly coasted")
                    viewport.cancelFlick()
                    viewport.contentY = 80
                    readingInput.mouseMove(viewport, 350, 150)
                    pinchZoom = window.zoom
                    heldRasterWidth = renderedPage.sourceSize.width
                    touch = readingInput.touchEvent(viewport)
                    touch.press(0, viewport, 300, 200).press(1, viewport, 400, 200).commit()
                } else if (phase === 19) {
                    touch.move(0, viewport, 275, 200).move(1, viewport, 425, 200).commit()
                } else if (phase === 20) {
                    touch.move(0, viewport, 240, 200).move(1, viewport, 460, 200).commit()
                } else if (phase === 21) {
                    if (window.zoom <= pinchZoom) throw new Error("Pinch zoom did not increase")
                    if (renderedPage.sourceSize.width !== heldRasterWidth) throw new Error("Pinch rerendered before the gesture ended")
                    // QtTest synthesizes a mouse move at the first touch (y=200).
                    if (Math.abs(zoomGesture.screenY - 200) > 2) throw new Error("Pinch must anchor at mouse pointer, got: " + zoomGesture.screenY)
                    var anchor = paper.mapToItem(viewport, zoomGesture.anchorX * paper.width, zoomGesture.anchorY * paper.height)
                    if (Math.abs(anchor.y - zoomGesture.screenY) > 2) throw new Error("Pinch anchor jumped vertically")
                    touch.release(0, viewport, 240, 200).release(1, viewport, 460, 200).commit()
                } else if (phase === 22) {
                    window.height = 320
                    window.sidebarVisible = true
                    pageList.positionViewAtBeginning()
                } else if (phase === 23) {
                    wheelStart = pageList.contentY
                    readingInput.mouseWheel(pageList, 50, 50, 0, -120)
                } else if (phase === 24) {
                    if (pageList.contentY <= wheelStart) throw new Error("Sidebar momentum missing")
                    pageList.cancelFlick()
                    viewport.contentY = 100
                    continuousWheel.stop()
                    var now = Date.now()
                    function wheel(delta, phase, at) {
                        continuousWheel.handleWheel({pixelDelta:Qt.point(0, delta), angleDelta:Qt.point(0,0), phase:phase}, at)
                    }
                    wheel(0, Qt.ScrollBegin, now)
                    for (var i = 1; i <= 6; i++) wheel(-2, Qt.ScrollUpdate, now + i * 10)
                    if (viewport.contentY < 160) throw new Error("Precise scrolling lost travel")
                    wheel(-1, Qt.ScrollUpdate, now + 70)
                    if (continuousWheel.velocity < 500) throw new Error("Finger lift lost momentum estimate")
                    wheel(0, Qt.ScrollEnd, now + 80)
                    wheelStart = viewport.contentY
                } else if (phase === 25) {
                    if (viewport.contentY <= wheelStart + 20) throw new Error("Trackpad did not coast after release")
                    var speed = viewport.verticalVelocity
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollBegin}, now)
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-4), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now + 10)
                    if (continuousWheel.velocity <= speed) throw new Error("Repeated swipe did not add momentum")
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollEnd}, now + 20)
                    continuousWheel.stop()
                } else if (phase === 26) {
                    window.height = 720
                    window.zoom = 1.5
                    pageList.currentIndex = 1
                } else if (phase === 27) {
                    viewport.contentY = paper.y + 100
                    centreY = (viewport.contentY + viewport.height / 2 - paper.y) / paper.height
                    pinchZoom = window.zoom
                    readingInput.mouseClick(zoomInButton)
                    if (window.zoom <= pinchZoom) throw new Error("Zoom button did not activate")
                    if (Math.abs(paper.y + centreY * paper.height - viewport.contentY - viewport.height / 2) > 2) throw new Error("Zoom button lost reading position")
                } else if (phase === 28) {
                    readingInput.keyClick(Qt.Key_Minus, Qt.ControlModifier)
                    if (Math.abs(window.zoom - pinchZoom) > 0.001) throw new Error("Zoom shortcut did not activate")
                    if (Math.abs(paper.y + centreY * paper.height - viewport.contentY - viewport.height / 2) > 2) throw new Error("Zoom shortcut lost reading position")
                } else if (phase === 29) {
                    zoomOutButton.forceActiveFocus(Qt.TabFocusReason)
                    readingInput.keyClick(Qt.Key_Tab)
                    if (!zoomInButton.activeFocus || !zoomInButton.visualFocus) throw new Error("Toolbar tab focus missing")
                    pinchZoom = window.zoom
                    readingInput.keyClick(Qt.Key_Space)
                    if (Math.abs(window.zoom - pinchZoom - 0.15) > 0.001) throw new Error("Space did not activate the focused button exactly once")
                    readingInput.keyClick(Qt.Key_Return)
                    if (Math.abs(window.zoom - pinchZoom - 0.3) > 0.001) throw new Error("Return did not activate the focused button exactly once")
                    readingInput.keyClick(Qt.Key_Backtab)
                    if (!zoomOutButton.activeFocus) throw new Error("Reverse tab navigation failed")
                    readingInput.keyClick(Qt.Key_Delete)
                    if (pages.count !== 2) throw new Error("Toolbar focus allowed page deletion")
                    paper.forceActiveFocus()
                    if (!window.readingKeysEnabled) throw new Error("Toolbar focus left reading shortcuts disabled")
                } else if (phase === 30) {
                    pageList.currentIndex = 1
                } else if (phase === 31) {
                    readingInput.keyClick(Qt.Key_B, Qt.ControlModifier)
                    if (!window.isBookmarked()) throw new Error("Bookmark shortcut failed")
                    pageList.currentIndex = 0
                } else if (phase === 32) {
                    readingInput.mouseClick(bookmarkButton)
                    if (!bookmarkMenu.visible || !window.modalActive) throw new Error("Bookmark menu did not open")
                    var entry = bookmarkMenu.itemAt(2)
                    if (!entry || entry.text !== "Page 2") { console.error("Error: Bookmark navigation entry missing", entry ? entry.text : "null", JSON.stringify(window.bookmarkEntries)); Qt.quit(); return }
                    readingInput.mouseClick(entry)
                } else if (phase === 33) {
                    if (window.currentIndex !== 1 || bookmarkMenu.visible) throw new Error("Bookmark jump failed")
                    readingInput.mouseClick(bookmarkButton)
                    readingInput.mouseClick(bookmarkMenu.itemAt(0))
                    if (window.isBookmarked() || window.bookmarkEntries.length) throw new Error("Bookmark removal failed")
                } else if (phase === 34) {
                    var extent = window.pageLayout.height, offset = viewport.contentY
                    var snapshot = window.contentKey(window.historySnapshot())
                    window.busyText = "Saving PDF…"; window.busy = true
                    if (window.pageLayout.height !== extent || viewport.contentY !== offset || documentSurface.enabled) throw new Error("Busy state disrupted the document view")
                    if (!statusMessage.visible || statusMessage.text !== "Saving PDF…") throw new Error("Save progress is invisible")
                    backend.receive(JSON.stringify({t:"error", id:99999, operation:"view_save", msg:"Simulated reading-state write failure"}))
                    if (!window.busy || documentSurface.enabled) throw new Error("Background failure unlocked the active export")
                    readingInput.keyClick(Qt.Key_Delete)
                    readingInput.keyClick(Qt.Key_Z, Qt.ControlModifier)
                    readingInput.keyClick(Qt.Key_O, Qt.ControlModifier)
                    if (openDialog.visible || window.contentKey(window.historySnapshot()) !== snapshot) throw new Error("Busy state allowed document changes")
                    window.busy = false
                    window.saveTo(EXPORT_PATH)
                } else if (phase === 35) {
                    if (window.dirty || !window.statusText.startsWith("Saved ")) throw new Error("Export did not complete cleanly")
                    window.zoomTo(2)
                    viewport.contentX = 0
                } else if (phase === 36) {
                    wheelStartX = viewport.contentX
                    var previousEvent = continuousWheel.lastAt
                    readingInput.mouseWheel(viewport, 100, 100, -120, 0)
                    if (continuousWheel.lastAt <= previousEvent) throw new Error("Horizontal wheel did not reach the scroll handler")
                } else if (phase === 37) {
                    if (viewport.contentX <= wheelStartX) throw new Error("Horizontal wheel did not pan")
                    continuousWheel.stop()
                    viewport.contentX = 40
                    viewport.contentY = paper.y + 100
                    var beforeY = viewport.contentY, now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollBegin}, now)
                    for (var i = 1; i <= 6; i++)
                        continuousWheel.handleWheel({pixelDelta:Qt.point(-2,-1), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now + i * 10)
                    if (viewport.contentX < 100 || viewport.contentY < beforeY + 30) throw new Error("Diagonal trackpad travel lost an axis")
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollEnd}, now + 70)
                    wheelStartX = viewport.contentX; wheelStart = viewport.contentY
                } else if (phase === 38) {
                    if (viewport.contentX <= wheelStartX + 10 || viewport.contentY <= wheelStart + 5) throw new Error("Diagonal release lost momentum")
                    continuousWheel.stop()
                } else if (phase === 39) {
                    viewport.contentY = 100
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollBegin}, now)
                    for (var i = 1; i <= 5; i++)
                        continuousWheel.handleWheel({pixelDelta:Qt.point(0,-1), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now + i * 32)
                    if (Math.abs(viewport.contentY - 126.5) > 0.1) throw new Error("Gentle swipe speed changed")
                    // A delayed zero-delta release must not erase the estimate.
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollEnd}, now + 300)
                    wheelStart = viewport.contentY
                } else if (phase === 40 || phase === 41) {
                    // Let the actual Flickable coast, not just inspect an estimate.
                } else if (phase === 42) {
                    if (!viewport.flickingVertically || viewport.contentY < wheelStart + 30) throw new Error("Gentle swipe stopped coasting too early")
                    continuousWheel.stop()
                } else if (phase === 43) {
                    viewport.contentY = 300
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollBegin}, now)
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-3), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now + 16)
                    // No ScrollEnd: the idle fallback starts the glide.
                } else if (phase === 44) {
                    if (!viewport.flickingVertically) throw new Error("Missing-end fallback did not coast")
                    var before = viewport.contentY
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,1), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, continuousWheel.lastAt + 100)
                    if (viewport.flickingVertically) throw new Error("Resumed finger movement did not interrupt fallback glide")
                    if (Math.abs(viewport.contentY - (before - 5.3)) > 0.1) throw new Error("Resumed finger movement jumped")
                    if (continuousWheel.velocity >= 0) throw new Error("Reversal retained old momentum")
                    continuousWheel.stop()
                } else if (phase === 45) {
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-1), angleDelta:Qt.point(0,0), phase:Qt.ScrollMomentum}, now)
                    continuousWheel.stop()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-3), angleDelta:Qt.point(0,0), phase:Qt.NoScrollPhase}, now + 16)
                    if (continuousWheel.nativeMomentum) throw new Error("Stopped native gesture leaked into new input")
                    wheelStart = viewport.contentY
                } else if (phase === 46) {
                    if (!viewport.flickingVertically || viewport.contentY <= wheelStart) throw new Error("Phase-less gesture failed to coast after native input")
                    continuousWheel.stop()
                    window.draftNoticeVisible = true
                    draftNotice.width = 260
                } else if (phase === 47) {
                    if (noticeText.lineCount < 2 || noticeText.height > draftNotice.height - 12 || noticeText.x + noticeText.width > noticeDismiss.x)
                        throw new Error("Constrained draft notice does not wrap cleanly")
                    noticeDismiss.forceActiveFocus(Qt.TabFocusReason)
                    if (!noticeDismiss.activeFocus) throw new Error("Draft notice button cannot receive focus")
                    readingInput.keyClick(Qt.Key_Space)
                    if (window.draftNoticeVisible) throw new Error("Draft notice cannot be dismissed by keyboard")
                } else if (phase === 48) {
                    exportedPageCount = pages.count
                    annotations.append({kind:"text", pageKey:window.currentPage.key, nx:0.2, ny:0.2, value:"Keep this edit", size:12, fontFamily:"sans-serif", inkColor:"#111111", nw:0.3, nh:0, strokeData:"[]"})
                    window.markDirty()
                    preservedContent = window.contentKey(window.historySnapshot())
                    preservedDraftKey = window.draftKey
                    window.recents = [MISSING_PATH]
                } else if (phase === 49) {
                    readingInput.mouseClick(recentButton)
                } else if (phase === 50) {
                    if (!recentMenu.visible) throw new Error("Recent files menu did not open")
                    readingInput.mouseClick(recentMenu.itemAt(0))
                } else if (phase === 51) {
                    if (!window.statusError || !window.dirty || window.draftKey !== preservedDraftKey || window.contentKey(window.historySnapshot()) !== preservedContent)
                        throw new Error("Missing recent file disturbed the current draft")
                    window.openPaths([SOURCE_PATH, MISSING_PATH], false)
                } else if (phase === 52) {
                    if (!window.statusError || !window.dirty || window.contentKey(window.historySnapshot()) !== preservedContent)
                        throw new Error("Failed multi-file add partially changed the document")
                    window.replaceWorkspace([EXPORT_PATH])
                } else if (phase === 53) {
                    if (window.currentPage.path !== EXPORT_PATH || window.dirty || pages.count !== exportedPageCount)
                        throw new Error("Valid open failed after a missing recent file")
                    var entries = []
                    for (var i = 0; i < 19; i++) entries.push("/fictional/folder-" + i + "/Same filename.pdf")
                    window.recents = entries.concat([EXPORT_PATH])
                } else if (phase === 54) {
                    readingInput.mouseClick(recentButton)
                } else if (phase === 55) {
                    if (recentMenu.itemAt(0).text !== "Same filename.pdf") throw new Error("Recent menu is not filename-first")
                    readingInput.keyClick(Qt.Key_End)
                } else if (phase === 56) {
                    var entry = recentMenu.itemAt(19)
                    var rect = window.itemRect(entry)
                    if (recentMenu.currentIndex !== 19 || rect.y < toolbar.height || rect.y + rect.height > window.height - 34)
                        throw new Error("Long Recent menu did not reveal the last file")
                    readingInput.keyClick(Qt.Key_Return)
                } else if (phase === 57) {
                    if (recentMenu.visible || window.currentPage.path !== EXPORT_PATH || window.statusError)
                        throw new Error("Keyboard could not open the last recent file")
                    window.zoomTo(2)
                    window.jumpToPage(0)
                } else if (phase === 58) {
                    viewport.contentY = 100
                    viewport.flick(0, -1920)
                    readingInput.keyClick(Qt.Key_Home, Qt.ControlModifier)
                } else if (phase === 59) {
                    if (window.currentIndex !== 0 || viewport.contentY !== 0 || viewport.flickingVertically)
                        throw new Error("Ctrl+Home did not stop at the top of the current first page")
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-3), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now)
                    wheelStart = viewport.contentY
                    readingInput.keyClick(Qt.Key_Down)
                } else if (phase === 60) {
                    if (Math.abs(viewport.contentY - wheelStart - 64) > 1 || viewport.flickingVertically)
                        throw new Error("Pending trackpad momentum resumed after keyboard scrolling")
                    readingInput.keyClick(Qt.Key_End, Qt.ControlModifier)
                } else if (phase === 61) {
                    viewport.contentY = window.pageGeometry(pages.count - 1).top + 100
                    viewport.flick(0, 1920)
                    readingInput.keyClick(Qt.Key_End, Qt.ControlModifier)
                } else if (phase === 62) {
                    var expected = window.pageGeometry(pages.count - 1).top - 24
                    if (window.currentIndex !== pages.count - 1 || Math.abs(viewport.contentY - expected) > 1 || viewport.flickingVertically)
                        throw new Error("Ctrl+End did not settle on the current last page")
                    viewport.contentY = expected + 80
                    readingInput.mouseClick(pageList.itemAtIndex(pages.count - 1), 80, 80)
                } else if (phase === 63) {
                    if (Math.abs(viewport.contentY - window.pageGeometry(pages.count - 1).top + 24) > 1)
                        throw new Error("Clicking the current thumbnail did not return to its page top")
                    window.width = 640
                    window.zoomTo(0.5)
                    window.jumpToPage(0)
                } else if (phase === 64) {
                    readingInput.keyClick(Qt.Key_End, Qt.ControlModifier)
                } else if (phase === 65) {
                    if (viewport.contentY > Math.max(0, viewport.contentHeight - viewport.height) + 1 || viewport.contentY < 0)
                        throw new Error("Zoomed-out page jump overscrolled into blank space")
                    if (window.currentIndex !== pages.count - 1) throw new Error("Clamped jump lost the explicitly selected page")
                    readingInput.keyClick(Qt.Key_Left)
                } else if (phase === 66) {
                    if (window.currentIndex !== 0) throw new Error("Zoomed-out previous-page navigation failed")
                    readingInput.keyClick(Qt.Key_Right)
                } else if (phase === 67) {
                    if (window.currentIndex !== pages.count - 1 || viewport.contentY !== 0)
                        throw new Error("Pages fitting in the viewport could not be selected independently")
                    window.width = 1040
                    window.zoomTo(1)
                } else if (phase === 68) {
                    viewport.contentY = 0
                } else if (phase === 69) {
                    if (window.currentIndex !== 0) throw new Error("Scrolling did not resume automatic page selection after a jump")
                    window.tool = "text"
                    preservedContent = window.contentKey(window.historySnapshot())
                    viewport.flick(0, -3000)
                } else if (phase === 70) {
                    if (!window.fastScrolling || renderedPage.sourceSize.width > 240) throw new Error("Fast scroll did not use a lightweight page raster")
                    readingInput.mouseClick(viewport, 150, 150)
                    if (viewport.flicking || window.editingAnnotation >= 0 || window.contentKey(window.historySnapshot()) !== preservedContent)
                        throw new Error("Tap did not stop cleanly without placing text")
                    wheelStart = viewport.contentY
                } else if (phase === 71) {
                    readingInput.mouseDoubleClickSequence(viewport, 150, 150)
                    if (Math.abs(viewport.contentY - wheelStart) > 0.1 || window.editingAnnotation >= 0 || window.contentKey(window.historySnapshot()) !== preservedContent)
                        throw new Error("Double tap edited or resumed scrolling")
                    window.tool = "read"
                } else if (phase === 72) {
                    if (renderedPage.sourceSize.width < renderedPage.width * 0.88) throw new Error("Stopped page did not regain full sharpness")
                    viewport.contentY = 100
                    viewport.flick(0, -2400)
                } else if (phase === 73) {
                    readingInput.mouseMove(viewport, 150, 150)
                    if (!TrackpadContact.bridge) throw new Error("Native hold bridge missing: " + (TrackpadContact.component ? TrackpadContact.component.errorString() : "no component"))
                    TrackpadContact.bridge.began(2)
                    if (viewport.flicking || !continuousWheel.contactStopped) throw new Error("Finger-down did not pause the actual reader")
                    var stoppedAt = viewport.contentY
                    TrackpadContact.bridge.ended(true)
                    if (viewport.flicking || viewport.contentY !== stoppedAt) throw new Error("Hold cancellation resumed without movement")
                    var now = Date.now()
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollBegin}, now)
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,-2), angleDelta:Qt.point(0,0), phase:Qt.ScrollUpdate}, now + 16)
                    if (continuousWheel.carriedVelocity <= 0) throw new Error("Continuing scroll lost paused velocity")
                    continuousWheel.handleWheel({pixelDelta:Qt.point(0,0), angleDelta:Qt.point(0,0), phase:Qt.ScrollEnd}, now + 17)
                } else if (phase === 74) {
                    if (!viewport.flicking) throw new Error("Continued gesture did not coast")
                    continuousWheel.stop()
                } else {
                    console.log("HISTORY_RENDER_PASS"); Qt.quit()
                }
                phase++
                } catch (error) {
                    console.error("Error: " + error)
                    Qt.quit()
                }
            }
        }
'''
    harness = harness.replace('EXPORT_PATH', json.dumps(str(work/'export.pdf'))).replace('MISSING_PATH', json.dumps(str(work/'missing.pdf'))).replace('SOURCE_PATH', json.dumps(str(pdf)))
    shell = work/'ui/shell.qml'
    shell.write_text(shell.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n').replace('ShellId oma-preview', 'ShellId '+work.name)
                     .replace('if (renderedPage.status === Image.Ready) lastRenderMs = Date.now() - renderStartedAt', 'if (renderedPage.status === Image.Ready) { lastRenderMs = Date.now() - renderStartedAt; if (window.firstMainRasterWidth < 0) window.firstMainRasterWidth = sourceSize.width }')
                     .replace('        Component.onCompleted: {', harness+'\n        Component.onCompleted: {'))
    platform = os.environ.get('OMA_PREVIEW_TEST_PLATFORM', 'offscreen')
    env = dict(os.environ, QT_QPA_PLATFORM=platform,
               QT_QUICK_BACKEND='software' if platform == 'offscreen' else 'rhi',
               QSG_RHI_BACKEND='opengl' if platform == 'offscreen' else 'vulkan',
               OMA_PREVIEW_BIN=os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/debug/oma-preview')),
               OMA_PREVIEW_PATHS=json.dumps([str(pdf)]), OMA_PREVIEW_REVIEW_SPEC='',
               XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'))
    try:
        result = subprocess.run(['qs', '-p', str(work/'ui')], env=env,
                                capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired as error:
        raise SystemExit(str(error.stdout) + str(error.stderr))
    log = result.stdout + result.stderr
    if 'HISTORY_RENDER_PASS' not in log or 'Error:' in log:
        raise SystemExit(log)
    subprocess.run(['qpdf', '--check', str(work/'export.pdf')], check=True, capture_output=True)
    print('PASS: history, reading input, keyboard controls, bookmarks, busy guards and verified export')
