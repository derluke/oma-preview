#!/usr/bin/env python3
"""Send native Qt wheel events privately; no desktop or hardware input."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='oma-native-scroll-') as scratch:
    work = Path(scratch)
    test_ui = Path(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'))
    if not (test_ui/'native/libomapreviewcontact.so').is_file():
        raise SystemExit('Native contact module missing: run bash native/build.sh (or install a complete matching UI).')
    (work/'ui').mkdir()
    for name in ('MomentumScroll.qml', 'TrackpadContact.qml'):
        shutil.copy(test_ui/name, work/'ui'/name)
    (work/'ui/qmldir').write_text('module OmaPreview\nsingleton TrackpadContact 1.0 TrackpadContact.qml\nMomentumScroll 1.0 MomentumScroll.qml\n')
    if (test_ui/'native').exists():
        shutil.copytree(test_ui/'native', work/'ui/native')
    (work/'test.qml').write_text('''
import QtQuick
import QtQuick.Window
import "ui"
Window {
    id: window
    property int clicks: 0
    property var contactBridge: TrackpadContact.bridge
    property string contactProblem: TrackpadContact.component ? TrackpadContact.component.errorString() : "Contact component missing"
    width: 600; height: 500; visible: Qt.application.arguments.indexOf("contact-probe") < 0
    Flickable {
        id: surface; objectName: "surface"; anchors.fill: parent
        contentWidth: 20000; contentHeight: 20000; contentX: 1000; contentY: 1000
        boundsBehavior: Flickable.StopAtBounds; maximumFlickVelocity: 9000
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: window.clicks++ }
        MomentumScroll { objectName: "scroll"; anchors.fill: parent; surface: surface }
    }
}
''')
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Quick'], text=True).split()
    subprocess.run(['c++', '-std=c++17', '-fPIC', str(root/'tests/native-scroll.cpp'), '-o', str(work/'test'), *flags], check=True)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    if '--probe-wayland' in sys.argv:
        probe_env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
        subprocess.run([str(work/'test'), str(work/'test.qml'), 'contact-probe'], env=probe_env, check=True, timeout=10)
        raise SystemExit(0)
    subprocess.run([str(work/'test'), str(work/'test.qml'), 'contact-probe'], env=env, check=True, timeout=10)
    (work/'list.qml').write_text((work/'test.qml').read_text().replace('Flickable {', 'ListView {')
        .replace('contentWidth: 20000; contentHeight: 20000; contentX: 1000; contentY: 1000',
                 'model: 300; delegate: Rectangle { width: 600; height: 64 }\n        contentY: 1000'))
    for layout in ('test', 'list'):
        print('Native events on ' + ('Flickable' if layout == 'test' else 'ListView'), flush=True)
        for scenario in ('wobble', 'horizontal', 'gentle', 'repeat', 'no-end', 'angle-pad', 'native', 'reverse', 'stop', 'wheel',
                         'tap', 'tap-right', 'tap-double', 'tap-pending', 'tap-native', 'hold-one', 'hold-two', 'hold-continue',
                         'hold-transition', 'hold-reverse', 'hold-pinch', 'hold-lift', 'hold-wait', 'hold-outside'):
            if layout == 'list' and scenario == 'horizontal':
                continue
            subprocess.run([str(work/'test'), str(work/f'{layout}.qml'), scenario], env=env, check=True, timeout=10)
