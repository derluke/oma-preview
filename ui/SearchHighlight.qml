import QtQuick
import "."

Item {
    id: root
    property var hit: null
    property string pageKey: ""
    clip: true
    Repeater {
        model: root.hit && root.hit.pageKey === root.pageKey ? root.hit.rects : []
        delegate: Rectangle {
            required property var modelData
            x: modelData.x * root.width - 2
            y: modelData.y * root.height - 2
            width: modelData.width * root.width + 4
            height: modelData.height * root.height + 4
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
            border.color: Theme.accent; border.width: 1; radius: 2
        }
    }
}
