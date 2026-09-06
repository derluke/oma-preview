import QtQuick
import QtQuick.Controls
import "."

AbstractButton {
    id: root
    signal activated()
    property string label: ""
    property bool chosen: false
    property bool compact: false
    property bool danger: false
    property color labelColor: danger ? Theme.urgent : Theme.foreground
    property real labelSize: Theme.textSize
    property string accessibleName: label
    readonly property bool reservesReadingKeys: true
    implicitWidth: compact ? 32 : Math.max(48, caption.implicitWidth + 20)
    implicitHeight: 32
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    Accessible.name: accessibleName
    Accessible.role: Accessible.Button
    onClicked: activated()
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) activated(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) activated(); event.accepted = true }
    opacity: enabled ? 1 : 0.36
    background: Rectangle {
        radius: Theme.radius
        color: !root.enabled ? "transparent" : root.chosen || root.down ? Theme.selected : root.hovered ? Theme.hover : "transparent"
        border.width: root.visualFocus ? 2 : root.chosen ? 1 : 0
        border.color: Theme.accent
    }
    contentItem: Text {
        id: caption
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.label
        color: root.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: root.labelSize
    }
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
