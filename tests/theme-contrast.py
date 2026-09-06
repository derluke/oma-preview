#!/usr/bin/env python3
"""Check actual QML secondary colours against the chrome for installed palettes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
palettes = sorted(Path('/usr/share/omarchy/themes').glob('*/colors.toml'))
with tempfile.TemporaryDirectory(prefix='oma-contrast-') as scratch:
    work = Path(scratch)
    shutil.copytree(os.environ.get('OMA_PREVIEW_TEST_UI', root/'ui'), work/'ui')
    cases = [{'name': p.parent.name, 'raw': p.read_text()} for p in palettes]
    # Portable light/dark coverage in CI, which does not install the desktop.
    cases += [
        {'name': 'test-light', 'raw': 'background="#f5f5f5"\nforeground="#555555"'},
        {'name': 'test-dark', 'raw': 'background="#161616"\nforeground="#bbbbbb"'},
    ]
    harness = '''
import QtQuick
import QtQuick.Controls
import Quickshell
import "ui"
ShellRoot {
    Window {
        visible: true; width: 200; height: 120
        ThemedMenu { id: menu; MenuItem { text: "Menu item" } }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            var cases = CASES
            for (var item of cases) {
                Theme.load(item.raw)
                if (!Qt.colorEqual(menu.background.color, Theme.chrome) || !Qt.colorEqual(menu.palette.text, Theme.foreground)
                        || !Qt.colorEqual(menu.itemAt(0).palette.highlight, Theme.selected)
                        || !Qt.colorEqual(menu.itemAt(0).palette.text, Theme.foreground))
                    throw new Error("Menu theme did not propagate: " + item.name)
                console.log("PALETTE " + JSON.stringify({name:item.name, text:String(Theme.secondaryText), background:String(Theme.chrome)}))
            }
            Qt.quit()
        }
    }
}
'''.replace('CASES', json.dumps(cases))
    (work/'shell.qml').write_text(harness)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
    result = subprocess.run(['qs', '-p', str(work/'shell.qml')], env=env, capture_output=True, text=True, timeout=10)
    log = result.stdout + result.stderr
    records = [json.loads(line.split('PALETTE ', 1)[1]) for line in log.splitlines() if 'PALETTE ' in line]
    if len(records) != len(cases) or 'Error:' in log:
        raise SystemExit(log)

def luminance(hex_color):
    channels = [int(hex_color[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

failures = []
ratios = []
for record in records:
    a, b = sorted([luminance(record['text']), luminance(record['background'])])
    ratio = (b + 0.05) / (a + 0.05)
    ratios.append(ratio)
    if ratio < 4.5:
        failures.append(f"{record['name']}: {ratio:.3f}:1")
if failures:
    raise SystemExit('Secondary-text contrast below 4.5:1: ' + ', '.join(failures))
print(f'PASS: menu theme propagation and secondary text in {len(records)} palettes; minimum {min(ratios):.3f}:1')
