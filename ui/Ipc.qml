import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property var folioWindow: null
    property var pages: null
    property var annotations: null
    property var annotationRepeater: null
    property var paper: null
    property var textButton: null
    property var signButton: null

    function centre(item) {
        if (!item || !folioWindow) return ""
        var rect = folioWindow.itemRect(item)
        return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
    }

    property IpcHandler seam: IpcHandler {
        target: "folio"
        function ready(): bool { return root.pages !== null && root.paper !== null }
        function tool(): string { return root.folioWindow ? root.folioWindow.tool : "" }
        function pageCount(): int { return root.pages ? root.pages.count : 0 }
        function currentPage(): int { return root.folioWindow ? root.folioWindow.currentIndex + 1 : 0 }
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
        function pagePoint(x: real, y: real): string {
            if (!root.paper || !root.folioWindow) return ""
            var rect = root.folioWindow.itemRect(root.paper)
            return Math.round(rect.x + rect.width * x) + " " + Math.round(rect.y + rect.height * y)
        }
    }
}
