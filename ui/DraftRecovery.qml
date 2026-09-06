import QtQuick
import QtQuick.Controls
import "."

Popup {
    id: root
    property string problem: ""
    property bool working: false
    readonly property alias retryButton: retryButton
    readonly property alias openButton: openButton
    signal retryRequested()
    signal openRequested()
    signal closeRequested()
    width: Math.min(480, parent.width - 32)
    height: Math.min(parent.height - 32, body.implicitHeight + 90)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 20
    modal: true
    dim: true
    focus: true
    popupType: Popup.Item
    closePolicy: Popup.NoAutoClose
    onOpened: retryButton.forceActiveFocus(Qt.TabFocusReason)
    background: Rectangle { color: Theme.chrome; radius: Theme.radius; border.color: Theme.hairline }
    Overlay.modal: Rectangle { color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.82) }
    contentItem: Item {
        Flickable {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.bottom: actions.top; anchors.bottomMargin: 14
            contentHeight: body.implicitHeight
            clip: true
            ScrollBar.vertical: ScrollBar { }
            Column {
                id: body; width: parent.width; spacing: 12
                Text {
                    width: parent.width; text: "Couldn't restore this draft"
                    color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 18
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "Your saved draft is unchanged. Check the file below, then try again."
                    color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width; text: root.problem
                    textFormat: Text.PlainText
                    color: Theme.secondaryText; font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
        Row {
            id: actions
            anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 4
            ToolButton { label: "Close"; enabled: !root.working; onActivated: root.closeRequested() }
            ToolButton { id: openButton; label: "Open another…"; enabled: !root.working; onActivated: root.openRequested() }
            ToolButton { id: retryButton; label: root.working ? "Checking…" : "Try again"; chosen: true; enabled: !root.working; onActivated: root.retryRequested() }
        }
    }
}
