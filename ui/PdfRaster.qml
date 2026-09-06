import QtQuick
import QtQuick.Window
import QtQuick.Pdf

// Qt's shared-document PdfPageImage path can miss the initial device scale.
// Use the standard scalable-image path on high-DPI windows, where Qt applies
// devicePixelRatio itself. Do not multiply sourceSize a second time.
Item {
    id: root
    property var document: null
    property var leaseEntry: null
    function updateLease() {
        var next = document ? document.leaseEntry : null
        if (next === leaseEntry) return
        if (leaseEntry) leaseEntry.refs--
        leaseEntry = next || null
        if (leaseEntry) leaseEntry.refs++
    }
    onDocumentChanged: updateLease()
    Component.onCompleted: { updateLease(); initialized = true }
    Component.onDestruction: { if (leaseEntry) leaseEntry.refs--; leaseEntry = null }
    property int currentFrame: 0
    property bool initialized: false
    function reloadPage() {
        if (!initialized) return
        // Retaining a raster is useful during zoom, but never across page
        // identities: the selected paper moves to a new position immediately.
        // Give each page/source its own image item so an old page cannot ride
        // along with that paper while an asynchronous request catches up.
        imageLoader.active = false
        imageLoader.active = Qt.binding(() => root.document !== null && root.document !== undefined)
    }
    onCurrentFrameChanged: reloadPage()
    onSourceChanged: reloadPage()
    property size sourceSize: Qt.size(0, 0)
    property bool asynchronous: true
    property int fillMode: Image.PreserveAspectFit
    readonly property url source: document ? document.source : ""
    readonly property real displayScale: Window.window ? Window.window.devicePixelRatio : 1
    readonly property int status: imageLoader.item ? imageLoader.item.status : Image.Null
    implicitWidth: imageLoader.item ? imageLoader.item.implicitWidth : 0
    implicitHeight: imageLoader.item ? imageLoader.item.implicitHeight : 0
    Loader {
        id: imageLoader
        active: root.document !== null && root.document !== undefined
        anchors.fill: parent
        // Keep source-only descriptors on the independent path while a screen
        // scale transition updates the window's delayed document binding.
        sourceComponent: root.displayScale > 1 || (root.document && root.document.sourceOnly === true) ? scaledImage : sharedImage
    }
    Component {
        id: sharedImage
        PdfPageImage {
            document: root.document
            currentFrame: root.currentFrame
            sourceSize: Qt.size(Math.max(0, root.sourceSize.width), Math.max(0, root.sourceSize.height))
            asynchronous: root.asynchronous
            fillMode: root.fillMode
        }
    }
    Component {
        id: scaledImage
        Image {
            source: root.source
            currentFrame: root.currentFrame
            sourceSize: Qt.size(Math.max(0, root.sourceSize.width), Math.max(0, root.sourceSize.height))
            asynchronous: root.asynchronous
            fillMode: root.fillMode
            retainWhileLoading: true
        }
    }
}
