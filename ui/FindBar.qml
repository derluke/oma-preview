import QtQuick
import QtQuick.Controls
import "."

Rectangle {
    id: root
    required property var search
    property bool opened: false
    readonly property alias field: input
    readonly property alias nextButton: next
    readonly property alias previousButton: previous
    readonly property alias closeButton: close
    readonly property bool hasFocus: input.activeFocus || next.activeFocus || previous.activeFocus || close.activeFocus
    signal dismissed()
    visible: opened
    implicitWidth: 470; implicitHeight: 48
    color: Theme.chrome; radius: Theme.radius
    border.color: Theme.hairline
    function open() { opened = true; input.forceActiveFocus(); input.selectAll() }
    function dismiss() { opened = false; dismissed() }
    TextField {
        id: input
        readonly property bool reservesReadingKeys: true
        anchors.left: parent.left; anchors.leftMargin: 8
        anchors.right: resultCount.left; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        maximumLength: 512
        placeholderText: "Find in PDF"
        Accessible.name: "Find in PDF"
        color: Theme.foreground; placeholderTextColor: Theme.secondaryText
        font.family: Theme.fontFamily; font.pixelSize: Theme.textSize
        selectionColor: Theme.selected; selectedTextColor: Theme.foreground
        background: Rectangle { color: Theme.background; radius: Theme.radius; border.color: input.activeFocus ? Theme.accent : Theme.hairline }
        onTextChanged: root.search.query = text
        Keys.onReturnPressed: event => { root.search.step(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true }
        Keys.onEnterPressed: event => { root.search.step(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true }
    }
    Text {
        id: resultCount
        width: 94
        anchors.right: buttons.left; anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: root.search.error ? "Search failed" : !input.text.trim().length ? ""
            : root.search.results.length ? (root.search.current >= 0 ? (root.search.current + 1) + " / " : "")
                + root.search.results.length + (root.search.truncated ? "+" : root.search.searching ? "…" : "")
            : root.search.searching ? "Searching…" : "No matches"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.search.error ? Theme.urgent : Theme.secondaryText
        font.family: Theme.fontFamily; font.pixelSize: Theme.smallSize
        ToolTip.visible: countHover.containsMouse && (!!root.search.error || root.search.truncated)
        ToolTip.text: root.search.error ? root.search.error + "\nPress Enter in the field to retry." : "Showing the first 10,000 matches. Narrow your search."
        ToolTip.delay: 500
        MouseArea { id: countHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }
    Row {
        id: buttons
        anchors.right: parent.right; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        ToolButton { id: previous; compact: true; label: "↑"; labelSize: 16; accessibleName: "Previous match"; enabled: root.search.results.length > 0; onActivated: root.search.step(-1) }
        ToolButton { id: next; compact: true; label: "↓"; labelSize: 16; accessibleName: "Next match"; enabled: root.search.results.length > 0; onActivated: root.search.step(1) }
        ToolButton { id: close; compact: true; label: "×"; labelSize: 16; accessibleName: "Close search"; onActivated: root.dismiss() }
    }
}
