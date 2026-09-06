import QtQuick
import QtQuick.Controls
import "."

Popup {
    id: root
    property int pageCount: 0
    property int currentPage: 1
    readonly property alias field: pageNumber
    readonly property alias goButton: goButton
    readonly property bool validPage: /^\d+$/.test(pageNumber.text) && Number(pageNumber.text) >= 1 && Number(pageNumber.text) <= pageCount
    signal pageChosen(int page)
    width: Math.min(300, parent.width - 32)
    height: 160
    x: (parent.width - width) / 2
    y: Math.max(16, (parent.height - height) / 3)
    padding: 16
    modal: true
    dim: false
    focus: true
    popupType: Popup.Item
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: Theme.chrome; radius: Theme.radius; border.color: Theme.hairline }
    function submit() {
        if (!validPage) return
        var chosen = Number(pageNumber.text)
        close()
        pageChosen(chosen)
    }
    onOpened: { pageNumber.text = String(currentPage); pageNumber.forceActiveFocus(); pageNumber.selectAll() }
    contentItem: Item {
        Text {
            text: "Go to page"
            color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 16
        }
        TextField {
            id: pageNumber
            anchors.left: parent.left; anchors.right: parent.right
            y: 30; height: 34
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
            selectionColor: Theme.selected; selectedTextColor: Theme.foreground
            inputMethodHints: Qt.ImhDigitsOnly
            Accessible.name: "Page number"
            background: Rectangle { color: Theme.background; radius: Theme.radius; border.color: pageNumber.activeFocus ? Theme.accent : Theme.hairline }
            onAccepted: root.submit()
        }
        Text {
            y: 70
            text: "1–" + root.pageCount
            color: pageNumber.text.length && !root.validPage ? Theme.urgent : Theme.secondaryText
            font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 4
            ToolButton { label: "Cancel"; onActivated: root.close() }
            ToolButton { id: goButton; label: "Go"; chosen: true; enabled: root.validPage; onActivated: root.submit() }
        }
    }
}
