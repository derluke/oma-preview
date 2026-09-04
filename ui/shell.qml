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

        property int currentIndex: pages.count > 0 ? Math.min(pageList.currentIndex < 0 ? 0 : pageList.currentIndex, pages.count - 1) : -1
        property var currentPage: (currentIndex >= 0 ? pages.get(currentIndex) : null) || ({path:"", page:1, width:595, height:842, key:""})
        property string tool: "read"
        property real zoom: 1.0
        property int serial: 0
        property int selectedAnnotation: -1
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
        property string suggestedOutput: ""
        property bool dirty: false
        property bool loadingWorkspace: false
        property bool baseStartsDirty: false
        property bool draftRestored: false
        property bool draftNoticeVisible: false
        property string draftKey: ""
        property int pendingInspections: 0
        property bool loadDraftAfterInspect: false
        property bool markDirtyAfterInspect: false
        property bool allowClose: false
        property bool closeAfterExport: false
        property bool editingOriginalDirty: false
        property bool applyingLiveReview: false
        property int reviewRevision: 0
        property string reviewError: ""
        property var undoStack: []
        property var redoStack: []
        property var historyHead: null
        property string savedContent: ""

        function historySnapshot() {
            var marks = []
            for (var i = 0; i < annotations.count; i++) marks.push(JSON.parse(JSON.stringify(annotations.get(i))))
            return {pages:pagePayload(), marks:marks, current:currentIndex, output:suggestedOutput}
        }
        function contentKey(s) { return JSON.stringify([s.pages, s.marks, s.output]) }
        function resetHistory() {
            undoStack = []; redoStack = []; historyHead = historySnapshot()
            savedContent = dirty ? "" : contentKey(historyHead)
        }
        function recordHistory() {
            if (editingAnnotation >= 0) return
            var next = historySnapshot()
            if (historyHead && contentKey(next) !== contentKey(historyHead)) {
                undoStack = undoStack.concat([historyHead]).slice(-100)
                redoStack = []
            }
            historyHead = next
        }
        function travelHistory(redo) {
            if (busy || loadingWorkspace || editingAnnotation >= 0) return
            var stack = redo ? redoStack : undoStack
            if (!stack.length) return
            var target = stack[stack.length - 1]
            if (redo) { undoStack = undoStack.concat([historySnapshot()]); redoStack = stack.slice(0, -1) }
            else { redoStack = redoStack.concat([historySnapshot()]); undoStack = stack.slice(0, -1) }
            loadingWorkspace = true
            selectedAnnotation = -1; tool = "read"
            pages.clear(); annotations.clear()
            target.pages.forEach(function(p) { pages.append(p) })
            target.marks.forEach(function(a) { annotations.append(a) })
            pageList.currentIndex = target.current
            suggestedOutput = target.output
            loadingWorkspace = false
            historyHead = historySnapshot()
            dirty = contentKey(historyHead) !== savedContent
            draftTimer.stop()
            if (dirty) saveDraftNow()
            else if (draftKey.length) backend.deleteDraft(draftKey)
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
            statusText = text; statusError = error === true; statusTimer.restart()
        }
        function openPaths(paths, restoreDraft) {
            if (!paths || paths.length === 0) return
            busy = true
            pendingInspections = paths.length
            loadingWorkspace = true
            loadDraftAfterInspect = restoreDraft === true
            markDirtyAfterInspect = restoreDraft !== true
            if (restoreDraft === true) draftKey = JSON.stringify(paths)
            for (var i = 0; i < paths.length; i++) {
                if (String(paths[i]).length) backend.inspect(String(paths[i]))
            }
        }
        function replaceWorkspace(paths) {
            clearCanvasSelection()
            saveDraftNow()
            pages.clear(); annotations.clear(); pageList.currentIndex = -1
            dirty = false; draftRestored = false; draftNoticeVisible = false
            suggestedOutput = ""
            openPaths(paths, true)
        }
        function pagePayload() {
            var out = []
            for (var i = 0; i < pages.count; i++) {
                var p = pages.get(i)
                out.push({path:p.path, page:p.page, width:p.width, height:p.height, key:p.key})
            }
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
        function draftPayload() {
            return {schema:1, pages:pagePayload(), annotations:annotationPayload(), current_page:currentIndex,
                    zoom:zoom, suggested_output:suggestedOutput, saved_at:new Date().toISOString()}
        }
        function markDirty() {
            if (loadingWorkspace) return
            recordHistory()
            dirty = editingAnnotation >= 0 || !historyHead || contentKey(historyHead) !== savedContent
            if (draftKey.length) draftTimer.restart()
        }
        function saveDraftNow() {
            draftTimer.stop()
            if (dirty && draftKey.length && pages.count) backend.saveDraft(draftKey, draftPayload())
        }
        function restoreDraft(draft) {
            loadingWorkspace = true
            pages.clear(); annotations.clear()
            for (var i = 0; i < draft.pages.length; i++) pages.append(draft.pages[i])
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
            for (var k = 0; k < sourcePaths().length; k++) backend.getBookmarks(sourcePaths()[k])
            say("Draft restored — your unsaved edits are back", false)
        }
        function closeWindow() { allowClose = true; window.close() }
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
            Qt.callLater(function() {
                var loader = annotationRepeater.itemAt(index)
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
                dirty = editingOriginalDirty
                if (!dirty && draftKey.length) backend.deleteDraft(draftKey)
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
        function saveTo(path) {
            if (!path.toLowerCase().endsWith(".pdf")) path += ".pdf"
            busy = true
            backend.exportPdf(path, pagePayload(), annotationPayload())
        }
        function applyLiveReview(path, allowSavedSignature) {
            if (busy || editingAnnotation >= 0) return false
            saveDraftNow()
            reviewError = ""
            applyingLiveReview = true
            draftNoticeVisible = false
            loadingWorkspace = true
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
            pages.remove(old); pageList.currentIndex = Math.min(old, pages.count - 1); markDirty()
        }

        onClosing: close => {
            if (allowClose || !dirty) return
            close.accepted = false
            saveDraftNow()
            closeDialog.open()
        }
        Connections { target: Quickshell; function onLastWindowClosed() { backend.quit() } }
        Connections { target: backend
            function onRecentsLoaded(paths) { window.recents = paths }
            function onQuitReady() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
            function onInspected(id, path, found) {
                backend.addRecent(path)
                for (var i = 0; i < found.length; i++) {
                    window.serial += 1
                    pages.append({path:path, page:found[i].page, width:found[i].width, height:found[i].height,
                                  key:path + "#" + found[i].page + "#" + window.serial})
                }
                if (pageList.currentIndex < 0 && pages.count) pageList.currentIndex = 0
                backend.getBookmarks(path)
                window.pendingInspections = Math.max(0, window.pendingInspections - 1)
                if (window.pendingInspections === 0) {
                    window.busy = false
                    if (window.loadDraftAfterInspect) {
                        window.baseStartsDirty = false
                        backend.loadDraft(window.draftKey)
                    } else {
                        window.loadingWorkspace = false
                        window.refreshDraftKey()
                        if (window.markDirtyAfterInspect) window.markDirty()
                        window.say("Added " + found.length + (found.length === 1 ? " page" : " pages"), false)
                    }
                }
            }
            function onExported(id, path) {
                window.busy = false; window.dirty = false
                window.savedContent = window.contentKey(window.historySnapshot())
                if (window.draftKey.length) backend.deleteDraft(window.draftKey)
                window.say("Saved " + window.fileName(path), false)
                if (window.closeAfterExport) window.closeWindow()
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
                window.refreshDraftKey(); window.baseStartsDirty = true
                if (window.applyingLiveReview) {
                    window.applyingLiveReview = false
                    window.reviewRevision += 1
                    window.baseStartsDirty = false
                    window.loadingWorkspace = false
                    window.markDirty()
                    window.say("Agent updates applied — review and adjust before saving", false)
                } else backend.loadDraft(window.draftKey)
            }
            function onDraftLoaded(draft) {
                if (draft && draft.schema === 1 && draft.pages && draft.annotations) window.restoreDraft(draft)
                else {
                    window.loadingWorkspace = false
                    if (window.baseStartsDirty) window.markDirty(); else window.dirty = false
                    window.say(window.baseStartsDirty ? "Agent proposal loaded — review and adjust before saving" : "Ready", false)
                }
                window.baseStartsDirty = false
                window.resetHistory()
            }
            function onFailed(message) { if (window.applyingLiveReview) window.reviewError = message; window.busy = false; window.loadingWorkspace = false; window.applyingLiveReview = false; window.say(message, true) }
        }

        Backend { id: backend }
        ListModel { id: pages }
        ListModel { id: annotations }

        Rectangle {
            anchors.fill: parent
            color: Theme.background

            Rectangle {
                id: toolbar
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 48
                color: Theme.chrome
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.hairline }

                Row {
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    ToolButton { label: "Open"; onActivated: openDialog.open() }
                    ToolButton { id: recentButton; label: "Recent"; onActivated: recentMenu.popup() }
                    ToolButton { label: "Add PDF"; onActivated: addDialog.open() }
                    ToolButton { label: "↶"; enabled: window.undoStack.length > 0 && !window.busy && window.editingAnnotation < 0; onActivated: window.travelHistory(false) }
                    ToolButton { label: "↷"; enabled: window.redoStack.length > 0 && !window.busy && window.editingAnnotation < 0; onActivated: window.travelHistory(true) }
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    ToolButton { label: "Read"; chosen: window.tool === "read"; onActivated: window.tool = "read" }
                    ToolButton { id: textButton; label: "Text"; chosen: window.tool === "text"; enabled: pages.count > 0; onActivated: window.tool = "text" }
                    ToolButton { id: signButton; label: "Sign"; chosen: window.tool === "sign"; enabled: pages.count > 0; onActivated: {
                        if (window.signature.length === 0) signatureDialog.open(); else window.tool = "sign"
                    } }
                    ToolButton { label: "Draw signature…"; enabled: pages.count > 0; onActivated: signatureDialog.open() }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    ToolButton { label: window.isBookmarked() ? "Bookmarked" : "Bookmark"; chosen: window.isBookmarked(); enabled: pages.count > 0; onActivated: window.toggleBookmark() }
                    ToolButton { label: window.suggestedOutput ? "Review & export…" : "Save as…"; chosen: true; enabled: pages.count > 0 && !window.busy; onActivated: saveDialog.open() }
                }
            }

            Rectangle {
                id: sidebar
                anchors.left: parent.left; anchors.top: toolbar.bottom; anchors.bottom: status.top
                width: pages.count > 0 ? 190 : 0
                visible: width > 0
                color: Theme.chrome
                clip: true
                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.hairline }

                Text {
                    id: sidebarTitle
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: 13; anchors.topMargin: 13
                    text: pages.count + (pages.count === 1 ? " page" : " pages")
                    color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                }
                ListView {
                    id: pageList
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: sidebarTitle.bottom; anchors.bottom: pageActions.top
                    anchors.topMargin: 8; anchors.bottomMargin: 6
                    clip: true; model: pages
                    currentIndex: pages.count ? 0 : -1
                    onCurrentIndexChanged: { window.currentIndex = currentIndex; window.selectedAnnotation = -1 }
                    delegate: Rectangle {
                        required property int index
                        required property string path
                        required property int page
                        width: ListView.view.width; height: 38
                        color: ListView.isCurrentItem ? Theme.selected : rowTap.containsMouse ? Theme.hover : "transparent"
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 13; anchors.verticalCenter: parent.verticalCenter
                            text: (index + 1) + "   " + window.fileName(path)
                            width: parent.width - 42; elide: Text.ElideMiddle
                            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            text: ((window.bookmarks[path] || []).indexOf(page) >= 0 ? "•  " : "") + page
                            color: (window.bookmarks[path] || []).indexOf(page) >= 0 ? Theme.accent : Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                        }
                        MouseArea { id: rowTap; anchors.fill: parent; hoverEnabled: true; onClicked: pageList.currentIndex = index }
                    }
                }
                Row {
                    id: pageActions
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    spacing: 2
                    ToolButton { compact: true; label: "↑"; enabled: window.currentIndex > 0; onActivated: window.movePage(-1) }
                    ToolButton { compact: true; label: "↓"; enabled: window.currentIndex >= 0 && window.currentIndex + 1 < pages.count; onActivated: window.movePage(1) }
                    ToolButton { compact: true; label: "−"; danger: true; enabled: pages.count > 1; onActivated: window.deletePage() }
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
                    width: Math.min(parent.width - 32, noticeRow.implicitWidth + 28)
                    height: 38; radius: 8; z: 50
                    visible: window.draftNoticeVisible
                    color: Theme.chrome
                    border.width: 1; border.color: Theme.accent

                    Row {
                        id: noticeRow
                        anchors.centerIn: parent; spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Draft restored — your unsaved edits are back"
                            color: Theme.foreground
                            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Dismiss"; color: Theme.accent
                            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -7
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.draftNoticeVisible = false
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent; spacing: 14; visible: pages.count === 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Oma Preview"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 28 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Open a PDF to read, fill, sign, or rearrange it."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.textSize }
                    ToolButton { anchors.horizontalCenter: parent.horizontalCenter; label: "Open PDF"; chosen: true; onActivated: openDialog.open() }
                }

                Flickable {
                    id: viewport
                    anchors.fill: parent
                    visible: pages.count > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: Math.max(width, paper.width + 80)
                    contentHeight: Math.max(height, paper.height + 80)

                    PinchHandler {
                        id: zoomGesture
                        target: null
                        acceptedDevices: PointerDevice.TouchPad | PointerDevice.TouchScreen
                        rotationAxis.enabled: false
                        xAxis.enabled: false
                        yAxis.enabled: false
                        property real zoomAtStart: 1
                        property real anchorX: 0.5
                        property real anchorY: 0.5

                        onActiveChanged: {
                            if (!active || !pages.count) return
                            zoomAtStart = window.zoom
                            var point = viewport.mapToItem(paper, centroid.position.x, centroid.position.y)
                            anchorX = Math.max(0, Math.min(1, point.x / Math.max(1, paper.width)))
                            anchorY = Math.max(0, Math.min(1, point.y / Math.max(1, paper.height)))
                        }
                        onActiveScaleChanged: {
                            if (!active || !pages.count) return
                            var nextZoom = Math.max(0.5, Math.min(3, zoomAtStart * activeScale))
                            if (Math.abs(nextZoom - window.zoom) < 0.001) return
                            window.zoom = nextZoom
                            Qt.callLater(function() {
                                var wantedX = paper.x + zoomGesture.anchorX * paper.width - zoomGesture.centroid.position.x
                                var wantedY = paper.y + zoomGesture.anchorY * paper.height - zoomGesture.centroid.position.y
                                viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, wantedX))
                                viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, wantedY))
                            })
                        }
                    }

                    Item {
                        id: paper
                        property real aspect: window.currentPage.width / Math.max(1, window.currentPage.height)
                        property real fitWidth: Math.min(viewport.width - 80, (viewport.height - 80) * aspect)
                        width: Math.max(120, fitWidth * window.zoom)
                        height: width / aspect
                        x: Math.max(40, (viewport.contentWidth - width) / 2)
                        y: Math.max(40, (viewport.contentHeight - height) / 2)

                        Rectangle { anchors.fill: parent; anchors.margins: -1; color: "#ffffff"; border.width: 1; border.color: "#b8b8b8" }
                        PdfDocument { id: document; source: window.currentIndex >= 0 ? window.fileUri(window.currentPage.path) : "" }
                        PdfPageImage {
                            id: renderedPage
                            property double renderStartedAt: Date.now()
                            property double lastRenderMs: 0
                            onStatusChanged: {
                                if (status === Image.Loading) renderStartedAt = Date.now()
                                if (status === Image.Ready) lastRenderMs = Date.now() - renderStartedAt
                            }
                            anchors.fill: parent
                            document: document
                            currentFrame: Math.max(0, window.currentPage.page - 1)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            onWidthChanged: rerender()
                            onSourceChanged: rerender()
                            function rerender() {
                                if (source.toString() === "" || width <= 0) return
                                var target = Math.round(width)
                                var ratio = sourceSize.width > 0 ? target / sourceSize.width : 0
                                if (ratio > 1.12 || ratio < 0.88) sourceSize = Qt.size(target, 0)
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
                            model: annotations
                            delegate: Loader {
                                id: markLoader
                                z: 5
                                required property int index
                                required property string pageKey
                                required property string kind
                                required property real nx
                                required property real ny
                                required property string value
                                required property real size
                                required property string fontFamily
                                required property string inkColor
                                required property real nw
                                required property real nh
                                required property string strokeData
                                active: pageKey === window.currentPage.key
                                sourceComponent: kind === "text" ? textMark : signatureMark
                                Component {
                                    id: textMark
                                    TextEdit {
                                        id: textEditor
                                        property var resizeHandle: textResizeHandle
                                        x: markLoader.nx * paper.width; y: markLoader.ny * paper.height
                                        width: markLoader.nw > 0 ? Math.max(60, markLoader.nw * paper.width) : Math.max(80, implicitWidth + 8)
                                        height: Math.max(24, contentHeight + 4)
                                        text: markLoader.value; color: markLoader.inkColor
                                        font.family: markLoader.fontFamily; font.pixelSize: Math.round(markLoader.size * paper.width / window.currentPage.width)
                                        selectionColor: Theme.accent; textFormat: TextEdit.PlainText
                                        // Export preserves explicit newlines; avoid displaying soft
                                        // wraps that would disappear in the saved PDF.
                                        wrapMode: TextEdit.NoWrap
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
                                        onTextChanged: if (activeFocus && annotations.get(markLoader.index).value !== text) {
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
                            z: 20
                            enabled: window.tool === "sign" || (window.tool === "text" && window.editingAnnotation < 0)
                            cursorShape: Qt.CrossCursor
                            onClicked: mouse => {
                                if (window.tool === "text") {
                                    var fontHeight = window.preferredTextSize * paper.width / window.currentPage.width
                                    var placedY = Math.max(0, Math.min(paper.height - 24, mouse.y - fontHeight * 0.75))
                                    annotations.append({kind:"text", pageKey:window.currentPage.key, nx:Math.min(0.78,mouse.x/paper.width), ny:placedY/paper.height, value:"", size:window.preferredTextSize, fontFamily:window.preferredTextFont, inkColor:window.preferredTextColor, nw:0.20, nh:0, strokeData:"[]"})
                                    var textIndex = annotations.count - 1
                                    window.beginTextEdit(textIndex, true)
                                    window.markDirty()
                                    window.say("Type here — click outside to finish, Esc to cancel", false)
                                } else if (window.signature.length > 0) {
                                    annotations.append({kind:"signature", pageKey:window.currentPage.key, nx:Math.min(0.74,mouse.x/paper.width), ny:Math.min(0.88,mouse.y/paper.height), value:"", size:0, fontFamily:"sans-serif", inkColor:"#111111", nw:0.24, nh:0.09, strokeData:JSON.stringify(window.signature)})
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
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: window.statusText || (pages.count ? (window.suggestedOutput ? "Agent review  •  " : "") + "Page " + (window.currentIndex + 1) + " of " + pages.count : "Ready")
                    color: window.statusError ? Theme.urgent : Theme.muted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    visible: !formatControls.visible
                }
                Row {
                    id: formatControls
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2; visible: window.hasSelectedAnnotation
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.selectedKind === "text" ? "Text" : "Signature"
                        color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    }
                    ToolButton {
                        id: formatEdit; visible: window.selectedKind === "text"
                        label: window.editingAnnotation === window.selectedAnnotation ? "Editing" : "Edit"
                        chosen: window.editingAnnotation === window.selectedAnnotation
                        enabled: window.editingAnnotation < 0
                        onActivated: window.beginTextEdit(window.selectedAnnotation, false)
                    }
                    ToolButton { compact: true; label: "−"; onActivated: window.changeSelectedSize(-1) }
                    Text {
                        width: 34; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
                        text: window.selectedKind === "text" ? Math.round(annotations.get(window.selectedAnnotation).size) : "Size"
                        color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    }
                    ToolButton { id: formatSizeUp; compact: true; label: "+"; onActivated: window.changeSelectedSize(1) }
                    ToolButton {
                        id: formatFont; visible: window.selectedKind === "text"
                        label: window.selectedFontLabel(); onActivated: window.cycleSelectedFont()
                    }
                    ToolButton { id: inkBlack; visible: window.selectedKind === "text"; compact: true; label: "●"; labelColor: "#111111"; chosen: window.selectedColorIs("#111111"); onActivated: window.setSelectedColor("#111111") }
                    ToolButton { id: inkBlue; visible: window.selectedKind === "text"; compact: true; label: "●"; labelColor: "#2563eb"; chosen: window.selectedColorIs("#2563eb"); onActivated: window.setSelectedColor("#2563eb") }
                    ToolButton { id: inkRed; visible: window.selectedKind === "text"; compact: true; label: "●"; labelColor: "#b42318"; chosen: window.selectedColorIs("#b42318"); onActivated: window.setSelectedColor("#b42318") }
                    ToolButton { id: formatDelete; label: "Delete"; danger: true; enabled: window.editingAnnotation < 0; onActivated: window.deleteSelectedAnnotation() }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2; visible: pages.count > 0
                    ToolButton { compact: true; label: "−"; enabled: window.zoom > 0.55; onActivated: window.zoom = Math.max(0.5, window.zoom - 0.15) }
                    Text { width: 46; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; text: Math.round(window.zoom * 100) + "%"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize }
                    ToolButton { compact: true; label: "+"; enabled: window.zoom < 3; onActivated: window.zoom = Math.min(3, window.zoom + 0.15) }
                }
            }
        }

        FileDialog {
            id: openDialog; title: "Open PDF"; fileMode: FileDialog.OpenFiles; nameFilters: ["PDF documents (*.pdf)"]
            onAccepted: { var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.replaceWorkspace(p) }
        }
        Menu {
            id: recentMenu
            popupType: Popup.Item
            x: recentButton.mapToItem(window.contentItem, 0, 0).x
            y: toolbar.height
            width: 420
            Instantiator {
                model: window.recents
                delegate: MenuItem {
                    required property string modelData
                    text: modelData
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
            onAccepted: { var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.openPaths(p, false) }
        }
        FileDialog {
            id: saveDialog; title: "Save PDF as"; fileMode: FileDialog.SaveFile; defaultSuffix: "pdf"; nameFilters: ["PDF document (*.pdf)"]
            currentFile: window.suggestedOutput ? window.fileUri(window.suggestedOutput) : ""
            onAccepted: window.saveTo(window.fromUrl(selectedFile))
            onRejected: window.closeAfterExport = false
        }
        SignatureDialog {
            id: signatureDialog; anchors.fill: parent
            onAccepted: strokes => { window.signature = strokes; backend.saveSignature(strokes); window.tool = "sign" }
        }
        CloseDialog {
            id: closeDialog; anchors.fill: parent
            onSaveRequested: { window.closeAfterExport = true; saveDialog.open() }
            onKeepRequested: { window.saveDraftNow(); window.closeWindow() }
            onDiscardRequested: {
                draftTimer.stop()
                if (window.draftKey.length) backend.deleteDraft(window.draftKey)
                window.dirty = false
                window.closeWindow()
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
        Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
        Shortcut { sequence: "Ctrl+Z"; enabled: window.editingAnnotation < 0; onActivated: window.travelHistory(false) }
        Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; enabled: window.editingAnnotation < 0; onActivated: window.travelHistory(true) }
        Shortcut { sequence: "Ctrl+Shift+O"; onActivated: addDialog.open() }
        Shortcut { sequence: "Ctrl+Shift+S"; enabled: pages.count > 0; onActivated: saveDialog.open() }
        Shortcut { sequence: "Ctrl+B"; enabled: pages.count > 0; onActivated: window.toggleBookmark() }
        Shortcut { sequence: "Delete"; enabled: pages.count > 0 && window.editingAnnotation < 0; onActivated: window.deletePage() }
        Shortcut { sequence: "Escape"; enabled: window.editingAnnotation >= 0 || window.tool !== "read" || window.selectedAnnotation >= 0; onActivated: window.cancelCurrentAction() }
        Shortcut { sequence: "Return"; enabled: window.selectedKind === "text" && window.editingAnnotation < 0; onActivated: window.beginTextEdit(window.selectedAnnotation, false) }
        Shortcut { sequence: "Left"; enabled: window.editingAnnotation < 0 && window.currentIndex > 0; onActivated: pageList.currentIndex-- }
        Shortcut { sequence: "Right"; enabled: window.editingAnnotation < 0 && window.currentIndex + 1 < pages.count; onActivated: pageList.currentIndex++ }
        Shortcut { sequence: "Ctrl+Home"; enabled: window.editingAnnotation < 0 && pages.count > 0; onActivated: pageList.currentIndex = 0 }
        Shortcut { sequence: "Ctrl+End"; enabled: window.editingAnnotation < 0 && pages.count > 0; onActivated: pageList.currentIndex = pages.count - 1 }
        Shortcut { sequence: "Ctrl++"; onActivated: window.zoom = Math.min(3, window.zoom + 0.15) }
        Shortcut { sequence: "Ctrl+-"; onActivated: window.zoom = Math.max(0.5, window.zoom - 0.15) }

        Component.onCompleted: {
            backend.getRecents()
            backend.getSignature()
            var raw = Quickshell.env("OMA_PREVIEW_PATHS") || "[]"
            try { var initial = JSON.parse(raw); var clean=[]; for(var i=0;i<initial.length;i++) if(initial[i]) clean.push(initial[i]); openPaths(clean, true) }
            catch(e) { say("Could not read the files passed to Oma Preview.", true) }
            var reviewSpec = Quickshell.env("OMA_PREVIEW_REVIEW_SPEC") || ""
            if (reviewSpec) {
                busy = true
                backend.loadSpec(reviewSpec, Quickshell.env("OMA_PREVIEW_ALLOW_SAVED_SIGNATURE") === "1")
            }
        }
    }
}
