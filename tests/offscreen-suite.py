#!/usr/bin/env python3
"""Run UI regressions with private fixtures/state and no desktop connection."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
env.pop('DISPLAY', None)
env.pop('WAYLAND_DISPLAY', None)
env.pop('OMA_PREVIEW_TEST_PLATFORM', None)

with tempfile.TemporaryDirectory(prefix='oma-suite-') as scratch:
    work = Path(scratch)
    page, stress = work/'page.pdf', work/'stress.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(page),
                    str(root/'assets/org.omarchy.oma-preview.svg')], env=env, check=True)
    # Shared resources keep this inexpensive while exercising a large page model.
    subprocess.run(['qpdf', '--empty', '--pages', *[part for _ in range(2048) for part in (str(page), '1')],
                    '--', str(stress)], env=env, check=True)
    checks = [
        ('dialog-smoke.py', []),
        ('page-menu.py', []),
        ('history-render.py', []),
        ('native-scroll.py', []),
        ('history-retention.py', []),
        ('annotation-scale.py', []),
        ('annotation-keys.py', []),
        ('find-flow.py', []),
        ('find-order.py', []),
        ('reading-position.py', []),
        ('export-recovery.py', []),
        ('close-recovery.py', []),
        ('open-recovery.py', []),
        ('source-recovery.py', []),
        ('reader-session.py', [str(page), '10', '--scale', '2', '--expect-source-only']),
        ('reader-session.py', [str(page), '20', '--scale', '1', '--max-resident-readers', '8']),
        ('reader-pool.py', []),
        ('thumbnail-smoke.py', [str(stress)]),
        ('thumbnail-paper.py', []),
        ('layout-performance.py', [str(stress)]),
        ('history-performance.py', [str(stress)]),
        ('history-performance.py', [str(stress), 'pages']),
        ('raster-quality.py', [str(page)]),
        ('page-raster-identity.py', []),
        ('theme-contrast.py', []),
    ]
    for name, args in checks:
        print(f'Running {name}', flush=True)
        subprocess.run([sys.executable, str(root/'tests'/name), *args], cwd=root,
                       env=env, check=True, timeout=60)
print('PASS: isolated UI regression suite (2,048-page synthetic stress fixture)')
