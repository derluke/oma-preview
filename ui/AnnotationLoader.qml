import QtQuick

Loader {
    required property var sourceModel
    required property int modelData
    readonly property int index: modelData // Public/agent indices stay document-global.
    property int dataRevision: 0
    readonly property var record: {
        var revision = dataRevision
        if (index < 0 || index >= sourceModel.count) return ({})
        var mark = sourceModel.get(index)
        return {pageKey:mark.pageKey, kind:mark.kind, value:mark.value,
                fontFamily:mark.fontFamily, inkColor:mark.inkColor, strokeData:mark.strokeData,
                nx:mark.nx, ny:mark.ny, nw:mark.nw, nh:mark.nh, size:mark.size}
    }
    // ListModel.get() wrappers are not a persistent live-binding contract.
    // Refresh only this visible row when its source values change.
    Connections {
        target: sourceModel
        function onDataChanged(first, last) {
            if (index >= first.row && index <= last.row) dataRevision++
        }
        function onRowsMoved() { dataRevision++ }
    }
    readonly property string pageKey: record.pageKey || ""
    readonly property string kind: record.kind || "text"
    readonly property string value: record.value || ""
    readonly property string fontFamily: record.fontFamily || "sans-serif"
    readonly property string inkColor: record.inkColor || "#111111"
    readonly property string strokeData: record.strokeData || "[]"
    readonly property real nx: record.nx || 0
    readonly property real ny: record.ny || 0
    readonly property real nw: record.nw || 0
    readonly property real nh: record.nh || 0
    readonly property real size: record.size || 14
}
