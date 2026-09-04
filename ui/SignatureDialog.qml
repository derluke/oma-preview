import QtQuick
import "."

Rectangle {
    id: root
    signal accepted(var strokes)
    signal cancelled()
    property var strokes: []
    property var activeStroke: []
    visible: false
    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.82)
    z: 100

    function open() { strokes = []; activeStroke = []; visible = true; pad.requestPaint() }
    function close() { visible = false }

    MouseArea { anchors.fill: parent }
    Rectangle {
        width: Math.min(560, parent.width - 48)
        height: 310
        anchors.centerIn: parent
        color: Theme.chrome
        border.width: 1
        border.color: Theme.hairline
        radius: Theme.radius

        Text {
            anchors.left: parent.left; anchors.top: parent.top
            anchors.margins: 18
            text: "Draw your signature"
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
        }
        Rectangle {
            id: sheet
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.bottom: buttons.top
            anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 52; anchors.bottomMargin: 14
            color: "#fafafa"
            radius: Theme.radius
            clip: true
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; y: parent.height * 0.72; height: 1; color: "#d7d7d7" }
            Canvas {
                id: pad
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d")
                    c.reset(); c.clearRect(0, 0, width, height)
                    c.strokeStyle = "#171717"; c.lineWidth = 2; c.lineCap = "round"; c.lineJoin = "round"
                    var all = root.strokes.slice(); if (root.activeStroke.length) all.push(root.activeStroke)
                    for (var i = 0; i < all.length; i++) {
                        var s = all[i]; if (!s.length) continue
                        c.beginPath(); c.moveTo(s[0].x * width, s[0].y * height)
                        for (var j = 1; j < s.length; j++) c.lineTo(s[j].x * width, s[j].y * height)
                        c.stroke()
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPressed: mouse => { root.activeStroke = [{x:mouse.x / width, y:mouse.y / height}]; pad.requestPaint() }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        var next = root.activeStroke.slice(); next.push({x:mouse.x / width, y:mouse.y / height})
                        root.activeStroke = next; pad.requestPaint()
                    }
                    onReleased: {
                        if (root.activeStroke.length > 1) { var next = root.strokes.slice(); next.push(root.activeStroke); root.strokes = next }
                        root.activeStroke = []; pad.requestPaint()
                    }
                }
            }
        }
        Row {
            id: buttons
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 14
            spacing: Theme.gap
            ToolButton { label: "Clear"; onActivated: { root.strokes = []; root.activeStroke = []; pad.requestPaint() } }
            ToolButton { label: "Cancel"; onActivated: { root.close(); root.cancelled() } }
            ToolButton { label: "Save signature"; enabled: root.strokes.length > 0; chosen: true; onActivated: { root.accepted(root.strokes); root.close() } }
        }
    }
}
