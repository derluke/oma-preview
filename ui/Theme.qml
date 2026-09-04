pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property color background: "#101315"
    property color foreground: "#cacccc"
    property color muted: "#707880"
    property color accent: "#89b4fa"
    property color urgent: "#f38ba8"
    readonly property color chrome: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.045))
    readonly property color hover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.09)
    readonly property color selected: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
    readonly property string fontFamily: "sans-serif"
    readonly property int textSize: 13
    readonly property int smallSize: 12
    readonly property int radius: 5
    readonly property int gap: 8

    function load(raw) {
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
            if (!m) continue
            if (m[1] === "background") background = m[2]
            else if (m[1] === "foreground") foreground = m[2]
            else if (m[1] === "accent" || m[1] === "color4") accent = m[2]
            else if (m[1] === "muted" || m[1] === "color8") muted = m[2]
            else if (m[1] === "red" || m[1] === "color1") urgent = m[2]
        }
    }

    property FileView colors: FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
    }
}
