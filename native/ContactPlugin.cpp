#include <QGuiApplication>
#include <QTimer>
#include <QQmlExtensionPlugin>
#include <QtQml>
#include <QtGui/qguiapplication_platform.h>
#include <QWaylandClientExtension>
#include <wayland-client.h>
#include "gestures-client.h"

// This joins Qt's existing Wayland connection. Hold events are delivered only
// for this client's surfaces; no raw devices or compositor settings are used.
class HoldExtension final : public QWaylandClientExtension {
    Q_OBJECT
public:
    HoldExtension() : QWaylandClientExtension(3) {
        connect(&m_pointerCheck, &QTimer::timeout, this, &HoldExtension::attachPointer);
        m_pointerCheck.setInterval(250);
        connect(this, &QWaylandClientExtension::activeChanged, this, [this] {
            if (isActive()) { attachPointer(); m_pointerCheck.start(); }
            else { m_pointerCheck.stop(); resetHold(); }
        });
    }
    ~HoldExtension() override {
        resetHold();
        if (m_manager) {
            if (wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_manager)) >= 2)
                zwp_pointer_gestures_v1_release(m_manager);
            else zwp_pointer_gestures_v1_destroy(m_manager);
        }
    }
    const wl_interface *extensionInterface() const override { return &zwp_pointer_gestures_v1_interface; }
    void bind(wl_registry *registry, int id, int version) override {
        setVersion(qMin(version, 3));
        m_manager = static_cast<zwp_pointer_gestures_v1 *>(wl_registry_bind(registry, id, extensionInterface(), this->version()));
    }
    bool available() const { return m_hold != nullptr; }
signals:
    void availabilityChanged();
    void began(int fingers);
    void ended(bool cancelled);
private:
    void resetHold() {
        if (!m_hold) return;
        if (m_holding) emit ended(true);
        m_holding = false;
        zwp_pointer_gesture_hold_v1_destroy(m_hold);
        m_hold = nullptr; m_pointer = nullptr;
        emit availabilityChanged();
    }
    void attachPointer() {
        if (!isActive() || version() < 3 || !m_manager) return;
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        auto *pointer = native ? native->pointer() : nullptr;
        if (pointer == m_pointer) return;
        resetHold();
        if (!pointer) return;
        m_pointer = pointer;
        m_hold = zwp_pointer_gestures_v1_get_hold_gesture(m_manager, pointer);
        static const zwp_pointer_gesture_hold_v1_listener listener = {
            [](void *data, zwp_pointer_gesture_hold_v1 *, uint32_t, uint32_t, wl_surface *, uint32_t fingers) {
                auto *self = static_cast<HoldExtension *>(data);
                self->m_holding = fingers == 1 || fingers == 2;
                if (self->m_holding) emit self->began(int(fingers));
            },
            [](void *data, zwp_pointer_gesture_hold_v1 *, uint32_t, uint32_t, int32_t cancelled) {
                auto *self = static_cast<HoldExtension *>(data);
                if (self->m_holding) { self->m_holding = false; emit self->ended(cancelled != 0); }
            }
        };
        zwp_pointer_gesture_hold_v1_add_listener(m_hold, &listener, this);
        emit availabilityChanged();
    }
    QTimer m_pointerCheck;
    zwp_pointer_gestures_v1 *m_manager = nullptr;
    zwp_pointer_gesture_hold_v1 *m_hold = nullptr;
    wl_pointer *m_pointer = nullptr; // Borrowed from Qt; never destroyed here.
    bool m_holding = false;
};

class HoldBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availabilityChanged)
public:
    explicit HoldBridge(QObject *parent = nullptr) : QObject(parent) {
        if (!QGuiApplication::platformName().startsWith("wayland")) return;
        m_extension = new HoldExtension;
        m_extension->setParent(this);
        connect(m_extension, &HoldExtension::availabilityChanged, this, &HoldBridge::availabilityChanged);
        connect(m_extension, &HoldExtension::began, this, &HoldBridge::began);
        connect(m_extension, &HoldExtension::ended, this, &HoldBridge::ended);
    }
    bool available() const { return m_extension && m_extension->available(); }
signals:
    void availabilityChanged();
    void began(int fingers);
    void ended(bool cancelled);
private:
    HoldExtension *m_extension = nullptr;
};

class ContactPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<HoldBridge>(uri, 1, 0, "HoldBridge"); }
};

#include "ContactPlugin.moc"
