import QtQuick
import "."

Item {
    id: root
    property var cancelButton: cancelButton
    property var discardButton: discardButton
    visible: false
    z: 1000
    signal saveRequested()
    signal keepRequested()
    signal discardRequested()

    function open() { visible = true }
    function close() { visible = false }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.82)
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        width: Math.min(440, parent.width - 40); height: 176
        anchors.centerIn: parent
        radius: Theme.radius
        color: Theme.chrome
        border.width: 1; border.color: Theme.hairline

        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 22
            text: "Keep your changes?"
            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 18
        }
        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: 22; anchors.rightMargin: 22; anchors.topMargin: 58
            wrapMode: Text.WordWrap
            text: "Your draft is already safe. Save a PDF now, keep the draft for later, or discard these edits."
            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 18
            spacing: 4
            ToolButton { id: cancelButton; label: "Cancel"; onActivated: root.close() }
            ToolButton { id: discardButton; label: "Discard"; danger: true; onActivated: { root.close(); root.discardRequested() } }
            ToolButton { label: "Keep draft"; chosen: true; onActivated: { root.close(); root.keepRequested() } }
            ToolButton { label: "Save PDF…"; onActivated: { root.close(); root.saveRequested() } }
        }
    }

    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.close() }
}
