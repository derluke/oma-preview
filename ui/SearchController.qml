import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var previewWindow
    property bool active: false
    property bool mayNavigate: false
    property string query: ""
    property bool searching: false
    property string error: ""
    property bool truncated: false
    property int completed: 0
    property int total: 0
    property var results: []
    property int current: -1
    readonly property var hit: current >= 0 && current < results.length ? results[current] : null
    property int generation: 0
    property var job: null
    property var pageResults: []
    property var pageSnapshot: []
    property int anchor: 0
    property bool autoPending: false
    signal chosen(var match)

    function cancel() {
        generation++
        debounce.stop(); publish.stop(); watchdog.stop()
        var old = job; job = null
        if (old) old.running = false
        pageSnapshot = []; autoPending = false
        searching = false
    }
    function restart() {
        cancel()
        results = []; current = -1; pageResults = []; error = ""; truncated = false
        completed = 0; total = 0
        if (active && query.trim().length && previewWindow.interactionReady) {
            searching = true; debounce.restart()
        }
    }
    function begin() {
        if (!active || !previewWindow.interactionReady || !query.trim().length) return
        pageSnapshot = previewWindow.pagePayload()
        total = pageSnapshot.length; anchor = Math.max(0, previewWindow.currentIndex); autoPending = true
        if (!total) { searching = false; return }
        job = worker.createObject(root, {epoch:generation,
            request:JSON.stringify({query:query, start_index:anchor, pages:pageSnapshot.map(p => ({path:p.path,page:p.page,key:p.key}))})})
        job.running = true
        watchdog.restart()
    }
    function fail(epoch, message) {
        if (epoch !== generation || !active) return
        cancel(); results = []; current = -1; pageResults = []
        error = message || "Search could not read this PDF."
    }
    function receive(epoch, line) {
        if (epoch !== generation || !active) return
        try {
            var message = JSON.parse(line)
            if (message.t === "search_page") {
                var index = message.page_index, page = pageSnapshot[index]
                if (!Number.isInteger(index) || index < 0 || !page || page.key !== message.page_key || !Array.isArray(message.matches)
                    || !message.matches.every(match => Array.isArray(match.rects) && match.rects.length > 0
                        && match.rects.every(r => r && [r.x, r.y, r.width, r.height].every(v => typeof v === "number" && isFinite(v) && v >= 0 && v <= 1))))
                    throw new Error("Invalid search page")
                pageResults[index] = message.matches.map((match, i) => ({id:page.key + ":" + i, pageKey:page.key,
                    pageIndex:index, rects:match.rects}))
                completed = message.completed
                if (!publish.running) publish.start()
            } else if (message.t === "search_done") {
                if (job) job.complete = true
                truncated = message.truncated === true
                completed = message.completed
                searching = false; watchdog.stop(); publish.stop(); publishResults()
            } else throw new Error("Unknown search response")
        } catch (e) { fail(epoch, "Search returned an unreadable response.") }
    }
    function publishResults() {
        var previous = hit ? hit.id : "", next = []
        for (var page of pageResults) if (page) for (var match of page) next.push(match)
        results = next
        current = previous ? next.findIndex(match => match.id === previous) : -1
        if (autoPending && mayNavigate && next.length) {
            var first = next.findIndex(match => match.pageIndex >= anchor)
            if (first < 0) first = 0
            if (first >= 0) {
                // A later source can finish first. Don't skip an unsearched
                // page, including across the end-to-start wraparound.
                var distance = (next[first].pageIndex + total - anchor) % total
                for (var offset = 0; searching && offset < distance; offset++)
                    if (pageResults[(anchor + offset) % total] === undefined) return
                current = first; autoPending = false; chosen(hit)
            }
        }
    }
    function step(direction) {
        if (active && previewWindow.interactionReady && !previewWindow.modalActive && error) {
            restart(); debounce.stop(); begin(); return
        }
        if (!results.length || !previewWindow.interactionReady || previewWindow.modalActive || previewWindow.editingAnnotation >= 0) return
        autoPending = false
        current = current < 0 ? (direction > 0 ? 0 : results.length - 1)
                             : (current + direction + results.length) % results.length
        chosen(hit)
    }
    onQueryChanged: restart()
    onActiveChanged: restart()
    Connections {
        target: root.previewWindow
        function onPageSnapshotRevisionChanged() { if (root.active) root.restart() }
        function onInteractionReadyChanged() { if (root.active) root.restart() }
    }
    Timer { id: debounce; interval: 180; onTriggered: root.begin() }
    Timer { id: publish; interval: 16; onTriggered: root.publishResults() }
    Timer { id: watchdog; interval: 300000; onTriggered: root.fail(root.generation, "Search took too long. Try a narrower query.") }
    Component {
        id: worker
        Process {
            id: process
            property int epoch: -1
            property string request: ""
            property string detail: ""
            property bool started: false
            property bool complete: false
            property bool retiring: false
            function retire() {
                if (retiring) return
                retiring = true
                Qt.callLater(function() { process.destroy() })
            }
            command: [Quickshell.env("OMA_PREVIEW_BIN") || "oma-preview", "--search-worker"]
            stdinEnabled: true
            onStarted: { started = true; write(request + "\n") }
            stdout: SplitParser { splitMarker: "\n"; onRead: data => root.receive(process.epoch, data) }
            stderr: SplitParser { splitMarker: "\n"; onRead: data => { if (process.detail.length < 512) process.detail += data.slice(0, 512 - process.detail.length) } }
            onRunningChanged: if (!running && !started) Qt.callLater(function() {
                root.fail(epoch, "The search service could not start.")
                retire()
            })
            onExited: (code, status) => {
                if (epoch === root.generation && (!complete || code !== 0)) root.fail(epoch, detail || "Search stopped unexpectedly.")
                if (root.job === process) root.job = null
                retire()
            }
        }
    }
}
