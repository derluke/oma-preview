//@ pragma AppId org.omarchy.folio
//@ pragma ShellId folio
//@ pragma NativeTextRendering
//@ pragma DefaultEnv QSG_RHI_BACKEND=vulkan

import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Pdf
import "."

ShellRoot {
    id: shell

    FloatingWindow {
        id: window
        title: currentIndex >= 0 ? "Folio — " + fileName(currentPage.path) : "Folio"
        implicitWidth: 1040
        implicitHeight: 720

        property int currentIndex: pages.count > 0 ? Math.min(pageList.currentIndex < 0 ? 0 : pageList.currentIndex, pages.count - 1) : -1
        property var currentPage: currentIndex >= 0 ? pages.get(currentIndex) : ({path:"", page:1, width:595, height:842, key:""})
        property string tool: "read"
        property real zoom: 1.0
        property int serial: 0
        property int selectedAnnotation: -1
        property int editingAnnotation: -1
        property var signature: []
        property var bookmarks: ({})
        property string statusText: ""
        property bool statusError: false
        property bool busy: false
        property string suggestedOutput: ""

        function fileName(path) {
            var parts = String(path || "").split("/")
            return parts.length ? parts[parts.length - 1] : ""
        }
        function centreOf(item) {
            if (!item) return ""
            var rect = window.itemRect(item)
            return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
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
        function openPaths(paths) {
            if (!paths || paths.length === 0) return
            busy = true
            for (var i = 0; i < paths.length; i++) {
                if (String(paths[i]).length) backend.inspect(String(paths[i]))
            }
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
                if (a.kind === "text") out.push({kind:"text", page_key:a.pageKey, x:a.nx, y:a.ny, text:a.value, size:a.size})
                else out.push({kind:"signature", page_key:a.pageKey, x:a.nx, y:a.ny, width:a.nw, height:a.nh, strokes:JSON.parse(a.strokeData || "[]")})
            }
            return out
        }
        function saveTo(path) {
            if (!path.toLowerCase().endsWith(".pdf")) path += ".pdf"
            busy = true
            backend.exportPdf(path, pagePayload(), annotationPayload())
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
            pages.move(currentIndex, to, 1); pageList.currentIndex = to
        }
        function deletePage() {
            if (selectedAnnotation >= 0) { annotations.remove(selectedAnnotation); selectedAnnotation = -1; return }
            if (currentIndex < 0 || pages.count <= 1) return
            var old = currentIndex; pages.remove(old); pageList.currentIndex = Math.min(old, pages.count - 1)
        }

        Connections { target: Quickshell; function onLastWindowClosed() { backend.quit() } }
        Connections { target: backend
            function onQuitReady() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
            function onInspected(id, path, found) {
                for (var i = 0; i < found.length; i++) {
                    window.serial += 1
                    pages.append({path:path, page:found[i].page, width:found[i].width, height:found[i].height,
                                  key:path + "#" + found[i].page + "#" + window.serial})
                }
                if (pageList.currentIndex < 0 && pages.count) pageList.currentIndex = 0
                backend.getBookmarks(path)
                window.busy = false
                window.say("Added " + found.length + (found.length === 1 ? " page" : " pages"), false)
            }
            function onExported(id, path) { window.busy = false; window.say("Saved " + window.fileName(path), false) }
            function onSignatureLoaded(strokes) { window.signature = strokes }
            function onSignatureSaved() { window.say("Signature saved for next time", false) }
            function onBookmarksLoaded(path, found) {
                var all = Object.assign({}, window.bookmarks); all[path] = found; window.bookmarks = all
            }
            function onReviewLoaded(output, proposedPages, proposedAnnotations) {
                pages.clear(); annotations.clear(); window.suggestedOutput = output
                for (var i = 0; i < proposedPages.length; i++) {
                    var p = proposedPages[i]
                    pages.append({path:p.path, page:p.page, width:p.width, height:p.height, key:p.key})
                    backend.getBookmarks(p.path)
                }
                for (var j = 0; j < proposedAnnotations.length; j++) {
                    var a = proposedAnnotations[j]
                    if (a.kind === "text") {
                        annotations.append({kind:"text", pageKey:a.page_key, nx:a.x, ny:a.y, value:a.text, size:a.size, nw:0, nh:0, strokeData:"[]"})
                    } else if (a.kind === "signature") {
                        annotations.append({kind:"signature", pageKey:a.page_key, nx:a.x, ny:a.y, value:"", size:0, nw:a.width, nh:a.height, strokeData:JSON.stringify(a.strokes || [])})
                    }
                }
                pageList.currentIndex = pages.count ? 0 : -1
                window.busy = false
                window.say("Agent proposal loaded — review and adjust before saving", false)
            }
            function onFailed(message) { window.busy = false; window.say(message, true) }
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
                    ToolButton { label: "Add PDF"; onActivated: addDialog.open() }
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

                Column {
                    anchors.centerIn: parent; spacing: 14; visible: pages.count === 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Folio"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 28 }
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

                        Repeater {
                            id: annotationRepeater
                            model: annotations
                            delegate: Loader {
                                id: markLoader
                                required property int index
                                required property string pageKey
                                required property string kind
                                required property real nx
                                required property real ny
                                required property string value
                                required property real size
                                required property real nw
                                required property real nh
                                required property string strokeData
                                active: pageKey === window.currentPage.key
                                sourceComponent: kind === "text" ? textMark : signatureMark
                                Component {
                                    id: textMark
                                    TextInput {
                                        x: markLoader.nx * paper.width; y: markLoader.ny * paper.height
                                        width: Math.max(80, implicitWidth + 8); height: Math.max(24, implicitHeight + 4)
                                        text: markLoader.value; color: "#111111"
                                        font.family: "sans-serif"; font.pixelSize: markLoader.size * paper.width / window.currentPage.width
                                        selectionColor: Theme.accent
                                        onAccepted: {
                                            annotations.setProperty(markLoader.index, "value", text)
                                            window.editingAnnotation = -1
                                            window.tool = "read"
                                            focus = false
                                            window.say("Text placed — double-click it to edit again", false)
                                        }
                                        onActiveFocusChanged: if (!activeFocus) {
                                            annotations.setProperty(markLoader.index, "value", text)
                                            if (window.editingAnnotation === markLoader.index) {
                                                window.editingAnnotation = -1
                                                window.tool = "read"
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; acceptedButtons: Qt.LeftButton
                                            enabled: !parent.activeFocus
                                            drag.target: parent; cursorShape: Qt.SizeAllCursor
                                            onPressed: { window.selectedAnnotation = markLoader.index }
                                            onDoubleClicked: parent.forceActiveFocus()
                                            onReleased: {
                                                annotations.setProperty(markLoader.index, "nx", parent.x / paper.width)
                                                annotations.setProperty(markLoader.index, "ny", parent.y / paper.height)
                                            }
                                        }
                                        Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; border.width: window.selectedAnnotation === markLoader.index ? 1 : 0; border.color: Theme.accent }
                                    }
                                }
                                Component {
                                    id: signatureMark
                                    Item {
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
                                            anchors.fill: parent; drag.target: parent; cursorShape: Qt.SizeAllCursor
                                            onPressed: window.selectedAnnotation = markLoader.index
                                            onReleased: {
                                                annotations.setProperty(markLoader.index, "nx", parent.x / paper.width)
                                                annotations.setProperty(markLoader.index, "ny", parent.y / paper.height)
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
                                    annotations.append({kind:"text", pageKey:window.currentPage.key, nx:mouse.x/paper.width, ny:mouse.y/paper.height, value:"Text", size:14, nw:0, nh:0, strokeData:"[]"})
                                    window.selectedAnnotation = annotations.count - 1
                                    window.say("Type the text, then press Enter", false)
                                    var textIndex = annotations.count - 1
                                    window.editingAnnotation = textIndex
                                    Qt.callLater(function() {
                                        var loader = annotationRepeater.itemAt(textIndex)
                                        if (loader && loader.item) {
                                            loader.item.forceActiveFocus()
                                            loader.item.selectAll()
                                        }
                                    })
                                } else if (window.signature.length > 0) {
                                    annotations.append({kind:"signature", pageKey:window.currentPage.key, nx:Math.min(0.74,mouse.x/paper.width), ny:Math.min(0.88,mouse.y/paper.height), value:"", size:0, nw:0.24, nh:0.09, strokeData:JSON.stringify(window.signature)})
                                    window.selectedAnnotation = annotations.count - 1
                                    window.tool = "read"
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
            onAccepted: { pages.clear(); annotations.clear(); pageList.currentIndex = -1; var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.openPaths(p) }
        }
        FileDialog {
            id: addDialog; title: "Add PDF"; fileMode: FileDialog.OpenFiles; nameFilters: ["PDF documents (*.pdf)"]
            onAccepted: { var p=[]; for(var i=0;i<selectedFiles.length;i++) p.push(window.fromUrl(selectedFiles[i])); window.openPaths(p) }
        }
        FileDialog {
            id: saveDialog; title: "Save PDF as"; fileMode: FileDialog.SaveFile; defaultSuffix: "pdf"; nameFilters: ["PDF document (*.pdf)"]
            currentFile: window.suggestedOutput ? window.fileUri(window.suggestedOutput) : ""
            onAccepted: window.saveTo(window.fromUrl(selectedFile))
        }
        SignatureDialog {
            id: signatureDialog; anchors.fill: parent
            onAccepted: strokes => { window.signature = strokes; backend.saveSignature(strokes); window.tool = "sign" }
        }
        Ipc {
            folioWindow: window
            pages: pages
            annotations: annotations
            annotationRepeater: annotationRepeater
            paper: paper
            textButton: textButton
            signButton: signButton
        }
        Timer { id: statusTimer; interval: 4500; onTriggered: window.statusText = "" }
        Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
        Shortcut { sequence: "Ctrl+Shift+O"; onActivated: addDialog.open() }
        Shortcut { sequence: "Ctrl+Shift+S"; enabled: pages.count > 0; onActivated: saveDialog.open() }
        Shortcut { sequence: "Ctrl+B"; enabled: pages.count > 0; onActivated: window.toggleBookmark() }
        Shortcut { sequence: "Delete"; enabled: pages.count > 0; onActivated: window.deletePage() }
        Shortcut { sequence: "Left"; enabled: window.currentIndex > 0; onActivated: pageList.currentIndex-- }
        Shortcut { sequence: "Right"; enabled: window.currentIndex + 1 < pages.count; onActivated: pageList.currentIndex++ }
        Shortcut { sequence: "Ctrl++"; onActivated: window.zoom = Math.min(3, window.zoom + 0.15) }
        Shortcut { sequence: "Ctrl+-"; onActivated: window.zoom = Math.max(0.5, window.zoom - 0.15) }

        Component.onCompleted: {
            backend.getSignature()
            var raw = Quickshell.env("FOLIO_PATHS") || "[]"
            try { var initial = JSON.parse(raw); var clean=[]; for(var i=0;i<initial.length;i++) if(initial[i]) clean.push(initial[i]); openPaths(clean) }
            catch(e) { say("Could not read the files passed to Folio.", true) }
            var reviewSpec = Quickshell.env("FOLIO_REVIEW_SPEC") || ""
            if (reviewSpec) {
                busy = true
                backend.loadSpec(reviewSpec, Quickshell.env("FOLIO_ALLOW_SAVED_SIGNATURE") === "1")
            }
        }
    }
}
