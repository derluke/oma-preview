import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal inspected(int id, string path, var pages)
    signal recentsLoaded(var paths)
    signal exported(int id, string path)
    signal signatureLoaded(var strokes)
    signal signatureSaved()
    signal bookmarksLoaded(string path, var pages)
    signal reviewLoaded(string output, var pages, var annotations)
    signal draftLoaded(var draft)
    signal draftSaved()
    signal draftDeleted()
    signal failed(string message)
    signal quitReady()

    property int sequence: 0
    property var pending: []
    property bool queueing: true
    property bool quitting: false

    function nextId() { sequence += 1; return sequence }
    function getRecents() { send({c:"recents_get", id:nextId()}) }
    function clearRecents() { send({c:"recents_clear", id:nextId()}) }
    function addRecent(path) { send({c:"recent_add", id:nextId(), path:path}) }
    function send(value) {
        var line = JSON.stringify(value) + "\n"
        if (queueing) { pending.push(line); return }
        if (!child.running) { failed("The document service is not running."); return }
        child.write(line)
    }
    function inspect(path) { var id = nextId(); send({c:"inspect", id:id, path:path}); return id }
    function exportPdf(dest, pages, annotations) { var id = nextId(); send({c:"export", id:id, dest:dest, pages:pages, annotations:annotations}); return id }
    function getSignature() { send({c:"signature_get", id:nextId()}) }
    function saveSignature(strokes) { send({c:"signature_save", id:nextId(), strokes:strokes}) }
    function getBookmarks(path) { send({c:"bookmarks_get", id:nextId(), path:path}) }
    function saveBookmarks(path, pages) { send({c:"bookmarks_save", id:nextId(), path:path, pages:pages}) }
    function loadSpec(path, allowSavedSignature) { send({c:"load_spec", id:nextId(), path:path, allow_saved_signature:allowSavedSignature}) }
    function loadDraft(key) { send({c:"draft_get", id:nextId(), key:key}) }
    function saveDraft(key, draft) { send({c:"draft_save", id:nextId(), key:key, draft:draft}) }
    function deleteDraft(key) { send({c:"draft_delete", id:nextId(), key:key}) }
    function quit() {
        if (quitting) return
        quitting = true
        if (queueing || !child.running) { quitReady(); return }
        send({c:"quit"})
    }
    function receive(line) {
        if (!line) return
        var m
        try { m = JSON.parse(line) } catch (e) { failed("The document service returned an unreadable response."); return }
        if (m.t === "inspected") inspected(m.id, m.path, m.pages || [])
        else if (m.t === "recents") recentsLoaded(m.paths || [])
        else if (m.t === "exported") exported(m.id, m.path)
        else if (m.t === "signature") signatureLoaded(m.strokes || [])
        else if (m.t === "signature_saved") signatureSaved()
        else if (m.t === "bookmarks") bookmarksLoaded(m.path, m.pages || [])
        else if (m.t === "review_loaded") reviewLoaded(m.output || "", m.pages || [], m.annotations || [])
        else if (m.t === "draft_loaded") draftLoaded(m.draft)
        else if (m.t === "draft_saved") draftSaved()
        else if (m.t === "draft_deleted") draftDeleted()
        else if (m.t === "quit_ready") quitReady()
        else if (m.t === "error") failed(m.msg || "The operation failed.")
    }

    Process {
        id: child
        command: [Quickshell.env("OMA_PREVIEW_BIN") || "oma-preview", "--backend"]
        running: true
        stdinEnabled: true
        stdout: SplitParser { splitMarker: "\n"; onRead: data => root.receive(data) }
        onStarted: {
            root.queueing = false
            for (var i = 0; i < root.pending.length; i++) child.write(root.pending[i])
            root.pending = []
        }
        onRunningChanged: if (root.queueing && !child.running) {
            root.queueing = false
            root.pending = []
            root.failed("Oma Preview's document service could not start.")
        }
        onExited: function(code, status) {
            if (root.quitting) root.quitReady()
            else root.failed("Oma Preview's document service stopped unexpectedly.")
        }
    }
}
