pragma Singleton
import QtQuick

QtObject {
    id: root
    property var bridge: null
    property var component: null
    readonly property bool available: !!bridge && bridge.available
    signal began(int fingers)
    signal ended(bool cancelled)
    function attach() {
        if (!component || component.status !== Component.Ready || bridge) return
        bridge = component.createObject(root)
        if (!bridge) return
        bridge.began.connect(root.began)
        bridge.ended.connect(root.ended)
    }
    Component.onCompleted: {
        // Source-only developer checkouts and non-Wayland platforms retain
        // click-to-stop. Packaged installations include the native module.
        // Resolve the directory first: Quickshell keeps .qml URLs behind its
        // virtual scheme, but Qt's native plugin loader needs a filesystem URL.
        // This leaf module has no shell singletons and is safe to load directly.
        component = Qt.createComponent(String(Qt.resolvedUrl("native/")) + "ContactSource.qml")
        if (component.status === Component.Loading) component.statusChanged.connect(root.attach)
        else attach()
    }
}
