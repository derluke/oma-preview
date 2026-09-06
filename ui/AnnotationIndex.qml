import QtQuick

// Page membership changes rarely; text and geometry change on every keystroke
// or drag. Keep those updates from rebuilding the active editor's delegates.
Item {
    id: root
    required property var sourceModel
    property var byPage: Object.create(null)
    property var pageKeys: []
    property bool resetPending: true
    readonly property var empty: []
    visible: false

    function forPage(key) { return byPage[key] || empty }
    function flush() {
        if (!refresh.running) return
        refresh.stop()
        rebuild()
    }
    function rebuild() {
        var next = Object.create(null), keys = []
        for (var i = 0; i < sourceModel.count; i++) {
            var key = sourceModel.get(i).pageKey
            keys.push(key)
            if (!next[key]) next[key] = []
            next[key].push(i)
        }
        for (var page in next) {
            var old = byPage[page], indices = next[page]
            if (!resetPending && old && old.length === indices.length && old.every((v, i) => v === indices[i])) next[page] = old
        }
        pageKeys = keys
        byPage = next
        resetPending = false
    }
    onSourceModelChanged: { resetPending = true; refresh.restart() }
    Timer { id: refresh; interval: 0; onTriggered: root.rebuild() }
    Connections {
        target: root.sourceModel
        function onRowsInserted() { refresh.restart() }
        function onRowsRemoved() { if (!root.sourceModel.count) root.resetPending = true; refresh.restart() }
        function onRowsMoved() { refresh.restart() }
        function onModelReset() { root.resetPending = true; refresh.restart() }
        function onDataChanged(first, last) {
            if (refresh.running) return
            for (var row = first.row; row <= last.row; row++) {
                if (root.pageKeys[row] !== root.sourceModel.get(row).pageKey) { refresh.restart(); return }
            }
        }
    }
    Component.onCompleted: refresh.restart()
}
