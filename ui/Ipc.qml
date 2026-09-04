import QtQuick
import Quickshell
import Quickshell.Io
import "."

QtObject {
    id: root
    property var previewWindow: null
    property var pages: null
    property var annotations: null
    property var annotationRepeater: null
    property var paper: null
    property var textButton: null
    property var signButton: null
    property var formatSizeUp: null
    property var formatFont: null
    property var inkBlue: null
    property var formatEdit: null
    property var formatDelete: null
    property var closeDialog: null
    property var backend: null
    property var renderedPage: null
    property var recentButton: null
    property var recentMenu: null

    function centre(item) {
        if (!item || !previewWindow) return ""
        var rect = previewWindow.itemRect(item)
        return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
    }

    property IpcHandler seam: IpcHandler {
        target: "oma-preview"
        function ready(): bool { return root.pages !== null && root.paper !== null }
        function renderState(): string {
            return JSON.stringify({ready:root.renderedPage && root.renderedPage.status === Image.Ready,
                frame:root.renderedPage ? root.renderedPage.currentFrame : -1,
                milliseconds:root.renderedPage ? root.renderedPage.lastRenderMs : 0})
        }
        function recentButtonCentre(): string { return root.centre(root.recentButton) }
        function recentItemCentre(index: int): string { return root.centre(root.recentMenu.itemAt(index)) }
        function loadReview(path: string, allowSavedSignature: bool): bool {
            if (!root.previewWindow || !root.backend) return false
            return root.previewWindow.applyLiveReview(path, allowSavedSignature)
        }
        function state(): string {
            if (!root.previewWindow) return JSON.stringify({ready:false})
            var w = root.previewWindow
            return JSON.stringify({ready:true, busy:w.busy, revision:w.reviewRevision,
                error:w.reviewError, dirty:w.dirty, editing:w.editingAnnotation >= 0,
                can_undo:w.undoStack.length > 0, can_redo:w.redoStack.length > 0,
                pid:Number(Quickshell.processId), active:w.active, modal:w.modalActive, dialog:w.activeDialog,
                selected_annotation:w.selectedAnnotation, tool:w.tool, zoom:w.zoom,
                current_page:w.currentIndex + 1, output:w.suggestedOutput,
                pages:w.pagePayload(), annotations:w.annotationPayload()})
        }
        function tool(): string { return root.previewWindow ? root.previewWindow.tool : "" }
        function pageCount(): int { return root.pages ? root.pages.count : 0 }
        function currentPage(): int { return root.previewWindow ? root.previewWindow.currentIndex + 1 : 0 }
        function zoom(): real { return root.previewWindow ? root.previewWindow.zoom : 0 }
        function themeBackground(): string { return String(Theme.background) }
        function themeForeground(): string { return String(Theme.foreground) }
        function themeAccent(): string { return String(Theme.accent) }
        function draftRestored(): bool { return root.previewWindow ? root.previewWindow.draftRestored : false }
        function draftNoticeVisible(): bool { return root.previewWindow ? root.previewWindow.draftNoticeVisible : false }
        function dirty(): bool { return root.previewWindow ? root.previewWindow.dirty : false }
        function recentPaths(): string { return JSON.stringify(root.previewWindow.recents) }
        function bookmarked(): bool { return root.previewWindow.isBookmarked() }
        function statusText(): string { return root.previewWindow ? root.previewWindow.statusText : "" }
        function closePromptVisible(): bool { return root.closeDialog ? root.closeDialog.visible : false }
        function closeCancelCentre(): string { return root.closeDialog ? root.centre(root.closeDialog.cancelButton) : "" }
        function requestClose(): bool {
            if (!root.previewWindow) return false
            root.previewWindow.close()
            return true
        }
        function annotationCount(): int { return root.annotations ? root.annotations.count : 0 }
        function annotationKinds(): string {
            var kinds = []
            if (root.annotations) for (var i = 0; i < root.annotations.count; i++) kinds.push(root.annotations.get(i).kind)
            return kinds.join(",")
        }
        function annotationText(index: int): string {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return ""
            var mark = root.annotations.get(index)
            return mark.kind === "text" ? mark.value : ""
        }
        function annotationSize(index: int): real {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return -1
            return root.annotations.get(index).size
        }
        function annotationWidth(index: int): real {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return -1
            return root.annotations.get(index).nw
        }
        function annotationFont(index: int): string {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return ""
            return root.annotations.get(index).fontFamily
        }
        function annotationColor(index: int): string {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return ""
            return root.annotations.get(index).inkColor
        }
        function selectedAnnotation(): int { return root.previewWindow ? root.previewWindow.selectedAnnotation : -1 }
        function annotationPosition(index: int): string {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return ""
            var mark = root.annotations.get(index)
            return mark.nx.toFixed(4) + " " + mark.ny.toFixed(4)
        }
        function annotationPoint(index: int): string {
            if (!root.annotations || !root.paper || !root.previewWindow || index < 0 || index >= root.annotations.count) return ""
            var mark = root.annotations.get(index)
            var rect = root.previewWindow.itemRect(root.paper)
            return Math.round(rect.x + rect.width * mark.nx + 6) + " " + Math.round(rect.y + rect.height * mark.ny + 6)
        }
        function annotationResizePoint(index: int): string {
            if (!root.annotationRepeater || index < 0) return ""
            var loader = root.annotationRepeater.itemAt(index)
            if (!loader || !loader.item || !loader.item.resizeHandle) return ""
            return root.centre(loader.item.resizeHandle)
        }
        function editingText(index: int): bool {
            if (!root.annotationRepeater || index < 0) return false
            var loader = root.annotationRepeater.itemAt(index)
            return loader && loader.item ? loader.item.activeFocus : false
        }
        function annotationStrokeCount(index: int): int {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return -1
            var mark = root.annotations.get(index)
            if (mark.kind !== "signature") return -1
            try { return JSON.parse(mark.strokeData || "[]").length } catch (e) { return -1 }
        }
        function annotationFirstPoint(index: int): string {
            if (!root.annotations || index < 0 || index >= root.annotations.count) return ""
            var mark = root.annotations.get(index)
            if (mark.kind !== "signature") return ""
            try {
                var strokes = JSON.parse(mark.strokeData || "[]")
                return strokes.length && strokes[0].length ? JSON.stringify(strokes[0][0]) : ""
            } catch (e) { return "" }
        }
        function textButtonCentre(): string { return root.centre(root.textButton) }
        function signButtonCentre(): string { return root.centre(root.signButton) }
        function sizeUpCentre(): string { return root.centre(root.formatSizeUp) }
        function fontButtonCentre(): string { return root.centre(root.formatFont) }
        function blueButtonCentre(): string { return root.centre(root.inkBlue) }
        function editButtonCentre(): string { return root.centre(root.formatEdit) }
        function deleteButtonCentre(): string { return root.centre(root.formatDelete) }
        function pagePoint(x: real, y: real): string {
            if (!root.paper || !root.previewWindow) return ""
            var rect = root.previewWindow.itemRect(root.paper)
            return Math.round(rect.x + rect.width * x) + " " + Math.round(rect.y + rect.height * y)
        }
    }
}
