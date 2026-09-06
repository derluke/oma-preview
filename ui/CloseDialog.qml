import QtQuick
import QtQuick.Controls
import "."

Popup {
    id: root
    property var cancelButton: cancelButton
    property var discardButton: discardButton
    signal discardRequested()
    width: Math.min(440, parent.width - 40)
    height: 176
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 0
    modal: true
    dim: true
    focus: true
    popupType: Popup.Item
    closePolicy: Popup.CloseOnEscape
    onOpened: cancelButton.forceActiveFocus(Qt.TabFocusReason)
    background: Rectangle { radius: Theme.radius; color: Theme.chrome; border.color: Theme.hairline }
    Overlay.modal: Rectangle { color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.82) }
    contentItem: Item {

        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 22
            text: "Discard draft and close?"
            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 18
        }
        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: 22; anchors.rightMargin: 22; anchors.topMargin: 58
            wrapMode: Text.WordWrap
            text: "This removes the saved edits and undo history. Original and exported PDFs are kept."
            color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 18
            spacing: 4
            ToolButton { id: cancelButton; label: "Cancel"; chosen: true; onActivated: root.close() }
            ToolButton { id: discardButton; label: "Discard and close"; danger: true; onActivated: { root.close(); root.discardRequested() } }
        }
    }

}
