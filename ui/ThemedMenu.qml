import QtQuick
import QtQuick.Controls
import "."

Menu {
    popupType: Popup.Item
    font.family: Theme.fontFamily
    font.pixelSize: Theme.textSize
    palette.window: Theme.chrome
    palette.base: Theme.chrome
    palette.button: Theme.chrome
    palette.text: Theme.foreground
    palette.windowText: Theme.foreground
    palette.buttonText: Theme.foreground
    palette.highlight: Theme.selected
    palette.highlightedText: Theme.foreground
    palette.disabled.text: Theme.muted
    palette.disabled.windowText: Theme.muted
    palette.disabled.buttonText: Theme.muted
    padding: 4
    background: Rectangle {
        // Replacing the native background also replaces its size hint. Without
        // this, small menus without an explicit width can collapse to zero.
        implicitWidth: 220
        color: Theme.chrome
        radius: Theme.radius
        border.color: Theme.hairline
    }
}
