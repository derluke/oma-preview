import QtQuick
import "."

Rectangle {
    id: root
    signal activated()
    property string label: ""
    property bool chosen: false
    property bool compact: false
    property bool danger: false
    property color labelColor: danger ? Theme.urgent : Theme.foreground
    implicitWidth: compact ? 32 : Math.max(48, text.implicitWidth + 20)
    implicitHeight: 30
    radius: Theme.radius
    color: !enabled ? "transparent" : chosen ? Theme.selected : tap.containsMouse ? Theme.hover : "transparent"
    border.width: chosen ? 1 : 0
    border.color: Theme.accent
    opacity: enabled ? 1 : 0.36

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.smallSize
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
