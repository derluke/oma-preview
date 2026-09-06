// Real QWheelEvent delivery into Qt Quick, on an isolated offscreen window.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QQuickItem>
#include <QPointingDevice>
#include <QTimer>
#include <QWheelEvent>
#include <QMouseEvent>
#include <QDebug>
#include <cstdio>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlEngine::warnings, [](const QList<QQmlError> &warnings) {
        for (const auto &warning : warnings) std::fprintf(stderr, "%s\n", qPrintable(warning.toString()));
    });
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty()) return 2;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) return 3;
    auto *surface = window->findChild<QQuickItem *>("surface");
    auto *scroll = window->findChild<QQuickItem *>("scroll");
    if (!surface || !scroll) return 3;
    const QString scenario = QString::fromLocal8Bit(argv[2]);
    const bool tapCase = scenario.startsWith("tap");
    const bool holdCase = scenario.startsWith("hold-");
    auto *contact = window->property("contactBridge").value<QObject *>();
    QPointingDevice pad("test pad", 42, QInputDevice::DeviceType::TouchPad,
                        QPointingDevice::PointerType::Finger, QInputDevice::Capability::Position,
                        2, 0);
    auto send = [&](int pixels, Qt::ScrollPhase phase, int horizontal = 0) {
        QPointF pos(200, 200);
        QWheelEvent event(pos, pos, scenario == "angle-pad" ? QPoint() : QPoint(horizontal, pixels), QPoint(horizontal * 8, pixels * 8),
                          Qt::NoButton, Qt::NoModifier, phase, false,
                          Qt::MouseEventSynthesizedBySystem, &pad);
        QCoreApplication::sendEvent(window, &event);
    };
    int step = 0;
    double release = 0;
    double beforeRepeat = 0;
    bool horizontal = scenario == "horizontal";
    const char *position = horizontal ? "contentX" : "contentY";
    auto fail = [&](const char *reason) {
        std::fprintf(stderr, "FAIL %s: %s\n", qPrintable(scenario), reason);
        app.exit(1);
    };
    auto tap = [&](bool twice) {
        QPointF pos(200, 200);
        const auto button = scenario == "tap-right" ? Qt::RightButton : Qt::LeftButton;
        QMouseEvent press(twice ? QEvent::MouseButtonDblClick : QEvent::MouseButtonPress,
                          pos, pos, button, button, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &press);
        if (surface->property("flicking").toBool()) fail("tap did not stop immediately on press");
        QMouseEvent releaseEvent(QEvent::MouseButtonRelease, pos, pos, button, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &releaseEvent);
    };
    auto holdBegin = [&](int fingers, bool outside = false) {
        QPointF pos = outside ? QPointF(700, 600) : QPointF(200, 200);
        QMouseEvent move(QEvent::MouseMove, pos, pos, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &move);
        if (!contact || !QMetaObject::invokeMethod(contact, "began", Q_ARG(int, fingers))) fail("native contact bridge not loaded");
        if (!outside && surface->property("flicking").toBool()) fail("hold BEGIN did not stop before finger lift");
    };
    auto holdEnd = [&](bool cancelled) {
        if (!contact || !QMetaObject::invokeMethod(contact, "ended", Q_ARG(bool, cancelled))) fail("hold end unavailable");
    };
    QTimer timer;
    timer.setInterval(16);
    QObject::connect(&timer, &QTimer::timeout, [&] {
        if (scenario == "contact-probe") {
            if (step++ < 30) return;
            if (!contact) fail(qPrintable(window->property("contactProblem").toString()));
            else if (QGuiApplication::platformName().startsWith("wayland") && !contact->property("available").toBool())
                fail("compositor hold protocol or pointer unavailable");
            else { std::printf("PASS contact bridge loaded; platform=%s available=%d; no visible window or input\n",
                               qPrintable(QGuiApplication::platformName()), contact->property("available").toBool()); app.quit(); }
            return;
        }
        if (scenario == "wheel") {
            if (step == 0) {
                const double before = surface->property(position).toDouble();
                QPointF pos(200, 200);
                QWheelEvent event(pos, pos, QPoint(), QPoint(0, -120),
                                  Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
                QCoreApplication::sendEvent(window, &event);
                release = surface->property(position).toDouble();
                if (qAbs(release - before - 160) > 0.1) fail("wheel notch did not step exactly 160 px");
            } else if (step == 30) {
                if (qAbs(surface->property(position).toDouble() - release) > 0.1 || surface->property("flicking").toBool())
                    fail("mouse wheel coasted after a notch");
                else { std::puts("PASS wheel: precise step, no coast"); app.quit(); }
            }
            ++step; return;
        }
        const auto phase = scenario == "no-end" || scenario == "angle-pad" ? Qt::NoScrollPhase : Qt::ScrollUpdate;
        int amount = scenario == "gentle" ? -1 : -3;
        if (step == 0) { if (scenario != "no-end" && scenario != "angle-pad") send(0, Qt::ScrollBegin); }
        else if (step <= 8) send(horizontal ? 0 : amount, phase, horizontal ? amount : 0);
        else if (step <= 10) {
            // Two tiny orthogonal events after the primary swipe reproduce the
            // old bug: reversing either axis erased BOTH velocity histories.
            int wobble = step == 9 ? -1 : 1;
            send(horizontal ? wobble : 0, phase, horizontal ? 0 : wobble);
        } else if (step == 11) {
            release = surface->property(position).toDouble();
            if (scenario != "no-end" && scenario != "angle-pad" && scenario != "tap-pending") send(0, Qt::ScrollEnd);
        } else if (tapCase && step == (scenario == "tap-pending" ? 12 : 15)) {
            tap(false);
            release = surface->property(position).toDouble();
        } else if (scenario == "tap-double" && step == 18) {
            tap(true);
        } else if (scenario == "tap-native" && step >= 16 && step <= 20) {
            send(-3, Qt::ScrollMomentum);
        } else if (holdCase && step == 15) {
            beforeRepeat = qAbs(surface->property("verticalVelocity").toDouble());
            holdBegin(scenario == "hold-one" || scenario == "hold-transition" ? 1 : 2, scenario == "hold-outside");
            release = surface->property(position).toDouble();
        } else if (scenario == "hold-transition" && step == 16) {
            holdEnd(true); holdBegin(2);
        } else if (holdCase && (step == 18 || (scenario == "hold-wait" && step == 38))
                   && scenario != "hold-one" && scenario != "hold-two" && scenario != "hold-outside"
                   && !(scenario == "hold-wait" && step == 18)) {
            holdEnd(scenario != "hold-lift");
            if (scenario == "hold-pinch") QMetaObject::invokeMethod(scroll, "stop");
            send(0, Qt::ScrollBegin);
            send(scenario == "hold-reverse" ? 3 : -3, Qt::ScrollUpdate);
            double carry = scroll->property("carriedVelocity").toDouble();
            bool shouldCarry = scenario == "hold-continue" || scenario == "hold-transition" || scenario == "hold-reverse";
            if (shouldCarry ? carry <= 0 : carry != 0) fail("continuation velocity was not distinguished from a fresh gesture");
            if (scenario == "hold-reverse" && scroll->property("velocity").toDouble() >= 0) fail("reversal revived old direction");
            send(0, Qt::ScrollEnd);
            release = surface->property(position).toDouble();
        } else if (scenario == "repeat" && step == 15) {
            beforeRepeat = qAbs(surface->property("verticalVelocity").toDouble());
            send(0, Qt::ScrollBegin);
            send(-3, Qt::ScrollUpdate);
            if (scroll->property("velocity").toDouble() <= beforeRepeat)
                fail("repeat swipe lost carry-over speed");
            send(0, Qt::ScrollEnd);
        } else if (scenario == "native" && step >= 12 && step <= 18) {
            send(-1, Qt::ScrollMomentum);
            release = surface->property(position).toDouble();
            if (step == 18) send(0, Qt::ScrollEnd);
        } else if (scenario == "stop" && step == 15) {
            QMetaObject::invokeMethod(scroll, "stop");
            release = surface->property(position).toDouble();
        } else if (scenario == "reverse" && step >= 12 && step <= 16) {
            send(3, Qt::ScrollUpdate);
            release = surface->property(position).toDouble();
            if (step == 16) send(0, Qt::ScrollEnd);
        } else if (step == 30) {
            if (scenario == "hold-wait") { ++step; return; }
            double travel = surface->property(position).toDouble() - release;
            bool okay = scenario == "native" || scenario == "stop" || tapCase || scenario == "hold-one" || scenario == "hold-two" ? qAbs(travel) < 0.1
                      : scenario == "reverse" || scenario == "hold-reverse" ? travel < -20 : travel > 40;
            if (!okay) {
                std::fprintf(stderr, "travel %.1f\n", travel);
                fail("incorrect post-release movement");
            } else if (tapCase) {
                if (window->property("clicks").toInt()) fail("stop tap activated underlying content");
            } else { std::printf("PASS %s: post-release travel %.1f px\n", qPrintable(scenario), travel); app.quit(); }
        } else if (scenario == "hold-wait" && step == 60) {
            if (surface->property(position).toDouble() <= release + 40) fail("fresh scroll did not proceed after holding");
            else { std::puts("PASS hold-wait: long contact discards carry, fresh scroll works"); app.quit(); }
        } else if (tapCase && step == 70) {
            tap(false);
            if (window->property("clicks").toInt() != 1) fail("ordinary click did not reach underlying content after stopping");
            else { std::printf("PASS %s: immediate stop, no accidental click, normal clicks recover\n", qPrintable(scenario)); app.quit(); }
        }
        ++step;
    });
    QTimer::singleShot(200, &timer, [&] { timer.start(); });
    QTimer::singleShot(5000, &app, [&] { app.exit(4); });
    return app.exec();
}
