import QtQuick
import "."

Item {
    id: root
    required property var surface
    property real gain: 5.3
    property real velocity: 0
    property real velocityX: 0
    property double lastAt: 0
    property bool nativeMomentum: false
    property var samples: []
    property var samplesX: []
    property real carriedVelocity: 0
    property real carriedVelocityX: 0
    property double stopTapUntil: 0
    property bool ignoreNativeMomentum: false
    property bool contactStopped: false
    property bool contactResumePending: false
    property real heldVelocity: 0
    property real heldVelocityX: 0
    property double heldAt: 0
    function clearContact() {
        contactStopped = false; contactResumePending = false
        heldVelocity = 0; heldVelocityX = 0; heldAt = 0
    }
    function beginContact(fingers) {
        if (fingers !== 1 && fingers !== 2) return
        // Changing from one held finger to two is not a fresh scroll. Preserve
        // the paused velocity until actual movement tells us the intention.
        if (contactResumePending && Date.now() - heldAt < 250) {
            contactStopped = true; return
        }
        if (!surface.flicking && !coast.running && !nativeMomentum) return
        var vy = surface.flicking ? surface.verticalVelocity : velocity
        var vx = surface.flicking ? surface.horizontalVelocity : velocityX
        stop()
        heldVelocity = vy; heldVelocityX = vx; heldAt = Date.now()
        contactStopped = true; contactResumePending = true
        ignoreNativeMomentum = true
    }
    function endContact(cancelled) {
        if (!contactStopped) return
        contactStopped = false
        // A cancellation may mean one -> two fingers, scrolling, or a pinch.
        // Never resume here. Only actual scroll deltas may use the short-lived
        // velocity credit; lifting the fingers discards it altogether.
        if (!cancelled) clearContact()
        stopTapUntil = Date.now() + Qt.styleHints.mouseDoubleClickInterval
    }
    function takeContactCarry(now) {
        if (!contactResumePending) return null
        var carry = now - heldAt < 250 ? {x:heldVelocityX, y:heldVelocity} : {x:0, y:0}
        clearContact(); stopTapUntil = 0
        return carry
    }
    HoverHandler {
        id: contactPointer
        parent: root.surface
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }
    Connections {
        target: TrackpadContact
        function onBegan(fingers) { if (root.enabled && contactPointer.hovered) root.beginContact(fingers) }
        function onEnded(cancelled) { root.endContact(cancelled) }
    }
    onEnabledChanged: if (!enabled) stop()
    function stop() {
        clearContact()
        coast.stop()
        surface.cancelFlick()
        velocity = 0; velocityX = 0
        carriedVelocity = 0; carriedVelocityX = 0
        samples = []; samplesX = []
        lastAt = 0
        nativeMomentum = false
    }
    function bounded(value) { return Math.max(-9000, Math.min(9000, value)) }
    function interruptByTap() {
        var moving = surface.flicking || coast.running || nativeMomentum || contactStopped
        if (!moving) return Date.now() < stopTapUntil
        stop()
        ignoreNativeMomentum = true
        stopTapUntil = Date.now() + Qt.styleHints.mouseDoubleClickInterval
        return true
    }
    MouseArea {
        parent: root.surface
        anchors.fill: parent
        z: 100
        enabled: root.enabled
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        scrollGestureEnabled: false
        onWheel: event => event.accepted = false
        // Consume only the stop gesture, including its second tap. Ordinary
        // clicks fall through to page selection, annotations and text editing.
        // Two-finger tap-to-click can arrive as a right press after hold end.
        onPressed: event => event.accepted = root.interruptByTap()
        onDoubleClicked: event => event.accepted = root.interruptByTap()
    }
    function finish() {
        coast.stop()
        if (!nativeMomentum && (Math.abs(velocity) > 10 || Math.abs(velocityX) > 10)) {
            // A constant brake makes small, precise swipes stop almost instantly.
            // Give ordinary releases roughly 650 ms to settle, without changing
            // finger-on-pad travel or launching a minimum-speed jump.
            surface.flickDeceleration = Math.max(100, Math.min(1600, Math.max(Math.abs(velocity), Math.abs(velocityX)) / 0.65))
            surface.flick(-bounded(velocityX), -bounded(velocity))
        }
        velocity = 0; velocityX = 0
        nativeMomentum = false
    }
    // Some input backends omit ScrollEnd. Never leave a gesture without a glide.
    Timer { id: coast; interval: 90; onTriggered: root.finish() }
    function moveBy(delta, dx) {
        var minimum = surface.originY
        var maximum = Math.max(minimum, minimum + surface.contentHeight - surface.height)
        surface.contentY = Math.max(minimum, Math.min(maximum, surface.contentY + delta))
        var minimumX = surface.originX
        var maximumX = Math.max(minimumX, minimumX + surface.contentWidth - surface.width)
        surface.contentX = Math.max(minimumX, Math.min(maximumX, surface.contentX + dx))
    }
    function estimateAxis(horizontal, delta, now, elapsed) {
        // Track axes separately: a sideways wobble at finger lift must not erase
        // the vertical swipe (or vice versa). Zero-axis events aren't reversals.
        var recent = (horizontal ? samplesX : samples).filter(s => now - s.at < 120)
        var carry = horizontal ? carriedVelocityX : carriedVelocity
        if (delta) {
            if (recent.length && recent[recent.length - 1].delta * delta < 0) {
                recent = []; carry = 0
            }
            var dt = recent.length ? now - recent[recent.length - 1].at : elapsed
            recent.push({at:now, delta:delta, dt:Math.max(4, Math.min(32, dt || 16))})
        }
        var travel = 0, duration = 0
        for (var s of recent) { travel += s.delta; duration += s.dt }
        var sample = travel * 1000 / Math.max(8, duration)
        if (horizontal) { samplesX = recent; carriedVelocityX = carry }
        else { samples = recent; carriedVelocity = carry }
        return bounded(sample + (carry * sample > 0 ? carry * 0.7 : 0))
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        scrollGestureEnabled: true
        // WheelHandler rejects zero-delta ScrollBegin while inactive. That
        // lets Flickable cancel the previous coast before we can carry it into
        // the next swipe. A wheel-only MouseArea sees the complete sequence,
        // including begin/end, while leaving clicks and drags to the canvas.
        onWheel: event => {
            if (event.modifiers !== Qt.NoModifier) { event.accepted = false; return }
            root.handleWheel(event, Date.now())
        }
    }
    function handleWheel(event, now) {
            if (event.phase === Qt.ScrollMomentum && ignoreNativeMomentum) { event.accepted = true; return }
            if (event.phase !== Qt.ScrollMomentum && event.phase !== Qt.ScrollEnd) ignoreNativeMomentum = false
            var elapsed = now - root.lastAt
            var delta = event.pixelDelta.y ? -event.pixelDelta.y * root.gain : -event.angleDelta.y / 120 * 160
            var dx = event.pixelDelta.x ? -event.pixelDelta.x * root.gain : -event.angleDelta.x / 120 * 160
            var trackpad = event.device && event.device.type === PointerDevice.TouchPad
            var contactCarry = delta || dx ? root.takeContactCarry(now) : null
            if (event.phase === Qt.NoScrollPhase && !event.pixelDelta.y && !event.pixelDelta.x && !trackpad) {
                // Discrete mouse-wheel notches are precise steps, not swipes.
                if (delta || dx) { root.stop(); root.moveBy(delta, dx) }
            } else {
                if (contactCarry || event.phase === Qt.ScrollBegin || ((elapsed > 120 || root.surface.flicking) && event.phase !== Qt.ScrollEnd)) {
                    root.carriedVelocity = contactCarry ? contactCarry.y : root.surface.verticalVelocity
                    root.carriedVelocityX = contactCarry ? contactCarry.x : root.surface.horizontalVelocity
                    root.samples = []; root.samplesX = []
                    root.velocity = 0; root.velocityX = 0
                    root.nativeMomentum = false
                    root.surface.cancelFlick()
                }
                if (event.phase === Qt.ScrollMomentum) root.nativeMomentum = true
                if (delta || dx) {
                    root.moveBy(delta, dx)
                    root.velocity = root.estimateAxis(false, delta, now, elapsed)
                    root.velocityX = root.estimateAxis(true, dx, now, elapsed)
                    if (!root.nativeMomentum) coast.restart()
                }
                if (root.nativeMomentum) coast.stop()
                if (event.phase === Qt.ScrollEnd) root.finish()
            }
            root.lastAt = now
            event.accepted = true
    }
}
