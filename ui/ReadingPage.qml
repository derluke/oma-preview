import QtQuick
import QtQuick.Pdf
import "."

Item {
    id: root
    required property string path
    required property int page
    required property string pageKey
    required property real pageWidth
    required property var marks
    required property var markIndices
    required property var pdfSource
    property bool zooming: false
    property bool fastScrolling: false
    function rasterWidth() { return Math.max(120, Math.round(fastScrolling ? Math.min(240, width) : width)) }
    property var searchHit: null
    readonly property alias annotationItems: markRepeater
    signal clicked(real px, real py)
    Rectangle { anchors.fill: parent; color: "white" }
    PdfRaster {
        id: raster
        anchors.fill: parent; document: root.pdfSource; currentFrame: root.page - 1
        asynchronous: true; fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(root.rasterWidth(), 0)
        // Capture the initial layout once; later zooms use the debounce below.
        Component.onCompleted: sourceSize = Qt.size(root.rasterWidth(), 0)
    }
    Timer { id: quality; interval: 160; onTriggered: raster.sourceSize.width = root.rasterWidth() }
    onWidthChanged: { if (!zooming) quality.restart() }
    onZoomingChanged: { if (zooming) quality.stop(); else quality.restart() }
    onFastScrollingChanged: {
        if (fastScrolling) { quality.stop(); raster.sourceSize.width = rasterWidth() }
        else if (!zooming) quality.restart()
    }
    SearchHighlight { anchors.fill: parent; hit: root.searchHit; pageKey: root.pageKey }
    Repeater {
        id: markRepeater
        model: root.markIndices
        delegate: AnnotationLoader {
            id: mark
            sourceModel: root.marks
            x: nx * root.width; y: ny * root.height
            width: nw * root.width; height: nh * root.height
            sourceComponent: kind === "text" ? textMark : signatureMark
            Component {
                id: textMark
                Text {
                    text: mark.value; color: mark.inkColor; font.family: mark.fontFamily
                    font.pixelSize: Math.round(mark.size * root.width / root.pageWidth)
                    textFormat: Text.PlainText
                }
            }
            Component {
                id: signatureMark
                Canvas {
                    anchors.fill: parent
                    property string strokes: mark.strokeData
                    onStrokesChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        c.strokeStyle = "#111111"; c.lineWidth = Math.max(1.2, root.width / 500)
                        c.lineCap = "round"; c.lineJoin = "round"
                        var lines = JSON.parse(strokes)
                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i]; if (!line.length) continue
                            c.beginPath(); c.moveTo(line[0].x * width, line[0].y * height)
                            for (var j = 1; j < line.length; j++) c.lineTo(line[j].x * width, line[j].y * height)
                            c.stroke()
                        }
                    }
                }
            }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: mouse => root.clicked(mouse.x, mouse.y) }
}
