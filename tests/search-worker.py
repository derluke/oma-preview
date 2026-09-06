#!/usr/bin/env python3
"""Real PDF search, page identity and owned-child cancellation; no desktop."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary = os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/release/oma-preview'))

with tempfile.TemporaryDirectory(prefix='oma-search-worker-') as scratch:
    work = Path(scratch)
    def pdf(name, text):
        svg, target = work/(name+'.svg'), work/(name+'.pdf')
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="500">'
                       '<rect width="400" height="500" fill="white"/>'
                       '<text x="40" y="80" font-family="sans-serif" font-size="24">'+text+'</text></svg>')
        subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(target), str(svg)], check=True)
        return target
    alpha = pdf('alpha', 'ALPHA café office')
    omega = pdf('omega', 'Omega total')
    combined = work/'combined.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', str(alpha), '1', str(omega), '1', '--', str(combined)], check=True)
    blank = work/'blank.pdf'
    subprocess.run(['rsvg-convert', '--format=pdf', '--output='+str(blank), str(root/'assets/org.omarchy.oma-preview.svg')], check=True)
    hashes = {path: hashlib.sha256(path.read_bytes()).digest() for path in (alpha, omega, combined, blank)}
    pages = [dict(path=str(alpha), page=1, key='first'), dict(path=str(combined), page=2, key='second'),
             dict(path=str(combined), page=1, key='third'), dict(path=str(combined), page=1, key='duplicate')]
    def search(query, selected=pages, success=True, start_index=0, order=None):
        result = subprocess.run([binary, '--search-worker'], input=json.dumps(dict(query=query, pages=selected, start_index=start_index)),
                                text=True, capture_output=True, timeout=15)
        if not success:
            assert result.returncode, 'Invalid request was accepted'
            assert 'search_done' not in result.stdout, 'Failure reported successful completion'
            return
        assert result.returncode == 0, result.stderr
        events = [json.loads(line) for line in result.stdout.splitlines()]
        done = events.pop()
        assert done['t'] == 'search_done' and done['completed'] == len(selected) and not done['truncated'], done
        assert len(events) == len(selected)
        assert sorted(event['page_index'] for event in events) == list(range(len(selected))), 'Page omitted or emitted twice'
        if order is not None:
            order.extend(event['page_index'] for event in events)
        for event in events:
            assert event['t'] == 'search_page'
            assert selected[event['page_index']]['key'] == event['page_key'], 'Workspace identity lost'
            for match in event['matches']:
                assert match['rects']
                for rect in match['rects']:
                    assert 0 <= rect['x'] <= 1 and 0 <= rect['y'] <= 1
                    assert 0 < rect['width'] <= 1 and 0 < rect['height'] <= 1
                    assert rect['x'] + rect['width'] <= 1.00001 and rect['y'] + rect['height'] <= 1.00001
        return {event['page_key']: event['matches'] for event in events}, done
    matches, done = search('alpha')
    assert done['matches'] == 3 and not matches['second'] and matches['third'] == matches['duplicate']
    matches, done = search('CAFÉ office')
    assert done['matches'] == 3 and len(matches['first'][0]['rects']) == 2
    assert search('missing')[1]['matches'] == 0
    assert search('alpha', [pages[1]])[1]['matches'] == 0, 'Removed source page leaked into results'
    assert search('alpha', [dict(path=str(blank), page=1, key='blank')])[1]['matches'] == 0
    search('', success=False)
    search('x' * 513, success=False)
    search('alpha', [pages[0], pages[0]], success=False)
    search('alpha', [dict(path=str(alpha), page=999, key='outside')], success=False)
    search('alpha', start_index=len(pages), success=False)
    search('alpha', start_index=-1, success=False)
    order = []
    assert search('alpha', start_index=1, order=order)[1]['matches'] == 3
    assert order[0] == 1, 'Search did not start at the current source/page'
    order = []
    assert search('alpha', start_index=2, order=order)[1]['matches'] == 3
    assert order[:2] == [2, 3], 'Repeated current page was not prioritized with stable identities'
    order = []
    assert search('alpha', start_index=3, order=order)[1]['matches'] == 3
    assert order[:2] == [3, 2], 'The visible copy of a repeated page was not prioritized'

    # Cross the extraction-batch boundary with real Poppler output, including
    # source page numbers that are not the same as workspace indices.
    stress = work/'batched.pdf'
    subprocess.run(['qpdf', '--empty', '--pages', *[part for _ in range(260) for part in (str(alpha), '1')],
                    '--', str(stress)], check=True)
    hashes[stress] = hashlib.sha256(stress.read_bytes()).digest()
    selected = [dict(path=str(stress), page=i+1, key=f'batched-{i}') for i in range(260)]
    order = []
    assert search('alpha', selected, start_index=220, order=order)[1]['matches'] == 260
    assert order[0] == 220, 'Large source was searched from the beginning'
    order = []
    assert search('alpha', list(reversed(selected)), order=order)[1]['matches'] == 260
    assert order[0] == 0, 'Reversed workspace did not start with the current page'
    order = []
    assert search('alpha', [selected[0], selected[-1]], start_index=1, order=order)[1]['matches'] == 2
    assert order == [1, 0], 'Sparse selection lost current-first ordering'

    # Use a controlled long-running extractor to verify the Linux parent-death
    # contract deterministically. Only the worker and its resolved child are
    # affected. The real extractor was used for every search assertion above.
    tools = work/'bin'
    tools.mkdir()
    fake = tools/'pdftotext'
    fake.write_text('#!/bin/sh\nexec sleep 30\n')
    fake.chmod(0o700)
    process = subprocess.Popen([binary, '--search-worker'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=dict(os.environ, PATH=str(tools)+':'+os.environ['PATH']))
    child_pid = None
    try:
        process.stdin.write(json.dumps(dict(query='alpha', pages=[pages[0]])))
        process.stdin.close()
        deadline = time.monotonic() + 5
        children = Path(f'/proc/{process.pid}/task/{process.pid}/children')
        while time.monotonic() < deadline and process.poll() is None:
            ids = children.read_text().split()
            if ids:
                child_pid = int(ids[0])
                break
            time.sleep(0.01)
        assert child_pid is not None, 'Worker did not launch its extractor'
        process.terminate()
        assert process.wait(timeout=5) != 0
        state = Path(f'/proc/{child_pid}/stat')
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if not state.exists() or state.read_text().rsplit(')', 1)[1].strip().split()[0] == 'Z':
                break
            time.sleep(0.01)
        else:
            raise AssertionError('Extractor survived cancellation of its search worker')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()

    fake.write_text('#!/usr/bin/env python3\nimport sys\n'
                    'sys.stdout.write("1\\t1\\t0\\t0\\t0\\t0\\t0\\t0\\t100\\t100\\t-1\\t###PAGE###\\n")\n'
                    'sys.stdout.write("5\\t1\\t0\\t0\\t0\\t0\\t10\\t10\\t5\\t5\\t100\\ta\\n" * 10001)\n')
    capped = subprocess.run([binary, '--search-worker'], input=json.dumps(dict(query='a', pages=[pages[0]])),
                            text=True, capture_output=True, timeout=10,
                            env=dict(os.environ, PATH=str(tools)+':'+os.environ['PATH']))
    assert capped.returncode == 0, capped.stderr
    events = [json.loads(line) for line in capped.stdout.splitlines()]
    assert len(events[0]['matches']) == 10000 and events[-1]['matches'] == 10000 and events[-1]['truncated'], 'Result cap was silent or ineffective'
    repeated = [pages[0], dict(pages[0], key='visible-copy')]
    capped = subprocess.run([binary, '--search-worker'], input=json.dumps(dict(query='a', pages=repeated, start_index=1)),
                            text=True, capture_output=True, timeout=10,
                            env=dict(os.environ, PATH=str(tools)+':'+os.environ['PATH']))
    assert capped.returncode == 0, capped.stderr
    events = [json.loads(line) for line in capped.stdout.splitlines()]
    assert events[0]['page_index'] == 1 and len(events[0]['matches']) == 10000 and events[-1]['truncated'], 'Result cap excluded the visible repeated page'
    fake.write_text('#!/usr/bin/env python3\nimport sys\nsys.stdout.write("x" * (1024 * 1024 + 2))\n')
    oversized = subprocess.run([binary, '--search-worker'], input=json.dumps(dict(query='a', pages=[pages[0]])),
                               text=True, capture_output=True, timeout=10,
                               env=dict(os.environ, PATH=str(tools)+':'+os.environ['PATH']))
    assert oversized.returncode and 'safety limit' in oversized.stderr and 'search_done' not in oversized.stdout
    for path, expected in hashes.items():
        assert hashlib.sha256(path.read_bytes()).digest() == expected, 'Source changed'
    print('PASS: real PDF search, Unicode/phrases, bounds, workspace pages, empty/invalid input, caps and cancellation; sources unchanged')
