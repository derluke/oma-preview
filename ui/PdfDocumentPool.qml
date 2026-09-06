import QtQuick
import QtQuick.Pdf

Item {
    id: root
    required property var hostWindow
    property int limit: 8
    property var documents: ({})
    property var entries: ({})
    property var idle: []
    // Binding callers must not depend on a QML flag changed inside get().
    property var stats: ({clock:0, allocated:0, retirementFailed:false})
    function get(path, uri) {
        var entry = entries[path]
        if (entry) { entry.used = ++stats.clock; return entry.doc }
        entry = {path:path, uri:uri, used:++stats.clock, refs:0, doc:null}
        var doc = idle.pop()
        // Keep shells parented to the window while cancelled image jobs unwind.
        if (!doc) { doc = factory.createObject(hostWindow); stats.allocated++ }
        entry.doc = doc
        entries[path] = entry; documents[path] = doc
        doc.leaseEntry = entry; doc.source = uri
        if (!stats.retirementFailed && Object.keys(entries).length > limit) trim.start()
        return doc
    }
    function prune() {
        var paths = Object.keys(entries)
        var extra = paths.length - limit
        paths.sort((a,b) => entries[a].used - entries[b].used)
        for (var path of paths) {
            if (extra <= 0) break
            var entry = entries[path]
            if (entry.refs > 0) continue
            delete entries[path]; delete documents[path]
            entry.doc.leaseEntry = null
            // Qt's source-switch path defers old device cleanup to its owning
            // thread. Release parsed resources without destroying the shell.
            entry.doc.source = Qt.resolvedUrl("idle.pdf")
            if (entry.doc.status !== PdfDocument.Ready) {
                entries[path] = entry; documents[path] = entry.doc
                entry.doc.leaseEntry = entry; entry.doc.source = entry.uri
                stats.retirementFailed = true; trim.stop()
                console.warn("Reader cache could not load its idle resource; retaining readers for this session")
                return
            }
            idle.push(entry.doc); extra--
        }
        if (extra <= 0) trim.stop()
    }
    Timer { id: trim; interval: 200; repeat: true; onTriggered: root.prune() }
    Component {
        id: factory
        PdfDocument {
            property bool sourceOnly: false
            property var leaseEntry: null
        }
    }
}
