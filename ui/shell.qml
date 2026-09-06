//@ pragma AppId org.omarchy.oma-preview
//@ pragma ShellId oma-preview
//@ pragma NativeTextRendering
//@ pragma DefaultEnv QSG_RHI_BACKEND=vulkan

import Quickshell
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Pdf
import "."

ShellRoot {
    id: shell

    Window {
        id: window
        visible: true
        title: (currentIndex >= 0 ? "Oma Preview — " + fileName(currentPage.path) : "Oma Preview") + (dirty ? " •" : "")
        width: 1040
        height: 720

        readonly property int currentIndex: pages.count > 0 ? Math.min(pageList.currentIndex < 0 ? 0 : pageList.currentIndex, pages.count - 1) : -1
        // ListModel.get objects are invalidated by clear(). Keep a value snapshot,
        // and depend on count so rebuilding history refreshes even the same index.
        readonly property var currentPage: pages.count > 0 && currentIndex >= 0
            ? JSON.parse(JSON.stringify(pages.get(currentIndex)))
            : ({path:"", page:1, width:595, height:842, key:""})
        property string tool: "read"
        property bool sidebarVisible: true
        property bool continuous: true
        property bool followingScroll: false
        property bool zooming: false
        readonly property bool fastScrolling: continuous && !zooming
            && (Math.abs(viewport.verticalVelocity) > 900 || Math.abs(continuousWheel.velocity) > 900)
        onFastScrollingChanged: {
            if (fastScrolling) renderedPage.rerender()
            else if (!zooming) renderDebounce.restart()
        }
        property bool layoutChanging: false
        property bool restoringView: false
        function saveReadingPosition() {
            readingSave.stop()
            if (!draftKey.length || !pages.count || busy || loadingWorkspace || restoringView) return
            backend.saveView(draftKey, {schema:1, path:currentPage.path, page:currentPage.page,
                zoom:zoom, continuous:continuous, sidebar:sidebarVisible,
                x:(viewport.contentX + viewport.width / 2 - paper.x) / paper.width,
                y:(viewport.contentY + viewport.height / 2 - paper.y) / paper.height})
        }
        Timer { id: readingSave; interval: 700; onTriggered: window.saveReadingPosition() }
        onZoomChanged: readingSave.restart()
        onContinuousChanged: readingSave.restart()
        onSidebarVisibleChanged: readingSave.restart()
        PdfDocumentPool { id: readerPool; hostWindow: window }
        property var pdfDocuments: readerPool.documents
        readonly property var pdfReaderStats: readerPool.stats
        function pdfDocumentFor(path) {
            if (!path) return null
            // High-DPI rasterization uses the image plugin's own document.
            // Do not also open a synchronous shared reader just to carry a URL.
            if (window.devicePixelRatio > 1) return {source:fileUri(path), sourceOnly:true}
            return readerPool.get(path, fileUri(path))
        }
        property var document: null
        Binding { target: window; property: "document"; delayed: true; value: window.pdfDocumentFor(window.currentPage.path) }
        property var visibleReadingPages: []
        ListModel { id: readingPages }
        onPageLayoutChanged: visiblePagesTimer.restart()
        Timer { id: visiblePagesTimer; interval: 0; onTriggered: window.updateVisibleReadingPages() }
        function updateVisibleReadingPages() {
            var count = pageMetrics.items.length, next = []
            if (continuous && count) {
                var start = viewport.contentY - 120, end = viewport.contentY + viewport.height + 120
                for (var i = pageAtY(start); i < count && pageGeometry(i).top <= end; i++) next.push(i)
            }
            if (JSON.stringify(next) !== JSON.stringify(visibleReadingPages)) {
                // Preserve overlapping delegates (and their decoded page images).
                // Replacing an array-backed Repeater recreates every visible page.
                for (var row = readingPages.count - 1; row >= 0; row--)
                    if (next.indexOf(readingPages.get(row).pageIndex) < 0) readingPages.remove(row)
                for (var slot = 0; slot < next.length; slot++)
                    if (slot >= readingPages.count || readingPages.get(slot).pageIndex !== next[slot])
                        readingPages.insert(slot, {pageIndex: next[slot]})
                visibleReadingPages = next
            }
        }
        // Source proportions change with the document, not with zoom or window size.
        property int pageMetricsRevision: 0
        Connections {
            target: pages
            function onDataChanged() { window.pageMetricsRevision++; window.pageSnapshotRevision++ }
            function onRowsMoved() { window.pageMetricsRevision++; window.pageSnapshotRevision++ }
            function onModelReset() { window.pageMetricsRevision++; window.pageSnapshotRevision++ }
            function onRowsInserted() { window.pageSnapshotRevision++ }
            function onRowsRemoved() { window.pageSnapshotRevision++ }
        }
        readonly property var pageMetrics: {
            var revision = pageMetricsRevision
            var items = [], sum = 0
            if (loadingWorkspace) return {items:items, total:sum}
            for (var i = 0; i < pages.count; i++) {
                var p = pages.get(i), ratio = p.height / p.width
                items.push({before:sum, ratio:ratio})
                sum += ratio
            }
            return {items:items, total:sum}
        }
        readonly property real readingPageWidth: Math.max(120, Math.min(900, viewport.width - 64)) * zoom
        readonly property var pageLayout: ({
            height: 24 + pageMetrics.items.length * 24 + pageMetrics.total * readingPageWidth,
            width: Math.max(viewport.width, pageMetrics.items.length ? readingPageWidth + 64 : 0)
        })
        function pageGeometry(index) {
            var metric = pageMetrics.items[index]
            if (!metric) return null
            return {top:24 + index * 24 + metric.before * readingPageWidth,
                    width:readingPageWidth, height:metric.ratio * readingPageWidth}
        }
        function pageAtY(position) {
            var lo = 0, hi = pageMetrics.items.length - 1
            if (hi < 0) return -1
            while (lo < hi) {
                var mid = Math.floor((lo + hi) / 2), geometry = pageGeometry(mid)
                if (geometry.top + geometry.height < position) lo = mid + 1; else hi = mid
            }
            return lo
        }
        property real explicitPageY: NaN
        function followReadingScroll() {
            updateVisibleReadingPages()
            if (!continuous || zooming || layoutChanging || restoringView || !readingEnabled || selectedAnnotation >= 0) return
            // When several pages fit, the requested page need not sit under the
            // viewport's reading marker. Keep it selected until scrolling moves.
            if (Math.abs(viewport.contentY - explicitPageY) < 0.5) return
            explicitPageY = NaN
            var middle = viewport.contentY + viewport.height * 0.4
            var lo = pageAtY(middle)
            if (lo >= 0 && lo !== currentIndex) {
                followingScroll = true; pageList.currentIndex = lo; followingScroll = false
                pageList.positionViewAtIndex(lo, ListView.Contain)
            }
        }
        readonly property bool controlHasFocus: !!(activeFocusItem && activeFocusItem.reservesReadingKeys)
        readonly property bool readingEnabled: tool === "read" && editingAnnotation < 0 && !modalActive && !busy && !loadingWorkspace && pages.count > 0
        readonly property bool readingKeysEnabled: readingEnabled && !controlHasFocus
        property double lastWheelPageTurn: 0
        property real wheelEdgeDistance: 0
        function positionReadingPage(index, bottom) {
            var geometry = pageGeometry(index)
            if (!geometry) return
            var maximum = Math.max(0, viewport.contentHeight - viewport.height)
            var target = continuous ? (bottom ? geometry.top + geometry.height - viewport.height : geometry.top - 24) : bottom ? maximum : 0
            viewport.contentY = Math.max(0, Math.min(maximum, target))
            explicitPageY = viewport.contentY
        }
        function turnReadingPage(direction, bottom) {
            if (!readingEnabled) return
            continuousWheel.stop()
            var next = currentIndex + direction
            if (next < 0 || next >= pages.count) return
            pageList.currentIndex = next
            pageList.positionViewAtIndex(next, ListView.Contain)
            Qt.callLater(function() {
                positionReadingPage(next, bottom)
            })
        }
        function scrollReading(distance, wheel) {
            if (!readingEnabled || !distance) return
            if (!wheel) continuousWheel.stop()
            if (wheel && Date.now() - lastWheelPageTurn < 400) return
            var maximum = Math.max(0, viewport.contentHeight - viewport.height)
            if (continuous) {
                viewport.contentY = Math.max(0, Math.min(maximum, viewport.contentY + distance))
                return
            }
            var atEdge = distance > 0 ? viewport.contentY >= maximum - 1 : viewport.contentY <= 1
            if (!atEdge) {
                viewport.contentY = Math.max(0, Math.min(maximum, viewport.contentY + distance))
                wheelEdgeDistance = 0
                return
            }
            if (wheel) {
                if (wheelEdgeDistance * distance < 0) wheelEdgeDistance = 0
                wheelEdgeDistance += distance
                if (Math.abs(wheelEdgeDistance) < 60) return
                wheelEdgeDistance = 0
                lastWheelPageTurn = Date.now()
            }
            turnReadingPage(distance > 0 ? 1 : -1, distance < 0)
        }
        property real zoom: 1.0
        function zoomTo(value) {
            if (!pages.count || busy || loadingWorkspace) return
            var next = Math.max(0.5, Math.min(3, value))
            if (next === zoom) return
            var sx = viewport.width / 2, sy = viewport.height / 2
            var index = currentIndex
            if (continuous) {
                index = pageAtY(viewport.contentY + sy)
            }
            var before = continuous ? pageGeometry(index) : {top:paper.y, width:paper.width, height:paper.height}
            var left = continuous ? (viewport.contentWidth - before.width) / 2 : paper.x
            var ax = (viewport.contentX + sx - left) / before.width
            var ay = (viewport.contentY + sy - before.top) / before.height
            continuousWheel.stop()
            zooming = true
            zoom = next
            var after = continuous ? pageGeometry(index) : {top:paper.y, width:paper.width, height:paper.height}
            left = continuous ? (viewport.contentWidth - after.width) / 2 : paper.x
            viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, left + ax * after.width - sx))
            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, after.top + ay * after.height - sy))
            zooming = false
            renderDebounce.restart()
        }
        property int serial: 0
        property int selectedAnnotation: -1
        onSelectedAnnotationChanged: nudgeBaseline = null
        property int nudgeIndex: -1
        property var nudgeBaseline: null
        property double lastNudgeAt: 0
        property int editingAnnotation: -1
        property int creatingAnnotation: -1
        property string editingOriginalValue: ""
        property real preferredTextSize: 14
        property string preferredTextFont: "sans-serif"
        property string preferredTextColor: "#111111"
        property var signature: []
        property var bookmarks: ({})
        property var recents: []
        property string statusText: ""
        property bool statusError: false
        property bool busy: false
        property string busyText: "Working…"
        readonly property bool interactionReady: !busy && !loadingWorkspace
        property string suggestedOutput: ""
        property bool dirty: false
        property bool loadingWorkspace: false
        property bool baseStartsDirty: false
        property bool draftRestored: false
        property bool draftNoticeVisible: false
        property string draftKey: ""
        property int pendingInspections: 0
        property var inspectionBatch: []
        property string inspectionError: ""
        property bool loadDraftAfterInspect: false
        property bool markDirtyAfterInspect: false
        property bool allowClose: false
        property bool closeAfterExport: false
        property int draftCloseRequest: -1
        property string draftCloseAction: ""
        property int draftOpenRequest: -1
        property var pendingOpenPaths: []
        property bool editingOriginalDirty: false
        property bool applyingLiveReview: false
        property int reviewRevision: 0
        property string reviewError: ""
        property string draftProblem: ""
        readonly property string activeDialog: openDialog.visible ? "open" : addDialog.visible ? "add" : saveDialog.visible ? "save" : signatureDialog.visible ? "signature" : closeDialog.visible ? "close" : draftRecovery.visible ? "draft-recovery" : recentMenu.visible ? "recent" : signatureMenu.visible ? "signature-menu" : pageMenu.visible ? "page-menu" : bookmarkMenu.visible ? "bookmarks" : pageJump.visible ? "go-to-page" : ""
        readonly property bool modalActive: activeDialog.length > 0
        property var undoStack: []
        property var redoStack: []
        property var historyHead: null
        property string savedContent: ""
        readonly property bool hasWorkingDraft: dirty || draftRestored || undoStack.length > 0 || redoStack.length > 0
        property bool draftPersisted: false
        property int draftRevision: 0
        property int latestDraftSaveRequest: -1
        property int latestDraftSaveRevision: -1
        property int pageSnapshotRevision: 0
        property int cachedPageSnapshotRevision: -1
        property var cachedPageSnapshot: []
        property var historyStorage: newHistoryStorage()

        function newHistoryStorage() {
            return {token:{}, records:[], byValue:Object.create(null), byPageKey:Object.create(null), sweepAt:256}
        }

        function historySnapshot() {
            var marks = []
            for (var i = 0; i < annotations.count; i++) marks.push(JSON.parse(JSON.stringify(annotations.get(i))))
            return {pages:pagePayload(), marks:marks, current:currentIndex, output:suggestedOutput}
        }
        function historyLayout(snapshot) {
            var storage = historyStorage, layout = snapshot._folioLayout
            if (layout && layout.owner === storage.token) return layout
            var ids = [], strings = []
            for (var p of snapshot) {
                var record = p._folioRecord
                if (!record || record.owner !== storage.token) {
                    // Canonical field order preserves older clean baselines.
                    var value = JSON.stringify({path:p.path, page:p.page, width:p.width, height:p.height, key:p.key})
                    record = storage.byValue[value]
                    if (!record) {
                        record = {owner:storage.token, id:storage.records.length, json:value}
                        storage.records.push(p); storage.byValue[value] = record
                    }
                    // Non-enumerable metadata stays out of PDF payloads and draft
                    // JSON. Ownership follows the snapshot without weak-key maps.
                    Object.defineProperty(p, "_folioRecord", {value:record, configurable:true})
                }
                ids.push(record.id); strings.push(record.json)
            }
            layout = {owner:storage.token, ids:ids, key:ids.join(","), json:"[" + strings.join(",") + "]"}
            Object.defineProperty(snapshot, "_folioLayout", {value:layout, configurable:true})
            return layout
        }
        function compactHistoryStorage(force) {
            var storage = historyStorage
            if (!force && storage.records.length < storage.sweepAt) return
            var current = pagePayload(), snapshots = undoStack.concat(redoStack)
            if (historyHead) snapshots.push(historyHead)
            var layouts = [current], seen = new Set(), used = new Set()
            for (var snapshot of snapshots) layouts.push(snapshot.pages)
            layouts = layouts.filter(p => {
                if (seen.has(p)) return false
                seen.add(p); return true
            })
            for (var pagesSnapshot of layouts)
                for (var id of historyLayout(pagesSnapshot).ids) used.add(id)
            if (used.size < storage.records.length) {
                // Metadata owns only a generation token, never the old cache.
                // Thus stale snapshots cannot keep discarded records alive.
                historyStorage = newHistoryStorage()
                for (var live of layouts) historyLayout(live)
                for (var page of current) historyStorage.byPageKey[page.key] = page
            }
            historyStorage.sweepAt = historyStorage.records.length + 256
        }
        function pageSnapshotString(snapshot) { return historyLayout(snapshot).json }
        function contentKey(s) { return "[" + pageSnapshotString(s.pages) + "," + JSON.stringify(s.marks) + "," + JSON.stringify(s.output) + "]" }
        function resetHistory() {
            nudgeBaseline = null
            undoStack = []; redoStack = []; historyHead = historySnapshot()
            savedContent = dirty ? "" : contentKey(historyHead)
        }
        function historyBeforeEdit(previousIndex) {
            var index = previousIndex
            if (!Number.isInteger(index)) {
                index = currentIndex
                if (!historyHead.pages[index] || historyHead.pages[index].key !== currentPage.key)
                    index = historyHead.pages.findIndex(p => p.key === currentPage.key)
            }
            if (index < 0 || index >= historyHead.pages.length) index = historyHead.current
            // Reading/navigation isn't an undo step, but undo should return to
            // the page that was edited rather than where this history began.
            return Object.assign({}, historyHead, {current:index})
        }
        function recordHistory(previousIndex, coalesce) {
            if (editingAnnotation >= 0) return
            var next = historySnapshot()
            if (historyHead && contentKey(next) !== contentKey(historyHead)) {
                if (coalesce && undoStack.length) {
                    if (contentKey(next) === contentKey(undoStack[undoStack.length - 1])) undoStack = undoStack.slice(0, -1)
                } else undoStack = undoStack.concat([historyBeforeEdit(previousIndex)]).slice(-100)
                redoStack = []
            }
            historyHead = next
            compactHistoryStorage(false)
        }
        function replacePageSnapshot(target) {
            var current = pagePayload()
            if (pageSnapshotString(target) === pageSnapshotString(current)) return
            var delta = packPageOrder(historyLayout(target).ids, historyLayout(current).ids, 0)
            if (delta.move) pages.move(delta.move[0], delta.move[1], 1)
            else if (!Array.isArray(delta) && delta.splice) {
                var start = delta.splice[0], count = delta.splice[1], inserted = delta.splice[2], records = historyStorage.records
                if (count) pages.remove(start, count)
                for (var i = 0; i < inserted.length; i++) pages.insert(start + i, records[inserted[i]])
            } else {
                pages.clear()
                target.forEach(p => pages.append(p))
            }
        }
        function travelHistory(redo) {
            if (busy || loadingWorkspace || modalActive || editingAnnotation >= 0) return
            var stack = redo ? redoStack : undoStack
            if (!stack.length) return
            var target = stack[stack.length - 1]
            nudgeBaseline = null
            var previousIndex = currentIndex, previousX = viewport.contentX, previousY = viewport.contentY
            continuousWheel.stop()
            if (redo) { undoStack = undoStack.concat([historySnapshot()]); redoStack = stack.slice(0, -1) }
            else { redoStack = redoStack.concat([historySnapshot()]); undoStack = stack.slice(0, -1) }
            loadingWorkspace = true
            selectedAnnotation = -1; tool = "read"
            // Text/signature undo must not rebuild thousands of unchanged pages
            // or invalidate their thumbnail and reading delegates.
            replacePageSnapshot(target.pages)
            cachedPageSnapshot = target.pages; cachedPageSnapshotRevision = pageSnapshotRevision
            annotations.clear()
            target.marks.forEach(function(a) { annotations.append(a) })
            pageList.currentIndex = target.current
            suggestedOutput = target.output
            loadingWorkspace = false
            // Loading temporarily suspends page metrics, which can clamp the
            // Flickable to zero even when undo stays on the same page. Restore
            // its view before the queued reading-marker update can select page 1.
            viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, previousX))
            if (currentIndex === previousIndex) {
                viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, previousY))
                explicitPageY = viewport.contentY
            } else positionReadingPage(target.current, false)
            historyHead = historySnapshot()
            dirty = contentKey(historyHead) !== savedContent
            draftRevision += 1; draftPersisted = false
            // Consecutive undo/redo uses the same autosave debounce as editing.
            // Close and document switching still flush and await the latest state.
            if (draftKey.length) draftTimer.restart()
            paper.forceActiveFocus()
            say(redo ? "Redone" : "Undone", false)
        }

        readonly property bool hasSelectedAnnotation: selectedAnnotation >= 0 && selectedAnnotation < annotations.count
        readonly property string selectedKind: hasSelectedAnnotation ? annotations.get(selectedAnnotation).kind : ""

        function fileName(path) {
            var parts = String(path || "").split("/")
            return parts.length ? parts[parts.length - 1] : ""
        }
        function centreOf(item) {
            if (!item) return ""
            var rect = window.itemRect(item)
            return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
        }
        function itemRect(item) {
            if (!item) return Qt.rect(0, 0, 0, 0)
            var point = item.mapToItem(window.contentItem, 0, 0)
            return Qt.rect(point.x, point.y, item.width, item.height)
        }
        function fromUrl(url) {
            return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
        }
        function fileUri(path) {
            return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
        }
        function say(text, error) {
            statusText = text; statusError = error === true
            statusTimer.stop()
            if (!statusError) statusTimer.restart()
        }
        function openPaths(paths, restoreDraft) {
            paths = (paths || []).filter(p => String(p).length > 0)
            if (!paths.length || !interactionReady) return
            restoringView = false
            readingSave.stop()
            busyText = restoreDraft ? "Opening PDF…" : "Adding pages…"
            busy = true
            pendingInspections = paths.length
            loadingWorkspace = true
            loadDraftAfterInspect = restoreDraft === true
            markDirtyAfterInspect = restoreDraft !== true
            inspectionBatch = []; inspectionError = ""
            for (var i = 0; i < paths.length; i++) {
                inspectionBatch.push({id:backend.inspect(String(paths[i])), path:String(paths[i]), found:null, done:false})
            }
        }
        function replaceWorkspace(paths) {
            paths = (paths || []).filter(p => String(p).length > 0)
            if (!interactionReady || !paths.length) return
            clearCanvasSelection()
            saveReadingPosition()
            draftTimer.stop()
            if (hasWorkingDraft) {
                if (!draftKey.length || !pages.count) { say("Save the current PDF before opening another document.", true); return }
                pendingOpenPaths = paths.slice()
                busyText = "Saving current draft…"
                busy = true
                draftOpenRequest = persistDraft()
                return
            }
            openPaths(paths, true)
        }
        function openAfterDraftSaved(id) {
            if (id !== draftOpenRequest || draftOpenRequest < 0) return
            var paths = pendingOpenPaths
            draftOpenRequest = -1; pendingOpenPaths = []
            busy = false
            openPaths(paths, true)
        }
        function finishInspection(id, found, error) {
            var entry = inspectionBatch.find(p => p.id === id)
            if (!entry || entry.done) return
            entry.done = true; entry.found = found
            if (error && !inspectionError) inspectionError = error
            pendingInspections -= 1
            if (pendingInspections > 0) return
            var batch = inspectionBatch
            inspectionBatch = []
            if (inspectionError) {
                busy = false; loadingWorkspace = false
                say(inspectionError, true)
                return
            }
            // Commit only after every requested PDF has been inspected. A failed
            // recent/open/add must not clear edits or leave a partial page list.
            if (loadDraftAfterInspect) {
                findBar.opened = false; findBar.field.text = ""
                pages.clear(); annotations.clear(); pageList.currentIndex = -1
                dirty = false; draftRestored = false; draftNoticeVisible = false
                draftPersisted = false; latestDraftSaveRequest = -1
                suggestedOutput = ""
                draftKey = JSON.stringify(batch.map(p => p.path))
            }
            var added = 0
            for (var item of batch) {
                backend.addRecent(item.path)
                for (var page of item.found) {
                    serial += 1; added += 1
                    pages.append({path:item.path, page:page.page, width:page.width, height:page.height,
                                  key:item.path + "#" + page.page + "#" + serial})
                }
                backend.getBookmarks(item.path)
            }
            if (pageList.currentIndex < 0 && pages.count) pageList.currentIndex = 0
            busy = false
            if (loadDraftAfterInspect) {
                baseStartsDirty = false
                backend.loadDraft(draftKey)
            } else {
                loadingWorkspace = false
                // The opening document owns this workspace, including added PDFs
                // and pages currently present only in undo/redo history.
                if (markDirtyAfterInspect) markDirty()
                say("Added " + added + (added === 1 ? " page" : " pages"), false)
            }
        }
        function pagePayload() {
            if (cachedPageSnapshotRevision === pageSnapshotRevision) return cachedPageSnapshot
            var out = [], previous = historyStorage.byPageKey
            for (var i = 0; i < pages.count; i++) {
                var p = pages.get(i), key = p.key, path = p.path, page = p.page, width = p.width, height = p.height
                var record = previous[key]
                if (!record || record.path !== path || record.page !== page || record.width !== width || record.height !== height) {
                    record = {path:path, page:page, width:width, height:height, key:key}
                    previous[key] = record
                }
                out.push(record)
            }
            historyLayout(out)
            // These value snapshots are immutable; historical states can share
            // them until the page model changes (including same-count changes).
            cachedPageSnapshot = out; cachedPageSnapshotRevision = pageSnapshotRevision
            return out
        }
        function annotationPayload() {
            var out = []
            for (var i = 0; i < annotations.count; i++) {
                var a = annotations.get(i)
                if (a.kind === "text") out.push({kind:"text", page_key:a.pageKey, x:a.nx, y:a.ny, text:a.value, size:a.size, font:a.fontFamily, color:a.inkColor, width:a.nw})
                else out.push({kind:"signature", page_key:a.pageKey, x:a.nx, y:a.ny, width:a.nw, height:a.nh, strokes:JSON.parse(a.strokeData || "[]")})
            }
            return out
        }
        function sourcePaths() {
            var found = []
            for (var i = 0; i < pages.count; i++) {
                var path = pages.get(i).path
                if (found.indexOf(path) < 0) found.push(path)
            }
            return found
        }
        function refreshDraftKey() { draftKey = JSON.stringify(sourcePaths()) }
        function packPageOrder(order, previous, base) {
            if (!previous || order.length < 8) return order
            var first = 0, oldEnd = previous.length - 1, end = order.length - 1
            while (first <= oldEnd && first <= end && previous[first] === order[first]) first++
            while (oldEnd >= first && end >= first && previous[oldEnd] === order[end]) { oldEnd--; end-- }
            if (previous.length === order.length && end > first) {
                var forward = previous[first] === order[end], backward = previous[end] === order[first]
                for (var i = first; i < end && (forward || backward); i++) {
                    forward = forward && previous[i + 1] === order[i]
                    backward = backward && previous[i] === order[i + 1]
                }
                if (forward || backward) return {base:base, move:forward ? [first, end] : [end, first]}
            }
            if (end - first + 7 < order.length) return {base:base, splice:[first, oldEnd - first + 1, order.slice(first, end + 1)]}
            return order
        }
        function packHistory(current, undo, redo) {
            var layouts = [], byValue = Object.create(null), previous = null
            var records = [], recordIndices = [], storedRecords = historyStorage.records
            function recordIndex(id) {
                var index = recordIndices[id]
                if (index === undefined) { index = records.length; records.push(storedRecords[id]); recordIndices[id] = index }
                return index
            }
            function pack(snapshot) {
                var stored = historyLayout(snapshot.pages), layout = byValue[stored.key]
                if (layout === undefined) {
                    layout = layouts.length
                    var packed = packPageOrder(stored.ids, previous, layout - 1)
                    if (Array.isArray(packed)) packed = packed.map(recordIndex)
                    else if (packed.splice) packed.splice[2] = packed.splice[2].map(recordIndex)
                    layouts.push(packed)
                    byValue[stored.key] = layout; previous = stored.ids
                }
                return {layout:layout, marks:snapshot.marks, current:snapshot.current, output:snapshot.output}
            }
            var packedUndo = undo.map(pack), packedCurrent = pack(current), packedRedo = redo.map(pack)
            return {page_records:records, layouts:layouts, current:packedCurrent, undo:packedUndo, redo:packedRedo, saved_content:savedContent}
        }
        function unpackHistory(history) {
            if (!history || history.layouts === undefined) return history // Original schema-2 drafts.
            if (!Array.isArray(history.layouts) || !history.layouts.length || history.layouts.length > 201
                || !Array.isArray(history.undo) || !Array.isArray(history.redo)
                || history.undo.length > 100 || history.redo.length > 100) return null
            var layouts = history.layouts
            if (history.page_records !== undefined) {
                if (!Array.isArray(history.page_records)) return null
                layouts = []
                for (var packed of history.layouts) {
                    var layout = []
                    if (Array.isArray(packed)) {
                        for (var index of packed) {
                            if (!Number.isInteger(index) || index < 0 || index >= history.page_records.length) return null
                            layout.push(history.page_records[index])
                        }
                    } else {
                        if (!packed || !Number.isInteger(packed.base) || packed.base < 0 || packed.base >= layouts.length
                            || (packed.move !== undefined) === (packed.splice !== undefined)) return null
                        layout = layouts[packed.base].slice()
                        if (Array.isArray(packed.move) && packed.move.length === 2) {
                            var from = packed.move[0], to = packed.move[1]
                            if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < 0 || from >= layout.length || to >= layout.length) return null
                            layout.splice(to, 0, layout.splice(from, 1)[0])
                        } else if (Array.isArray(packed.splice) && packed.splice.length === 3) {
                            var start = packed.splice[0], count = packed.splice[1], inserted = packed.splice[2], added = []
                            if (!Number.isInteger(start) || !Number.isInteger(count) || start < 0 || start > layout.length || count < 0 || start + count > layout.length || !Array.isArray(inserted)) return null
                            for (var ref of inserted) {
                                if (!Number.isInteger(ref) || ref < 0 || ref >= history.page_records.length) return null
                                added.push(history.page_records[ref])
                            }
                            layout = layout.slice(0, start).concat(added, layout.slice(start + count))
                        } else return null
                    }
                    layouts.push(layout)
                }
            }
            function unpack(snapshot) {
                if (!snapshot || !Number.isInteger(snapshot.layout) || snapshot.layout < 0 || snapshot.layout >= history.layouts.length) return null
                return {pages:layouts[snapshot.layout], marks:snapshot.marks, current:snapshot.current, output:snapshot.output}
            }
            return {current:unpack(history.current), undo:history.undo.map(unpack), redo:history.redo.map(unpack), saved_content:history.saved_content}
        }
        function draftPayload() {
            var current = historySnapshot()
            // Autosaving while typing captures the pending edit as one undo step,
            // without committing or disturbing the live editor's own undo history.
            var pendingEdit = editingAnnotation >= 0 && historyHead && contentKey(current) !== contentKey(historyHead)
            return {schema:2, pages:pagePayload(), annotations:annotationPayload(), current_page:currentIndex,
                    zoom:zoom, serial:serial, suggested_output:suggestedOutput, saved_at:new Date().toISOString(),
                    history:packHistory(current, pendingEdit ? undoStack.concat([historyBeforeEdit()]).slice(-100) : undoStack,
                                        pendingEdit ? [] : redoStack)}
        }
        function markDirty(previousIndex, coalesce) {
            if (loadingWorkspace) return
            nudgeBaseline = null
            draftRevision += 1; draftPersisted = false
            recordHistory(previousIndex, coalesce)
            dirty = editingAnnotation >= 0 || !historyHead || contentKey(historyHead) !== savedContent
            if (draftKey.length) draftTimer.restart()
        }
        function saveDraftNow() {
            draftTimer.stop()
            if (hasWorkingDraft && draftKey.length && pages.count) persistDraft()
        }
        function persistDraft() {
            latestDraftSaveRevision = draftRevision
            latestDraftSaveRequest = backend.saveDraft(draftKey, draftPayload())
            return latestDraftSaveRequest
        }
        function validHistorySnapshot(snapshot, layoutKeys) {
            if (!snapshot || !Array.isArray(snapshot.pages) || !snapshot.pages.length || !Array.isArray(snapshot.marks)
                || typeof snapshot.output !== "string" || !Number.isInteger(snapshot.current)
                || snapshot.current < 0 || snapshot.current >= snapshot.pages.length) return false
            var keys = layoutKeys.get(snapshot.pages)
            if (!keys) {
                keys = Object.create(null)
                for (var p of snapshot.pages) {
                    if (!p || typeof p.path !== "string" || !p.path.length || typeof p.key !== "string" || keys[p.key]
                        || !Number.isInteger(p.page) || p.page < 1 || !(p.width > 0) || !(p.height > 0)) return false
                    keys[p.key] = true
                }
                layoutKeys.set(snapshot.pages, keys)
            }
            for (var a of snapshot.marks) {
                if (!a || !keys[a.pageKey] || (a.kind !== "text" && a.kind !== "signature")
                    || typeof a.value !== "string" || typeof a.fontFamily !== "string" || typeof a.inkColor !== "string"
                    || typeof a.strokeData !== "string") return false
                for (var role of ["nx", "ny", "nw", "nh", "size"])
                    if (typeof a[role] !== "number" || !isFinite(a[role])) return false
                try { if (!Array.isArray(JSON.parse(a.strokeData))) return false } catch (error) { return false }
            }
            return true
        }
        function restoreHistory(history) {
            history = unpackHistory(history)
            var layoutKeys = new Map()
            if (!history || !validHistorySnapshot(history.current, layoutKeys) || !Array.isArray(history.undo)
                || !Array.isArray(history.redo) || history.undo.length > 100 || history.redo.length > 100
                || typeof history.saved_content !== "string"
                || !history.undo.every(s => validHistorySnapshot(s, layoutKeys)) || !history.redo.every(s => validHistorySnapshot(s, layoutKeys))) return false
            loadingWorkspace = true
            replacePageSnapshot(history.current.pages)
            annotations.clear()
            cachedPageSnapshot = history.current.pages; cachedPageSnapshotRevision = pageSnapshotRevision
            history.current.marks.forEach(a => annotations.append(a))
            pageList.currentIndex = history.current.current
            suggestedOutput = history.current.output
            undoStack = history.undo; redoStack = history.redo
            historyHead = historySnapshot(); savedContent = history.saved_content
            dirty = contentKey(historyHead) !== savedContent
            loadingWorkspace = false
            return true
        }
        function restoreDraft(draft) {
            loadingWorkspace = true
            pages.clear(); annotations.clear()
            for (var i = 0; i < draft.pages.length; i++) pages.append(draft.pages[i])
            // Newly added pages must not reuse keys from a restored history.
            serial = Math.max(serial, Number(draft.serial) || 0)
            for (var p of draft.pages) serial = Math.max(serial, Number(String(p.key).split("#").pop()) || 0)
            for (var j = 0; j < draft.annotations.length; j++) {
                var a = draft.annotations[j]
                if (a.kind === "text") annotations.append({kind:"text", pageKey:a.page_key, nx:a.x, ny:a.y, value:a.text, size:a.size, fontFamily:a.font || "sans-serif", inkColor:a.color || "#111111", nw:a.width || 0, nh:0, strokeData:"[]"})
                else annotations.append({kind:"signature", pageKey:a.page_key, nx:a.x, ny:a.y, value:"", size:0, fontFamily:"sans-serif", inkColor:"#111111", nw:a.width, nh:a.height, strokeData:JSON.stringify(a.strokes || [])})
            }
            pageList.currentIndex = Math.max(0, Math.min(pages.count - 1, draft.current_page || 0))
            zoom = draft.zoom || 1.0
            suggestedOutput = draft.suggested_output || suggestedOutput
            selectedAnnotation = -1; editingAnnotation = -1
            loadingWorkspace = false; dirty = true; draftRestored = true; draftNoticeVisible = true
            draftPersisted = true
            for (var k = 0; k < sourcePaths().length; k++) backend.getBookmarks(sourcePaths()[k])
            say("Draft restored — continue where you left off", false)
        }
        function closeWindow() { allowClose = true; window.close() }
        function finishWithDraft(keep) {
            if (!interactionReady) return
            clearCanvasSelection()
            draftTimer.stop()
            if (!hasWorkingDraft) { closeWindow(); return }
            if (!draftKey.length || !pages.count) { say("Could not locate this draft. Save a PDF before closing.", true); return }
            draftCloseAction = keep ? "keep" : "discard"
            busyText = keep ? "Saving draft…" : "Discarding draft…"
            busy = true
            draftCloseRequest = keep ? persistDraft() : backend.deleteDraft(draftKey)
        }
        function draftCloseConfirmed(id, action) {
            if (id !== draftCloseRequest || draftCloseAction !== action) return
            draftCloseRequest = -1; draftCloseAction = ""
            busy = false
            closeWindow()
        }
        function changeSelectedSize(direction) {
            if (!hasSelectedAnnotation) return
            var a = annotations.get(selectedAnnotation)
            if (a.kind === "text") {
                preferredTextSize = Math.max(6, Math.min(72, a.size + direction * 2))
                annotations.setProperty(selectedAnnotation, "size", preferredTextSize)
            } else {
                var factor = direction > 0 ? 1.12 : 1 / 1.12
                annotations.setProperty(selectedAnnotation, "nw", Math.max(0.06, Math.min(1 - a.nx, a.nw * factor)))
                annotations.setProperty(selectedAnnotation, "nh", Math.max(0.025, Math.min(1 - a.ny, a.nh * factor)))
            }
            markDirty()
        }
        function cycleSelectedFont() {
            if (selectedKind !== "text") return
            var fonts = ["sans-serif", "serif", "monospace"]
            var current = annotations.get(selectedAnnotation).fontFamily
            preferredTextFont = fonts[(fonts.indexOf(current) + 1) % fonts.length]
            annotations.setProperty(selectedAnnotation, "fontFamily", preferredTextFont)
            markDirty()
        }
        function selectedFontLabel() {
            if (selectedKind !== "text") return ""
            var family = annotations.get(selectedAnnotation).fontFamily
            return family === "serif" ? "Serif" : family === "monospace" ? "Mono" : "Sans"
        }
        function setSelectedColor(value) {
            if (selectedKind === "text") {
                preferredTextColor = value
                annotations.setProperty(selectedAnnotation, "inkColor", value)
                markDirty()
            }
        }
        function selectedColorIs(value) {
            return selectedKind === "text" && annotations.get(selectedAnnotation).inkColor === value
        }
        function beginTextEdit(index, isNew) {
            if (index < 0 || index >= annotations.count || annotations.get(index).kind !== "text") return
            if (editingAnnotation >= 0 && editingAnnotation !== index) finishTextEdit(editingAnnotation, false, false)
            selectedAnnotation = index
            editingOriginalValue = annotations.get(index).value
            editingOriginalDirty = dirty
            creatingAnnotation = isNew ? index : -1
            editingAnnotation = index
            tool = "text"
            annotationIndex.flush()
            Qt.callLater(function() {
                var loader = annotationRepeater.itemForAnnotation(index)
                if (loader && loader.item) loader.item.forceActiveFocus()
            })
        }
        function finishTextEdit(index, cancelled, deselect) {
            if (index !== editingAnnotation || index < 0 || index >= annotations.count) return
            var wasNew = creatingAnnotation === index
            var value = annotations.get(index).value
            editingAnnotation = -1
            creatingAnnotation = -1
            tool = "read"
            if (cancelled && !wasNew) annotations.setProperty(index, "value", editingOriginalValue)
            if ((wasNew && cancelled) || (!cancelled && String(value).trim().length === 0)) {
                annotations.remove(index)
                selectedAnnotation = -1
                say(cancelled ? "Text cancelled" : "Empty text removed", false)
            } else {
                selectedAnnotation = deselect ? -1 : index
                say(cancelled ? "Changes discarded" : "Text ready — drag it to move", false)
            }
            if (cancelled) {
                draftTimer.stop()
                draftRevision += 1; draftPersisted = false
                dirty = editingOriginalDirty
                if (!hasWorkingDraft && draftKey.length) backend.deleteDraft(draftKey)
                else saveDraftNow()
            } else markDirty()
            paper.forceActiveFocus()
        }
        function clearCanvasSelection() {
            if (editingAnnotation >= 0) finishTextEdit(editingAnnotation, false, true)
            else selectedAnnotation = -1
            tool = "read"
            paper.forceActiveFocus()
        }
        function cancelCurrentAction() {
            if (editingAnnotation >= 0) finishTextEdit(editingAnnotation, true, false)
            else { tool = "read"; selectedAnnotation = -1; paper.forceActiveFocus() }
        }
        function deleteSelectedAnnotation() {
            if (!hasSelectedAnnotation || editingAnnotation >= 0) return
            annotations.remove(selectedAnnotation)
            selectedAnnotation = -1
            markDirty()
            say("Annotation deleted", false)
        }
        readonly property bool annotationKeysEnabled: interactionReady && !modalActive && !controlHasFocus
            && hasSelectedAnnotation && editingAnnotation < 0
        function nudgeAnnotation(dx, dy, larger) {
            if (!annotationKeysEnabled) return
            var index = selectedAnnotation, mark = annotations.get(index)
            var loader = annotationRepeater.itemForAnnotation(index)
            if (mark.pageKey !== currentPage.key || !loader || !loader.item) return
            var step = larger ? 10 : 1
            var x = Math.max(0, Math.min(Math.max(0, 1 - loader.item.width / paper.width), mark.nx + dx * step / currentPage.width))
            var y = Math.max(0, Math.min(Math.max(0, 1 - loader.item.height / paper.height), mark.ny + dy * step / currentPage.height))
            if (Math.abs(x - mark.nx) < 0.0000001 && Math.abs(y - mark.ny) < 0.0000001) return
            var now = Date.now()
            var merge = nudgeIndex === index && now - lastNudgeAt < 600 && nudgeBaseline
                && undoStack.length && undoStack[undoStack.length - 1] === nudgeBaseline
            var baseline = merge ? nudgeBaseline : null
            if (baseline) {
                var original = baseline.marks[index]
                if (Math.abs(x - original.nx) < 0.0000001) x = original.nx
                if (Math.abs(y - original.ny) < 0.0000001) y = original.ny
            }
            continuousWheel.stop()
            annotations.setProperty(index, "nx", x)
            annotations.setProperty(index, "ny", y)
            markDirty(undefined, !!merge)
            nudgeIndex = index; lastNudgeAt = now
            // Returning to the starting point removes this gesture's undo step.
            nudgeBaseline = merge ? (undoStack.indexOf(baseline) >= 0 ? baseline : null)
                                  : undoStack[undoStack.length - 1]
        }
        function saveTo(path) {
            if (!interactionReady) return
            clearCanvasSelection()
            if (!path.toLowerCase().endsWith(".pdf")) path += ".pdf"
            busyText = "Saving PDF…"
            busy = true
            backend.exportPdf(path, pagePayload(), annotationPayload())
        }
        function applyLiveReview(path, allowSavedSignature) {
            if (busy || modalActive || editingAnnotation >= 0) return false
            saveDraftNow()
            reviewError = ""
            applyingLiveReview = true
            draftNoticeVisible = false
            loadingWorkspace = true
            busyText = "Loading proposed edits…"
            busy = true
            draftTimer.stop()
            backend.loadSpec(path, allowSavedSignature === true)
            return true
        }
        function isBookmarked() {
            if (currentIndex < 0) return false
            var list = bookmarks[currentPage.path] || []
            return list.indexOf(currentPage.page) >= 0
        }
        readonly property var bookmarkEntries: {
            if (busy || loadingWorkspace) return []
            var revision = pageMetricsRevision, entries = [], paths = sourcePaths()
            for (var i = 0; i < pages.count; i++) {
                var page = pages.get(i)
                if ((bookmarks[page.path] || []).indexOf(page.page) >= 0)
                    entries.push({index:i, label:"Page " + (i + 1) + (paths.length > 1 ? " — " + fileName(page.path) : "")})
            }
            return entries
        }
        function jumpToPage(index) {
            if (index < 0 || index >= pages.count) return
            clearCanvasSelection()
            continuousWheel.stop()
            pageList.currentIndex = index
            pageList.positionViewAtIndex(index, ListView.Contain)
            Qt.callLater(function() {
                positionReadingPage(index, false)
                paper.forceActiveFocus()
            })
        }
        function openFind() {
            if (!interactionReady || modalActive || !pages.count) return
            clearCanvasSelection(); continuousWheel.stop(); findBar.open()
        }
        function showSearchMatch(match) {
            if (!match || !interactionReady || modalActive || editingAnnotation >= 0
                || match.pageIndex >= pages.count || pages.get(match.pageIndex).key !== match.pageKey) return
            selectedAnnotation = -1; continuousWheel.stop()
            followingScroll = true; pageList.currentIndex = match.pageIndex; followingScroll = false
            pageList.positionViewAtIndex(match.pageIndex, ListView.Contain)
            var epoch = searchController.generation
            Qt.callLater(function() {
                if (epoch !== searchController.generation || !searchController.hit || searchController.hit.id !== match.id
                    || !window.interactionReady || window.modalActive || window.editingAnnotation >= 0) return
                var rect = match.rects[0]
                if (!rect) return
                var y = paper.y + rect.y * paper.height - Math.max(findBar.y + findBar.height + 16, viewport.height * 0.35)
                var x = paper.x + (rect.x + rect.width / 2) * paper.width - viewport.width / 2
                viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, y))
                viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, x))
                window.explicitPageY = viewport.contentY
            })
        }
        function openPageActions(index) {
            if (!interactionReady || modalActive || index < 0 || index >= pages.count) return
            if (index !== currentIndex) jumpToPage(index)
            else { clearCanvasSelection(); continuousWheel.stop() }
            // Let page navigation finish before giving the menu keyboard focus.
            Qt.callLater(function() {
                if (!window.interactionReady || window.modalActive || window.currentIndex !== index) return
                var row = window.sidebarVisible ? pageList.itemAtIndex(index) : null
                var point = row ? row.actionsButton.mapToItem(window.contentItem, 0, row.actionsButton.height)
                                : Qt.point(workspace.x + 12, toolbar.height + 12)
                pageMenu.x = Math.max(8, Math.min(point.x, window.width - pageMenu.implicitWidth - 8))
                pageMenu.y = Math.max(8, Math.min(point.y, window.height - pageMenu.implicitHeight - 8))
                pageMenu.open()
            })
        }
        function toggleBookmark() {
            if (currentIndex < 0) return
            var all = Object.assign({}, bookmarks)
            var list = (all[currentPage.path] || []).slice()
            var at = list.indexOf(currentPage.page)
            if (at >= 0) list.splice(at, 1); else list.push(currentPage.page)
            list.sort(function(a,b){ return a-b })
            all[currentPage.path] = list; bookmarks = all
            backend.saveBookmarks(currentPage.path, list)
        }
        function movePage(delta) {
            if (currentIndex < 0) return
            var to = Math.max(0, Math.min(pages.count - 1, currentIndex + delta))
            if (to === currentIndex) return
            pages.move(currentIndex, to, 1); pageList.currentIndex = to; markDirty()
        }
        function deletePage() {
            if (selectedAnnotation >= 0) { deleteSelectedAnnotation(); return }
            if (currentIndex < 0 || pages.count <= 1) return
            var old = currentIndex
            var key = currentPage.key
            for (var i = annotations.count - 1; i >= 0; i--) {
                if (annotations.get(i).pageKey === key) annotations.remove(i)
            }
            pages.remove(old); pageList.currentIndex = Math.min(old, pages.count - 1); markDirty(old)
        }

        onClosing: close => {
            if (busy || loadingWorkspace) { close.accepted = false; return }
            searchController.cancel()
            saveReadingPosition()
            if (allowClose) return
            clearCanvasSelection()
            if (!hasWorkingDraft) return
            close.accepted = false
            finishWithDraft(true)
        }
        Connections { target: Quickshell; function onLastWindowClosed() { backend.quit() } }
        Connections { target: backend
            function onDraftSaved(id) {
                if (id === window.latestDraftSaveRequest && window.latestDraftSaveRevision === window.draftRevision) window.draftPersisted = true
                window.draftCloseConfirmed(id, "keep"); window.openAfterDraftSaved(id)
            }
            function onDraftDeleted(id) { window.draftCloseConfirmed(id, "discard") }
            function onRecentsLoaded(paths) { window.recents = paths }
            function onQuitReady() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
            function onInspected(id, path, found) {
                window.finishInspection(id, found, "")
            }
            function onExported(id, path) {
                window.draftRestored = window.hasWorkingDraft
                window.busy = false; window.dirty = false
                window.savedContent = window.contentKey(window.historySnapshot())
                window.draftRevision += 1; window.draftPersisted = false
                window.saveDraftNow()
                window.say("Saved " + window.fileName(path), false)
                if (window.closeAfterExport) window.finishWithDraft(true)
            }
            function onSignatureLoaded(strokes) { window.signature = strokes }
            function onSignatureSaved() { window.say("Signature saved for next time", false) }
            function onBookmarksLoaded(path, found) {
                var all = Object.assign({}, window.bookmarks); all[path] = found; window.bookmarks = all
            }
            function onReviewLoaded(output, proposedPages, proposedAnnotations) {
                var previousIndex = window.currentIndex
                window.selectedAnnotation = -1
                window.editingAnnotation = -1
                window.creatingAnnotation = -1
                window.tool = "read"
                pages.clear(); annotations.clear(); window.suggestedOutput = output
                for (var i = 0; i < proposedPages.length; i++) {
                    var p = proposedPages[i]
                    pages.append({path:p.path, page:p.page, width:p.width, height:p.height, key:p.key})
                }
                var paths = window.sourcePaths()
                for (var k = 0; k < paths.length; k++) {
                    backend.getBookmarks(paths[k])
                    backend.addRecent(paths[k])
                }
                for (var j = 0; j < proposedAnnotations.length; j++) {
                    var a = proposedAnnotations[j]
                    if (a.kind === "text") {
                        annotations.append({kind:"text", pageKey:a.page_key, nx:a.x, ny:a.y, value:a.text, size:a.size, fontFamily:a.font || "sans-serif", inkColor:a.color || "#111111", nw:a.width || 0, nh:0, strokeData:"[]"})
                    } else if (a.kind === "signature") {
                        annotations.append({kind:"signature", pageKey:a.page_key, nx:a.x, ny:a.y, value:"", size:0, fontFamily:"sans-serif", inkColor:"#111111", nw:a.width, nh:a.height, strokeData:JSON.stringify(a.strokes || [])})
                    }
                }
                pageList.currentIndex = pages.count ? (window.applyingLiveReview ? Math.max(0, Math.min(previousIndex, pages.count - 1)) : 0) : -1
                window.busy = false
                if (!window.applyingLiveReview) window.refreshDraftKey()
                window.baseStartsDirty = true
                if (window.applyingLiveReview) {
                    window.applyingLiveReview = false
                    window.reviewRevision += 1
                    window.baseStartsDirty = false
                    window.loadingWorkspace = false
                    window.markDirty()
                    window.say("Agent updates applied — review and adjust before saving", false)
                } else backend.loadDraft(window.draftKey)
            }
            function onDraftLoaded(draft, problem) {
                window.historyStorage = window.newHistoryStorage()
                window.cachedPageSnapshotRevision = -1
                if (problem) {
                    draftTimer.stop()
                    window.loadingWorkspace = false; window.busy = false
                    window.dirty = false; window.draftRestored = false; window.draftPersisted = false
                    window.baseStartsDirty = false; window.resetHistory()
                    window.draftProblem = problem
                    window.say("Draft not restored — the saved draft is unchanged", true)
                    draftRecovery.open()
                    return
                }
                window.draftProblem = ""; draftRecovery.close()
                var restoreReading = !window.baseStartsDirty
                var restored = draft && (draft.schema === 1 || draft.schema === 2) && draft.pages && draft.annotations
                if (restored) window.restoreDraft(draft)
                else {
                    window.loadingWorkspace = false
                    if (window.baseStartsDirty) window.markDirty(); else window.dirty = false
                    window.say(window.baseStartsDirty ? "Agent proposal loaded — review and adjust before saving" : "Ready", false)
                }
                window.baseStartsDirty = false
                if (!restored || draft.schema !== 2) window.resetHistory()
                else if (!window.restoreHistory(draft.history)) {
                    window.resetHistory()
                    window.say("Edits restored, but the saved undo history could not be read.", true)
                }
                if (restoreReading) {
                    window.restoringView = true
                    backend.loadView(window.draftKey)
                }
            }
            function onViewLoaded(key, view) {
                if (key !== window.draftKey) return
                if (!view || view.schema !== 1) { window.restoringView = false; return }
                var index = -1
                for (var i = 0; i < pages.count; i++)
                    if (pages.get(i).path === view.path && pages.get(i).page === view.page) { index = i; break }
                if (index < 0) { window.restoringView = false; return }
                window.zoom = Math.max(0.5, Math.min(3, Number(view.zoom) || 1))
                window.continuous = view.continuous !== false
                window.sidebarVisible = view.sidebar !== false
                pageList.currentIndex = index
                // Let sidebar resizing and selected-page layout settle before positioning.
                Qt.callLater(function() { Qt.callLater(function() {
                    if (key !== window.draftKey) return
                    var x = Number(view.x), y = Number(view.y)
                    if (!isFinite(x)) x = 0.5
                    if (!isFinite(y)) y = 0.5
                    viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, paper.x + x * paper.width - viewport.width / 2))
                    viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, paper.y + y * paper.height - viewport.height / 2))
                    window.restoringView = false
                }) })
            }
            function onFailed(message, operation, requestId) {
                if (requestId === window.draftOpenRequest && window.draftOpenRequest >= 0) {
                    window.draftOpenRequest = -1; window.pendingOpenPaths = []
                    window.busy = false
                    window.say("Could not save the current draft: " + message + " Your document is still open.", true)
                    return
                }
                if (requestId === window.draftCloseRequest && window.draftCloseRequest >= 0) {
                    window.draftCloseRequest = -1; window.draftCloseAction = ""
                    window.busy = false; window.closeAfterExport = false
                    window.say("Could not finish closing: " + message + " Your edits are still open.", true)
                    return
                }
                if (operation === "inspect") { window.finishInspection(requestId, null, message); return }
                var background = ["view_save", "draft_save", "draft_delete", "bookmarks_save", "bookmarks_get", "recent_add", "recents_get", "recents_clear", "signature_get", "signature_save"].indexOf(operation) >= 0
                if (!background) {
                    window.draftOpenRequest = -1; window.pendingOpenPaths = []
                    window.draftCloseRequest = -1; window.draftCloseAction = ""
                    window.inspectionBatch = []; window.pendingInspections = 0
                    if (window.applyingLiveReview) window.reviewError = message
                    window.busy = false; window.loadingWorkspace = false; window.restoringView = false
                    window.applyingLiveReview = false; window.closeAfterExport = false
                }
                window.say(message, true)
            }
        }

        Backend { id: backend }
        ListModel { id: pages }
        ListModel { id: annotations }
        AnnotationIndex { id: annotationIndex; sourceModel: annotations }
        SearchController {
            id: searchController
            previewWindow: window
            active: findBar.opened
            mayNavigate: findBar.hasFocus && window.interactionReady && !window.modalActive && window.editingAnnotation < 0
            onChosen: match => window.showSearchMatch(match)
        }

        Rectangle {
            id: documentSurface
            anchors.fill: parent
            enabled: window.interactionReady
            color: Theme.background

            FindBar {
                id: findBar
                parent: workspace
                z: 50
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.top: parent.top; anchors.topMargin: draftNotice.visible ? draftNotice.y + draftNotice.height + 8 : 8
                width: Math.min(implicitWidth, parent.width - 24); height: implicitHeight
                search: searchController
                onDismissed: paper.forceActiveFocus()
            }

            Rectangle {
                id: toolbar
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: toolbarGroups.implicitHeight + 58
                color: Theme.chrome
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.hairline }

                Row {
                    id: fileControls
                    anchors.left: parent.left; anchors.leftMargin: 12; y: 6
                    spacing: 4
                    ToolButton { label: "Open"; onActivated: openDialog.open() }
                    ToolButton { id: recentButton; label: "Recent"; onActivated: recentMenu.open() }
                }
                Text {
                    id: documentTitle
                    anchors.left: fileControls.right; anchors.leftMargin: 20
                    anchors.right: saveButton.left; anchors.rightMargin: 20
                    anchors.verticalCenter: fileControls.verticalCenter
                    elide: Text.ElideMiddle
                    text: pages.count ? window.fileName(window.currentPage.path) : "Oma Preview"
                    color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                ToolButton {
                    id: saveButton
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 6
                    label: "Save as…"; chosen: true
                    enabled: pages.count > 0 && !window.busy; onActivated: saveDialog.open()
                }
                Flow {
                    id: toolbarGroups
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 8
                    anchors.topMargin: 44
                    spacing: 16
                Row {
                    spacing: 3
                    ToolButton { label: "Pages"; chosen: window.sidebarVisible; enabled: pages.count > 0; onActivated: window.sidebarVisible = !window.sidebarVisible }
                    ToolButton { label: "Add PDF"; onActivated: addDialog.open() }
                }
                Row {
                    id: editTools
                    spacing: 2
                    ToolButton { id: textButton; label: "Add text"; chosen: window.tool === "text"; enabled: pages.count > 0; onActivated: { if (window.tool === "text") window.clearCanvasSelection(); else window.tool = "text" } }
                    ToolButton { id: signButton; label: "Sign"; chosen: window.tool === "sign"; enabled: pages.count > 0; onActivated: {
                        if (window.signature.length === 0) signatureDialog.open(); else signatureMenu.popup()
                    } }
                }
                Row {
                    spacing: 3
                    ToolButton { id: bookmarkButton; label: "Bookmarks"; chosen: window.isBookmarked(); enabled: pages.count > 0; onActivated: { window.clearCanvasSelection(); bookmarkMenu.popup() } }
                    ToolButton { label: "Continuous"; chosen: window.continuous; enabled: pages.count > 0; onActivated: { window.continuous = !window.continuous; Qt.callLater(function() { window.positionReadingPage(window.currentIndex, false) }) } }
                }
                }
            }

            Rectangle {
                id: sidebar
                anchors.left: parent.left; anchors.top: toolbar.bottom; anchors.bottom: status.top
                width: pages.count > 0 && window.sidebarVisible ? 190 : 0
                visible: width > 0
                color: Theme.chrome
                clip: true
                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.hairline }

                Text {
                    id: sidebarTitle
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: 13; anchors.topMargin: 13
                    text: pages.count + (pages.count === 1 ? " page" : " pages")
                    color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                }
                ListView {
                    id: pageList
                    maximumFlickVelocity: 9000
                    flickDeceleration: 1600
                    MomentumScroll { anchors.fill: parent; surface: pageList; enabled: window.interactionReady && !window.modalActive && !window.zooming }
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: sidebarTitle.bottom; anchors.bottom: parent.bottom
                    anchors.topMargin: 8; anchors.bottomMargin: 6
                    clip: true; model: pages
                    cacheBuffer: 0
                    ScrollBar.vertical: ScrollBar { }
                    currentIndex: pages.count ? 0 : -1
                    onCurrentIndexChanged: {
                        window.selectedAnnotation = -1
                        window.wheelEdgeDistance = 0
                        if (!window.followingScroll) Qt.callLater(function() { window.positionReadingPage(window.currentIndex, false) })
                    }
                    delegate: Rectangle {
                        required property int index
                        required property string path
                        required property int page
                        required property var model
                        id: pageRow
                        readonly property bool thumbnailActive: thumbnailLoader.active
                        readonly property bool thumbnailReady: thumbnailLoader.item ? thumbnailLoader.item.ready : false
                        readonly property alias actionsButton: pageActions
                        width: ListView.view.width; height: 184
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 6
                            radius: 8
                            color: pageRow.ListView.isCurrentItem ? Theme.selected : rowTap.containsMouse ? Theme.hover : "transparent"
                            border.width: pageRow.ListView.isCurrentItem ? 1 : 0
                            border.color: Theme.accent
                        }
                        Loader {
                            id: thumbnailLoader
                            anchors.top: parent.top; anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 150; height: 144
                            // Only render viewport thumbnails; closing the sidebar releases them.
                            active: window.sidebarVisible && pageRow.y + pageRow.height > pageList.contentY && pageRow.y < pageList.contentY + pageList.height
                            sourceComponent: Item {
                                readonly property bool ready: thumbnailImage.status === Image.Ready
                                Rectangle {
                                    id: thumbnailPaper
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height * pageRow.model.width / pageRow.model.height)
                                    height: width * pageRow.model.height / pageRow.model.width
                                    color: "white"
                                    PdfRaster {
                                        id: thumbnailImage
                                        anchors.fill: parent
                                        document: window.pdfDocumentFor(pageRow.path)
                                        currentFrame: Math.max(0, pageRow.page - 1)
                                        sourceSize.width: 150
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                            text: index + 1
                            visible: !pageRow.ListView.isCurrentItem
                            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            text: (window.bookmarks[path] || []).indexOf(page) >= 0 ? "◆" : ""
                            color: (window.bookmarks[path] || []).indexOf(page) >= 0 ? Theme.accent : Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                        }
                        MouseArea {
                            id: rowTap; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) window.openPageActions(index)
                                else window.jumpToPage(index)
                            }
                        }
                        ToolButton {
                            id: pageActions
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                            label: "Page " + (index + 1) + " ⌄"; visible: pageRow.ListView.isCurrentItem
                            accessibleName: "Actions for page " + (index + 1)
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            ToolTip.text: "Page actions · Shift+F10"
                            onActivated: window.openPageActions(index)
                        }
                    }
                }
            }

            Rectangle {
                id: workspace
                anchors.left: sidebar.right; anchors.right: parent.right; anchors.top: toolbar.bottom; anchors.bottom: status.top
                color: Qt.darker(Theme.background, 1.08)

                Rectangle {
                    id: draftNotice
                    anchors.top: parent.top; anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 32, noticeText.implicitWidth + noticeDismiss.width + 40)
                    height: Math.max(40, noticeText.implicitHeight + 16); radius: 8; z: 50
                    visible: window.draftNoticeVisible
                    color: Theme.chrome
                    border.width: 1; border.color: Theme.accent

                    Text {
                        id: noticeText
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.right: noticeDismiss.left; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Draft restored — continue where you left off"
                        wrapMode: Text.WordWrap
                        color: Theme.foreground
                        font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    }
                    ToolButton {
                        id: noticeDismiss
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Dismiss"; labelColor: Theme.accent
                        accessibleName: "Dismiss draft restored notice"
                        onActivated: window.draftNoticeVisible = false
                    }
                }

                Column {
                    anchors.centerIn: parent; spacing: 14; visible: pages.count === 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Oma Preview"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 28 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Open a PDF to read, fill, sign, or rearrange it."; color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.textSize }
                    ToolButton { anchors.horizontalCenter: parent.horizontalCenter; label: "Open PDF"; chosen: true; onActivated: openDialog.open() }
                }

                Flickable {
                    id: viewport
                    maximumFlickVelocity: 9000
                    flickDeceleration: 1600
                    interactive: !window.zooming
                    MomentumScroll {
                        id: continuousWheel
                        anchors.fill: parent
                        surface: viewport
                        enabled: window.continuous && pages.count > 0 && !window.modalActive && window.editingAnnotation < 0 && !window.zooming
                    }
                    WheelHandler {
                        target: null
                        enabled: window.readingEnabled && !window.continuous
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.NoModifier
                        onWheel: event => {
                            var delta = event.pixelDelta.y ? -event.pixelDelta.y : -event.angleDelta.y / 120 * 80
                            if (delta) { window.scrollReading(delta, true); event.accepted = true }
                        }
                    }
                    anchors.fill: parent
                    visible: pages.count > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: window.continuous ? window.pageLayout.width : Math.max(width, paper.width + 80)
                    contentHeight: window.continuous ? Math.max(height, window.pageLayout.height) : Math.max(height, paper.height + 80)
                    onContentYChanged: { scrollSelection.restart(); readingSave.restart() }
                    onContentXChanged: readingSave.restart()
                    Timer { id: scrollSelection; interval: 0; onTriggered: window.followReadingScroll() }
                    onWidthChanged: {
                        window.layoutChanging = true
                        Qt.callLater(function() {
                            if (window.continuous) window.positionReadingPage(window.currentIndex, false)
                            window.layoutChanging = false
                        })
                    }
                    ScrollBar.vertical: ScrollBar { }

                    HoverHandler {
                        id: zoomPointer
                        parent: viewport
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    }
                    PinchHandler {
                        id: zoomGesture
                        parent: viewport
                        target: null
                        acceptedDevices: PointerDevice.TouchPad | PointerDevice.TouchScreen
                        rotationAxis.enabled: false
                        xAxis.enabled: false
                        yAxis.enabled: false
                        property real zoomAtStart: 1
                        property real anchorX: 0.5
                        property real anchorY: 0.5
                        property real screenX: 0
                        property real screenY: 0

                        onActiveChanged: {
                            window.zooming = active
                            if (!active) { renderDebounce.restart(); return }
                            continuousWheel.stop()
                            if (!active || !pages.count) return
                            zoomAtStart = window.zoom
                            // Handler positions may be content-relative inside Flickable.
                            // Convert from scene coordinates so scroll offsets never enter the anchor twice.
                            var touchScreen = centroid.device && centroid.device.type === PointerDevice.TouchScreen
                            var sceneFocus = !touchScreen && zoomPointer.hovered ? zoomPointer.point.scenePosition : centroid.scenePosition
                            var focus = viewport.mapFromItem(window.contentItem, sceneFocus.x, sceneFocus.y)
                            screenX = focus.x
                            screenY = focus.y
                            if (window.continuous) {
                                var position = viewport.contentY + screenY
                                var lo = window.pageAtY(position)
                                window.followingScroll = true; pageList.currentIndex = lo; window.followingScroll = false
                            }
                            var point = viewport.mapToItem(paper, screenX, screenY)
                            anchorX = Math.max(0, Math.min(1, point.x / Math.max(1, paper.width)))
                            anchorY = Math.max(0, Math.min(1, point.y / Math.max(1, paper.height)))
                        }
                        onActiveScaleChanged: {
                            if (!active || !pages.count) return
                            var nextZoom = Math.max(0.5, Math.min(3, zoomAtStart * activeScale))
                            if (Math.abs(nextZoom - window.zoom) < 0.001) return
                            window.zoom = nextZoom
                            var wantedX = paper.x + zoomGesture.anchorX * paper.width - zoomGesture.screenX
                            var wantedY = paper.y + zoomGesture.anchorY * paper.height - zoomGesture.screenY
                            viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, wantedX))
                            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, wantedY))
                        }
                    }

                    Repeater {
                        id: readingRepeater
                        model: readingPages
                        delegate: Loader {
                            id: readingLoader
                            required property int pageIndex
                            readonly property var pageData: pageIndex < pages.count ? pages.get(pageIndex) : ({path:"",page:1,key:"",width:595})
                            readonly property var geometry: window.pageGeometry(pageIndex) || ({top:0, width:0, height:0})
                            x: (viewport.contentWidth - width) / 2; y: geometry.top
                            width: geometry.width; height: geometry.height
                            active: !window.loadingWorkspace && window.continuous && pageIndex !== window.currentIndex
                            sourceComponent: ReadingPage {
                                width: readingLoader.width; height: readingLoader.height
                                path: readingLoader.pageData.path; page: readingLoader.pageData.page; pageKey: readingLoader.pageData.key
                                pageWidth: readingLoader.pageData.width
                                pdfSource: window.pdfDocumentFor(readingLoader.pageData.path)
                                marks: annotations; markIndices: annotationIndex.forPage(pageKey); zooming: window.zooming
                                fastScrolling: window.fastScrolling
                                searchHit: searchController.hit
                                onClicked: (px, py) => {
                                    if (window.editingAnnotation >= 0) window.clearCanvasSelection()
                                    window.followingScroll = true
                                    pageList.currentIndex = readingLoader.pageIndex
                                    window.followingScroll = false
                                    if (window.tool !== "read") placementArea.placeAt(px, py)
                                }
                            }
                        }
                    }
                    Item {
                        id: paper
                        property real aspect: window.currentPage.width / Math.max(1, window.currentPage.height)
                        property real fitWidth: window.continuous ? Math.max(120, Math.min(900, viewport.width - 64)) : Math.min(viewport.width - 64, (viewport.height - 48) * aspect)
                        width: Math.max(120, fitWidth * window.zoom)
                        height: width / aspect
                        x: Math.max(32, (viewport.contentWidth - width) / 2)
                        y: window.continuous && window.pageGeometry(window.currentIndex) ? window.pageGeometry(window.currentIndex).top : Math.max(24, (viewport.contentHeight - height) / 2)

                        Rectangle { anchors.fill: parent; anchors.margins: -1; color: "#ffffff"; border.width: 1; border.color: "#b8b8b8" }
                        PdfRaster {
                            id: renderedPage
                            sourceSize: Qt.size(Math.max(120, Math.round(width)), 0)
                            Component.onCompleted: sourceSize = Qt.size(Math.max(120, Math.round(width)), 0)
                            property double renderStartedAt: Date.now()
                            property double lastRenderMs: 0
                            onStatusChanged: {
                                if (renderedPage.status === Image.Loading) renderStartedAt = Date.now()
                                if (renderedPage.status === Image.Ready) lastRenderMs = Date.now() - renderStartedAt
                            }
                            anchors.fill: parent
                            document: window.document
                            currentFrame: Math.max(0, window.currentPage.page - 1)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            onWidthChanged: { if (!window.zooming) renderDebounce.restart() }
                            onSourceChanged: { rerender(); renderDebounce.restart() }
                            function rerender() {
                                if (source.toString() === "" || width <= 0 || window.zooming) return
                                var target = Math.round(window.fastScrolling ? Math.min(240, width) : width)
                                var ratio = sourceSize.width > 0 ? target / sourceSize.width : 0
                                if (ratio > 1.12 || ratio < 0.88) sourceSize = Qt.size(target, 0)
                            }
                        }
                        Timer { id: renderDebounce; interval: 140; onTriggered: renderedPage.rerender() }
                        SearchHighlight { id: searchHighlight; anchors.fill: parent; z: 0.5; pageKey: window.currentPage.key; hit: searchController.hit }

                        Canvas {
                            id: bookmarkRibbon
                            width: 18; height: 30; x: parent.width - 42; z: 3
                            y: window.isBookmarked() ? -2 : -12
                            opacity: window.isBookmarked() ? 1 : 0
                            property color ink: Theme.accent
                            onInkChanged: requestPaint()
                            Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = ink
                                ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(width, 0)
                                ctx.lineTo(width, height); ctx.lineTo(width / 2, height - 6)
                                ctx.lineTo(0, height); ctx.closePath(); ctx.fill()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: 1
                            enabled: window.tool === "read" || window.editingAnnotation >= 0
                            cursorShape: Qt.ArrowCursor
                            onClicked: window.clearCanvasSelection()
                        }

                        Repeater {
                            id: annotationRepeater
                            z: 5
                            model: annotationIndex.forPage(window.currentPage.key)
                            function itemForAnnotation(index) {
                                for (var i = 0; i < count; i++) {
                                    var loader = itemAt(i)
                                    if (loader && loader.index === index) return loader
                                }
                                return null
                            }
                            delegate: AnnotationLoader {
                                id: markLoader
                                z: 5
                                sourceModel: annotations
                                sourceComponent: kind === "text" ? textMark : signatureMark
                                Component {
                                    id: textMark
                                    TextEdit {
                                        id: textEditor
                                        property var resizeHandle: textResizeHandle
                                        x: markLoader.nx * paper.width; y: markLoader.ny * paper.height
                                        width: Math.max(60, (markLoader.nw > 0 ? markLoader.nw : 0.20) * paper.width)
                                        height: Math.max(24, contentHeight + 4)
                                        text: markLoader.value; color: markLoader.inkColor
                                        font.family: markLoader.fontFamily; font.pixelSize: Math.round(markLoader.size * paper.width / window.currentPage.width)
                                        selectionColor: Theme.accent; textFormat: TextEdit.PlainText
                                        // Export preserves explicit newlines; avoid displaying soft
                                        // wraps that would disappear in the saved PDF.
                                        wrapMode: TextEdit.NoWrap
                                        ToolTip.visible: textDrag.containsMouse && !textDrag.pressed && window.selectedAnnotation === markLoader.index && !textEditor.activeFocus
                                        ToolTip.delay: 800
                                        ToolTip.text: "Drag or arrow keys to move · Shift for larger steps\nDouble-click to edit · Delete to remove"
                                        Keys.priority: Keys.BeforeItem
                                        Keys.onReturnPressed: event => {
                                            if (event.modifiers & Qt.ShiftModifier) insert(cursorPosition, "\n")
                                            else window.finishTextEdit(markLoader.index, false, false)
                                            event.accepted = true
                                        }
                                        Keys.onEnterPressed: event => {
                                            if (event.modifiers & Qt.ShiftModifier) insert(cursorPosition, "\n")
                                            else window.finishTextEdit(markLoader.index, false, false)
                                            event.accepted = true
                                        }
                                        onTextChanged: if (activeFocus && window.editingAnnotation === markLoader.index
                                            && markLoader.index < annotations.count && annotations.get(markLoader.index).value !== text) {
                                            annotations.setProperty(markLoader.index, "value", text)
                                            window.markDirty()
                                        }
                                        onActiveFocusChanged: if (!activeFocus && window.editingAnnotation === markLoader.index)
                                            window.finishTextEdit(markLoader.index, false, false)
                                        HoverHandler { cursorShape: parent.activeFocus ? Qt.IBeamCursor : Qt.OpenHandCursor }
                                        MouseArea {
                                            anchors.fill: parent; z: 15
                                            enabled: parent.activeFocus
                                            acceptedButtons: Qt.NoButton; hoverEnabled: true
                                            cursorShape: Qt.IBeamCursor
                                        }
                                        Text {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 2
                                            text: "Type here"; visible: parent.text.length === 0
                                            color: Theme.muted; opacity: 0.7
                                            font.family: parent.font.family; font.pixelSize: parent.font.pixelSize
                                        }
                                        MouseArea {
                                            id: textDrag
                                            anchors.fill: parent; acceptedButtons: Qt.LeftButton
                                            enabled: !parent.activeFocus
                                            preventStealing: true
                                            drag.target: parent; hoverEnabled: true
                                            drag.threshold: 0
                                            drag.minimumX: 0; drag.maximumX: Math.max(0, paper.width - parent.width)
                                            drag.minimumY: 0; drag.maximumY: Math.max(0, paper.height - parent.height)
                                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                            onPressed: {
                                                window.selectedAnnotation = markLoader.index
                                                window.tool = "read"
                                            }
                                            onDoubleClicked: window.beginTextEdit(markLoader.index, false)
                                            onReleased: {
                                                annotations.setProperty(markLoader.index, "nx", parent.x / paper.width)
                                                annotations.setProperty(markLoader.index, "ny", parent.y / paper.height)
                                                window.markDirty()
                                            }
                                        }
                                        Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; border.width: window.selectedAnnotation === markLoader.index ? 1 : 0; border.color: Theme.accent }
                                        Rectangle {
                                            id: textResizeHandle
                                            width: 10; height: 16; radius: 3; z: 30
                                            anchors.right: parent.right; anchors.rightMargin: -5
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: window.selectedAnnotation === markLoader.index && !textEditor.activeFocus
                                            color: Theme.accent
                                            MouseArea {
                                                anchors.fill: parent; hoverEnabled: true; preventStealing: true
                                                cursorShape: Qt.SizeHorCursor
                                                onReleased: window.markDirty()
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    var point = mapToItem(paper, mouse.x, mouse.y)
                                                    var width = Math.max(60, Math.min(paper.width - textEditor.x, point.x - textEditor.x))
                                                    annotations.setProperty(markLoader.index, "nw", width / paper.width)
                                                }
                                            }
                                        }
                                    }
                                }
                                Component {
                                    id: signatureMark
                                    Item {
                                        id: signatureItem
                                        ToolTip.visible: signatureDrag.containsMouse && !signatureDrag.pressed && window.selectedAnnotation === markLoader.index
                                        ToolTip.delay: 800
                                        ToolTip.text: "Drag or arrow keys to move · Shift for larger steps\nDelete to remove"
                                        property var resizeHandle: signatureResizeHandle
                                        x: markLoader.nx * paper.width; y: markLoader.ny * paper.height
                                        width: markLoader.nw * paper.width; height: markLoader.nh * paper.height
                                        Canvas {
                                            id: signatureCanvas; anchors.fill: parent
                                            property var signatureStrokes: JSON.parse(markLoader.strokeData || "[]")
                                            onSignatureStrokesChanged: requestPaint()
                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()
                                            Component.onCompleted: requestPaint()
                                            onPaint: {
                                                var c = getContext("2d"); c.reset(); c.clearRect(0,0,width,height)
                                                c.strokeStyle = "#111111"; c.lineWidth = Math.max(1.2, paper.width / 500); c.lineCap = "round"; c.lineJoin = "round"
                                                for (var i=0; i<signatureStrokes.length; i++) {
                                                    var s=signatureStrokes[i]; if (!s.length) continue
                                                    c.beginPath(); c.moveTo(s[0].x*width,s[0].y*height)
                                                    for (var j=1;j<s.length;j++) c.lineTo(s[j].x*width,s[j].y*height)
                                                    c.stroke()
                                                }
                                            }
                                        }
                                        Rectangle { anchors.fill: parent; color: "transparent"; border.width: window.selectedAnnotation === markLoader.index ? 1 : 0; border.color: Theme.accent }
                                        MouseArea {
                                            id: signatureDrag
                                            anchors.fill: parent; drag.target: parent; hoverEnabled: true
                                            preventStealing: true; drag.threshold: 0
                                            drag.minimumX: 0; drag.maximumX: Math.max(0, paper.width - parent.width)
                                            drag.minimumY: 0; drag.maximumY: Math.max(0, paper.height - parent.height)
                                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                            onPressed: window.selectedAnnotation = markLoader.index
                                            onReleased: {
                                                annotations.setProperty(markLoader.index, "nx", parent.x / paper.width)
                                                annotations.setProperty(markLoader.index, "ny", parent.y / paper.height)
                                                window.markDirty()
                                            }
                                        }
                                        Rectangle {
                                            id: signatureResizeHandle
                                            width: 11; height: 11; radius: 3; z: 30
                                            anchors.right: parent.right; anchors.rightMargin: -5
                                            anchors.bottom: parent.bottom; anchors.bottomMargin: -5
                                            visible: window.selectedAnnotation === markLoader.index
                                            color: Theme.accent
                                            MouseArea {
                                                anchors.fill: parent; hoverEnabled: true; preventStealing: true
                                                cursorShape: Qt.SizeFDiagCursor
                                                onReleased: window.markDirty()
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    var point = mapToItem(paper, mouse.x, mouse.y)
                                                    var wantedWidth = Math.max(36, point.x - signatureItem.x)
                                                    var currentWidth = Math.max(1, markLoader.nw * paper.width)
                                                    var factor = wantedWidth / currentWidth
                                                    var maxFactorX = (paper.width - signatureItem.x) / currentWidth
                                                    var maxFactorY = (paper.height - signatureItem.y) / Math.max(1, markLoader.nh * paper.height)
                                                    factor = Math.min(factor, maxFactorX, maxFactorY)
                                                    annotations.setProperty(markLoader.index, "nw", Math.max(0.06, markLoader.nw * factor))
                                                    annotations.setProperty(markLoader.index, "nh", Math.max(0.025, markLoader.nh * factor))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            id: placementArea
                            z: 20
                            enabled: window.tool === "sign" || (window.tool === "text" && window.editingAnnotation < 0)
                            cursorShape: Qt.CrossCursor
                            onClicked: mouse => placeAt(mouse.x, mouse.y)
                            function placeAt(px, py) {
                                if (window.tool === "text") {
                                    var fontHeight = window.preferredTextSize * paper.width / window.currentPage.width
                                    var placedY = Math.max(0, Math.min(paper.height - 24, py - fontHeight * 0.75))
                                    annotations.append({kind:"text", pageKey:window.currentPage.key, nx:Math.min(0.78,px/paper.width), ny:placedY/paper.height, value:"", size:window.preferredTextSize, fontFamily:window.preferredTextFont, inkColor:window.preferredTextColor, nw:0.20, nh:0, strokeData:"[]"})
                                    var textIndex = annotations.count - 1
                                    window.beginTextEdit(textIndex, true)
                                    window.markDirty()
                                    window.say("Type here — click outside to finish, Esc to cancel", false)
                                } else if (window.signature.length > 0) {
                                    annotations.append({kind:"signature", pageKey:window.currentPage.key, nx:Math.min(0.74,px/paper.width), ny:Math.min(0.88,py/paper.height), value:"", size:0, fontFamily:"sans-serif", inkColor:"#111111", nw:0.24, nh:0.09, strokeData:JSON.stringify(window.signature)})
                                    window.selectedAnnotation = annotations.count - 1
                                    window.tool = "read"
                                    window.markDirty()
                                    window.say("Signature placed — drag to adjust; Delete removes it", false)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: status
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 34; color: Theme.chrome
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.hairline }
                Text {
                    id: statusMessage
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    anchors.right: zoomControls.left; anchors.rightMargin: 12
                    text: !window.interactionReady ? window.busyText : window.statusText || (pages.count ? (window.suggestedOutput ? "Agent review  •  " : "") + "Page " + (window.currentIndex + 1) + " of " + pages.count + (window.hasWorkingDraft && window.draftPersisted ? "  •  Draft saved" : "") : "Ready")
                    color: window.interactionReady && window.statusError ? Theme.urgent : Theme.secondaryText
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    visible: !formatControls.visible
                    ToolTip.visible: messageHover.containsMouse && truncated
                    ToolTip.delay: 600
                    ToolTip.text: statusMessage.text
                    MouseArea { id: messageHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                Row {
                    id: formatControls
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2; visible: window.hasSelectedAnnotation && window.interactionReady
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.selectedKind === "text" ? "Text" : "Signature"
                        color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    }
                    ToolButton {
                        id: formatEdit; visible: window.selectedKind === "text"
                        label: window.editingAnnotation === window.selectedAnnotation ? "Editing" : "Edit"
                        chosen: window.editingAnnotation === window.selectedAnnotation
                        enabled: window.editingAnnotation < 0
                        onActivated: window.beginTextEdit(window.selectedAnnotation, false)
                    }
                    ToolButton { compact: true; label: "−"; accessibleName: "Decrease annotation size"; onActivated: window.changeSelectedSize(-1) }
                    Text {
                        width: 34; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
                        text: window.selectedKind === "text" ? Math.round(annotations.get(window.selectedAnnotation).size) : "Size"
                        color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    }
                    ToolButton { id: formatSizeUp; compact: true; label: "+"; accessibleName: "Increase annotation size"; onActivated: window.changeSelectedSize(1) }
                    ToolButton {
                        id: formatFont; visible: window.selectedKind === "text"
                        label: window.selectedFontLabel(); onActivated: window.cycleSelectedFont()
                    }
                    ToolButton { id: inkBlack; visible: window.selectedKind === "text"; compact: true; label: "●"; accessibleName: "Black text"; labelColor: "#111111"; chosen: window.selectedColorIs("#111111"); onActivated: window.setSelectedColor("#111111") }
                    ToolButton { id: inkBlue; visible: window.selectedKind === "text"; compact: true; label: "●"; accessibleName: "Blue text"; labelColor: "#2563eb"; chosen: window.selectedColorIs("#2563eb"); onActivated: window.setSelectedColor("#2563eb") }
                    ToolButton { id: inkRed; visible: window.selectedKind === "text"; compact: true; label: "●"; accessibleName: "Red text"; labelColor: "#b42318"; chosen: window.selectedColorIs("#b42318"); onActivated: window.setSelectedColor("#b42318") }
                    ToolButton { id: formatDelete; label: "Delete"; danger: true; enabled: window.editingAnnotation < 0; onActivated: window.deleteSelectedAnnotation() }
                }
                Row {
                    id: zoomControls
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2; visible: pages.count > 0
                    ToolButton { id: zoomOutButton; compact: true; label: "−"; accessibleName: "Zoom out"; enabled: window.zoom > 0.5; onActivated: window.zoomTo(window.zoom - 0.15) }
                    Text { width: 46; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; text: Math.round(window.zoom * 100) + "%"; color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize }
                    ToolButton { id: zoomInButton; compact: true; label: "+"; accessibleName: "Zoom in"; enabled: window.zoom < 3; onActivated: window.zoomTo(window.zoom + 0.15) }
                }
            }
        }

        FileDialog {
            id: openDialog; title: "Open PDF"; fileMode: FileDialog.OpenFiles; nameFilters: ["PDF documents (*.pdf)"]
            // Keep GTK/Tracker file search out of our process (native dialog crash).
            options: FileDialog.DontUseNativeDialog
            onAccepted: { var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.replaceWorkspace(p) }
        }
        ThemedMenu {
            id: signatureMenu
            x: Math.min(signButton.mapToItem(window.contentItem, 0, 0).x, window.width - width - 8)
            y: toolbar.height
            MenuItem { id: signaturePlace; text: "Place saved signature"; enabled: window.signature.length > 0; opacity: enabled ? 1 : 0.42; onTriggered: window.tool = "sign" }
            MenuItem { id: signatureDraw; text: "Draw a new signature…"; onTriggered: signatureDialog.open() }
        }
        ThemedMenu {
            id: pageMenu
            onClosed: paper.forceActiveFocus()
            MenuItem {
                id: pageMenuTitle; text: "Page " + (window.currentIndex + 1); enabled: false
                contentItem: Text {
                    text: pageMenuTitle.text; color: Theme.secondaryText
                    font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize; font.weight: Font.DemiBold
                }
            }
            MenuSeparator { }
            MenuItem { id: pageBookmark; text: window.isBookmarked() ? "Remove bookmark" : "Bookmark page"; enabled: pages.count > 0; onTriggered: window.toggleBookmark() }
            MenuSeparator { }
            MenuItem { id: pageMoveUp; text: "Move up"; enabled: window.currentIndex > 0; opacity: enabled ? 1 : 0.42; onTriggered: window.movePage(-1) }
            MenuItem { id: pageMoveDown; text: "Move down"; enabled: window.currentIndex + 1 < pages.count; opacity: enabled ? 1 : 0.42; onTriggered: window.movePage(1) }
            MenuSeparator { }
            MenuItem { id: pageRemove; text: "Remove page"; enabled: pages.count > 1; opacity: enabled ? 1 : 0.42; onTriggered: { window.selectedAnnotation = -1; window.deletePage() } }
        }
        ThemedMenu {
            id: bookmarkMenu
            function focusEntry(index) {
                currentIndex = index
                var entry = itemAt(index)
                if (entry) entry.forceActiveFocus(Qt.TabFocusReason)
            }
            Shortcut { enabled: bookmarkMenu.visible; sequence: "Home"; onActivated: bookmarkMenu.focusEntry(0) }
            Shortcut { enabled: bookmarkMenu.visible; sequence: "End"; onActivated: bookmarkMenu.focusEntry(window.bookmarkEntries.length ? window.bookmarkEntries.length + 1 : 0) }
            x: Math.min(bookmarkButton.mapToItem(window.contentItem, 0, 0).x, window.width - width - 8)
            y: toolbar.height
            width: Math.min(360, window.width - 16)
            height: Math.min(implicitHeight, window.height - toolbar.height - 42)
            MenuItem { text: window.isBookmarked() ? "Remove bookmark" : "Bookmark this page"; enabled: pages.count > 0; onTriggered: window.toggleBookmark() }
            MenuSeparator { }
            Instantiator {
                model: window.bookmarkEntries
                delegate: MenuItem {
                    required property var modelData
                    text: modelData.label
                    onTriggered: window.jumpToPage(modelData.index)
                }
                onObjectAdded: (index, object) => bookmarkMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => bookmarkMenu.removeItem(object)
            }
            MenuItem { text: "No bookmarked pages yet"; enabled: false; visible: window.bookmarkEntries.length === 0; height: visible ? implicitHeight : 0 }
        }
        ThemedMenu {
            id: recentMenu
            function focusEntry(index) {
                currentIndex = index
                var entry = itemAt(index)
                if (entry) entry.forceActiveFocus(Qt.TabFocusReason)
            }
            Shortcut { enabled: recentMenu.visible && window.recents.length > 0; sequence: "Home"; onActivated: recentMenu.focusEntry(0) }
            Shortcut { enabled: recentMenu.visible && window.recents.length > 0; sequence: "End"; onActivated: recentMenu.focusEntry(window.recents.length - 1) }
            x: Math.min(recentButton.mapToItem(window.contentItem, 0, 0).x, window.width - width - 8)
            y: toolbar.height
            width: Math.min(420, window.width - 16)
            height: Math.min(implicitHeight, window.height - toolbar.height - 42)
            Instantiator {
                model: window.recents
                delegate: MenuItem {
                    id: recentEntry
                    required property string modelData
                    text: window.fileName(modelData)
                    Accessible.name: text + ", " + modelData
                    implicitHeight: 54
                    leftPadding: 12; rightPadding: 12
                    contentItem: Column {
                        spacing: 3
                        Text {
                            width: parent.width
                            text: recentEntry.text
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
                            color: Theme.foreground
                        }
                        Text {
                            width: parent.width
                            text: recentEntry.modelData.substring(0, recentEntry.modelData.lastIndexOf("/")) || "/"
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                            color: Theme.secondaryText
                        }
                    }
                    ToolTip.visible: hovered
                    ToolTip.delay: 700
                    ToolTip.text: modelData
                    onTriggered: window.replaceWorkspace([modelData])
                }
                onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => recentMenu.removeItem(object)
            }
            MenuItem { text: "No recent PDFs"; enabled: false; visible: window.recents.length === 0; height: visible ? implicitHeight : 0 }
            MenuSeparator { visible: window.recents.length > 0; height: visible ? implicitHeight : 0 }
            MenuItem { text: "Clear recent files"; enabled: window.recents.length > 0; onTriggered: backend.clearRecents() }
        }
        FileDialog {
            id: addDialog; title: "Add PDF"; fileMode: FileDialog.OpenFiles; nameFilters: ["PDF documents (*.pdf)"]
            options: FileDialog.DontUseNativeDialog
            onAccepted: { var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.openPaths(p, false) }
        }
        FileDialog {
            id: saveDialog; title: "Save PDF as"; fileMode: FileDialog.SaveFile; defaultSuffix: "pdf"; nameFilters: ["PDF document (*.pdf)"]
            options: FileDialog.DontUseNativeDialog
            currentFile: window.suggestedOutput ? window.fileUri(window.suggestedOutput) : ""
            onAccepted: window.saveTo(window.fromUrl(selectedFile))
            onRejected: window.closeAfterExport = false
        }
        SignatureDialog {
            id: signatureDialog
            onAccepted: strokes => { window.signature = strokes; backend.saveSignature(strokes); window.tool = "sign" }
            onClosed: paper.forceActiveFocus()
        }
        CloseDialog {
            id: closeDialog
            onDiscardRequested: window.finishWithDraft(false)
            onClosed: paper.forceActiveFocus()
        }
        DraftRecovery {
            id: draftRecovery
            problem: window.draftProblem
            working: window.busy || window.loadingWorkspace
            onCloseRequested: window.close()
            onOpenRequested: openDialog.open()
            onRetryRequested: {
                window.loadingWorkspace = true
                window.busyText = "Checking saved draft…"
                backend.loadDraft(window.draftKey)
            }
        }
        Ipc {
            previewWindow: window
            pages: pages
            annotations: annotations
            annotationRepeater: annotationRepeater
            paper: paper
            textButton: textButton
            signButton: signButton
            formatSizeUp: formatSizeUp
            formatFont: formatFont
            inkBlue: inkBlue
            formatEdit: formatEdit
            formatDelete: formatDelete
            closeDialog: closeDialog
            backend: backend
            renderedPage: renderedPage
            recentButton: recentButton
            recentMenu: recentMenu
        }
        Timer { id: statusTimer; interval: 4500; onTriggered: window.statusText = "" }
        Timer { id: draftTimer; interval: 600; onTriggered: window.saveDraftNow() }
        PageJump {
            id: pageJump
            parent: window.contentItem
            pageCount: pages.count
            currentPage: window.currentIndex + 1
            onPageChosen: page => window.jumpToPage(page - 1)
            onClosed: paper.forceActiveFocus()
        }
        Shortcut { enabled: window.readingEnabled; sequence: "Ctrl+G"; onActivated: pageJump.open() }
        Shortcut { enabled: window.readingKeysEnabled; sequence: "Shift+F10"; onActivated: window.openPageActions(window.currentIndex) }
        Shortcut { enabled: window.interactionReady && !window.modalActive; sequence: "Ctrl+O"; onActivated: openDialog.open() }
        Shortcut { enabled: window.interactionReady && !window.modalActive; sequence: "Ctrl+W"; onActivated: window.close() }
        Shortcut { enabled: window.interactionReady && !window.modalActive && window.hasWorkingDraft; sequence: "Ctrl+Shift+W"; onActivated: closeDialog.open() }
        Shortcut { enabled: window.interactionReady && !window.modalActive && pages.count > 0; sequence: "F9"; onActivated: window.sidebarVisible = !window.sidebarVisible }
        Shortcut { sequence: "Ctrl+Z"; enabled: window.interactionReady && !window.modalActive && !findBar.field.activeFocus && (window.editingAnnotation < 0); onActivated: window.travelHistory(false) }
        Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; enabled: window.interactionReady && !window.modalActive && !findBar.field.activeFocus && (window.editingAnnotation < 0); onActivated: window.travelHistory(true) }
        Shortcut { enabled: window.interactionReady && !window.modalActive; sequence: "Ctrl+Shift+O"; onActivated: addDialog.open() }
        Shortcut { sequence: "Ctrl+Shift+S"; enabled: window.interactionReady && !window.modalActive && (pages.count > 0); onActivated: saveDialog.open() }
        Shortcut { sequence: "Ctrl+B"; enabled: window.interactionReady && !window.modalActive && (pages.count > 0); onActivated: window.toggleBookmark() }
        Shortcut { sequence: "Delete"; enabled: window.interactionReady && !window.modalActive && !window.controlHasFocus && (pages.count > 0 && window.editingAnnotation < 0); onActivated: window.deletePage() }
        Shortcut { sequence: "Escape"; enabled: window.interactionReady && !window.modalActive && !findBar.hasFocus && (window.editingAnnotation >= 0 || window.tool !== "read" || window.selectedAnnotation >= 0); onActivated: window.cancelCurrentAction() }
        Shortcut { sequence: "Ctrl+F"; enabled: window.interactionReady && !window.modalActive && pages.count > 0; onActivated: window.openFind() }
        Shortcut { sequence: "F3"; enabled: findBar.opened && window.interactionReady && !window.modalActive; onActivated: searchController.step(1) }
        Shortcut { sequence: "Shift+F3"; enabled: findBar.opened && window.interactionReady && !window.modalActive; onActivated: searchController.step(-1) }
        Shortcut { sequence: "Escape"; enabled: findBar.opened && window.interactionReady && !window.modalActive && (findBar.hasFocus || (window.editingAnnotation < 0 && window.selectedAnnotation < 0 && window.tool === "read")); onActivated: findBar.dismiss() }
        Shortcut { sequence: "Return"; enabled: window.interactionReady && !window.modalActive && !window.controlHasFocus && (window.selectedKind === "text" && window.editingAnnotation < 0); onActivated: window.beginTextEdit(window.selectedAnnotation, false) }
        Shortcut { sequence: "Left"; enabled: window.readingKeysEnabled || window.annotationKeysEnabled; onActivated: window.hasSelectedAnnotation ? window.nudgeAnnotation(-1, 0, false) : window.turnReadingPage(-1, false) }
        Shortcut { sequence: "Right"; enabled: window.readingKeysEnabled || window.annotationKeysEnabled; onActivated: window.hasSelectedAnnotation ? window.nudgeAnnotation(1, 0, false) : window.turnReadingPage(1, false) }
        Shortcut { sequence: "Down"; enabled: window.readingKeysEnabled || window.annotationKeysEnabled; onActivated: window.hasSelectedAnnotation ? window.nudgeAnnotation(0, 1, false) : window.scrollReading(64, false) }
        Shortcut { sequence: "Up"; enabled: window.readingKeysEnabled || window.annotationKeysEnabled; onActivated: window.hasSelectedAnnotation ? window.nudgeAnnotation(0, -1, false) : window.scrollReading(-64, false) }
        Shortcut { sequence: "Shift+Left"; enabled: window.annotationKeysEnabled; onActivated: window.nudgeAnnotation(-1, 0, true) }
        Shortcut { sequence: "Shift+Right"; enabled: window.annotationKeysEnabled; onActivated: window.nudgeAnnotation(1, 0, true) }
        Shortcut { sequence: "Shift+Down"; enabled: window.annotationKeysEnabled; onActivated: window.nudgeAnnotation(0, 1, true) }
        Shortcut { sequence: "Shift+Up"; enabled: window.annotationKeysEnabled; onActivated: window.nudgeAnnotation(0, -1, true) }
        Shortcut { sequences: ["PgDown", "Space"]; enabled: window.readingKeysEnabled; onActivated: window.scrollReading(viewport.height * 0.85, false) }
        Shortcut { sequences: ["PgUp", "Shift+Space"]; enabled: window.readingKeysEnabled; onActivated: window.scrollReading(-viewport.height * 0.85, false) }
        Shortcut { sequence: "Ctrl+Home"; enabled: window.interactionReady && !window.modalActive && !window.controlHasFocus && (window.editingAnnotation < 0 && pages.count > 0); onActivated: window.jumpToPage(0) }
        Shortcut { sequence: "Ctrl+End"; enabled: window.interactionReady && !window.modalActive && !window.controlHasFocus && (window.editingAnnotation < 0 && pages.count > 0); onActivated: window.jumpToPage(pages.count - 1) }
        Shortcut { enabled: window.interactionReady && !window.modalActive && pages.count > 0; sequences: ["Ctrl++", "Ctrl+="]; onActivated: window.zoomTo(window.zoom + 0.15) }
        Shortcut { enabled: window.interactionReady && !window.modalActive && pages.count > 0; sequence: "Ctrl+-"; onActivated: window.zoomTo(window.zoom - 0.15) }

        Component.onCompleted: {
            backend.getRecents()
            backend.getSignature()
            var raw = Quickshell.env("OMA_PREVIEW_PATHS") || "[]"
            try { var initial = JSON.parse(raw); var clean=[]; for(var i=0;i<initial.length;i++) if(initial[i]) clean.push(initial[i]); openPaths(clean, true) }
            catch(e) { say("Could not read the files passed to Oma Preview.", true) }
            var reviewSpec = Quickshell.env("OMA_PREVIEW_REVIEW_SPEC") || ""
            if (reviewSpec) {
                busyText = "Loading proposed edits…"
                loadingWorkspace = true
                busy = true
                backend.loadSpec(reviewSpec, Quickshell.env("OMA_PREVIEW_ALLOW_SAVED_SIGNATURE") === "1")
            }
        }
    }
}
