#!/usr/bin/env python3
"""Capture staged 0.9.0 actions in the real UI. No desktop connection or input."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
source=root/'output/pdf/A slower weekend.pdf'
before=hashlib.sha256(source.read_bytes()).digest()
output=Path(tempfile.mkdtemp(prefix='release-media-',dir=root/'output'))
(output/'frames').mkdir()
export=output/'A slower weekend - Alex.pdf'
palettes=[Path('/usr/share/omarchy/themes',name,'colors.toml').read_text()
          for name in ('tokyo-night','catppuccin-latte','gruvbox')]
harness=(root/'tests/media-sequence.qml').read_text().replace('PALETTES',json.dumps(palettes)).replace('OUTPUT',json.dumps(str(output))).replace('EXPORT',json.dumps(str(export)))
with tempfile.TemporaryDirectory(prefix='oma-media-ui-') as scratch:
    work=Path(scratch)
    shutil.copytree(root/'ui',work/'ui')
    shell=work/'ui/shell.qml'
    original=shell.read_text()
    assert original.count('        Component.onCompleted: {')==1
    shell.write_text(original.replace('ShellId oma-preview','ShellId '+work.name)
                     .replace('import QtQuick\n','import QtQuick\nimport QtTest\n',1)
                     .replace('        Component.onCompleted: {',harness+'\n        Component.onCompleted: {'))
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='',QT_QUICK_BACKEND='software',
             QT_SCALE_FACTOR='1',OMA_PREVIEW_BIN=str(root/'target/release/oma-preview'),
             OMA_PREVIEW_PATHS=json.dumps([str(source)]),OMA_PREVIEW_REVIEW_SPEC='',
             HOME=str(work/'home'),XDG_STATE_HOME=str(work/'state'),XDG_DATA_HOME=str(work/'data'))
    env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    result=subprocess.run(['qs','-p',str(work/'ui')],env=env,capture_output=True,text=True,timeout=180)
    log=result.stdout+result.stderr
    (output/'capture.log').write_text(log)
    print(output,flush=True)
    if 'MEDIA_PASS' not in log or 'Error:' in log: raise SystemExit(log)
assert hashlib.sha256(source.read_bytes()).digest()==before,'Source changed'
subprocess.run([str(root/'target/release/oma-preview'),'verify',str(export)],check=True)
assert len(list((output/'frames').glob('*.png')))==595
print('PASS: real UI, 595 frames, confirmed fictional edits/export; no desktop input')
