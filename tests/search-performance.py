#!/usr/bin/env python3
"""Measure a separate search worker against a real PDF without modifying it."""
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve(strict=True)
query = sys.argv[2] if len(sys.argv) > 2 else 'the'
count = int(subprocess.check_output(['qpdf', '--show-npages', str(source)], text=True))
before = hashlib.sha256(source.read_bytes()).digest()
request = dict(query=query, pages=[dict(path=str(source), page=i+1, key=str(i)) for i in range(count)])
started = time.monotonic()
first_page = first_match = None
done = None
with tempfile.TemporaryFile(mode='w+') as errors:
    process = subprocess.Popen([os.environ.get('OMA_PREVIEW_TEST_BIN', str(root/'target/release/oma-preview')), '--search-worker'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors)
    try:
        process.stdin.write((json.dumps(request)+'\n').encode())
        process.stdin.flush()  # Worker must not need stdin EOF from the UI.
        pending = b''
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                assert time.monotonic() - started < 90, 'Search worker timed out'
                if not selector.select(timeout=1):
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                lines = (pending + chunk).split(b'\n')
                pending = lines.pop()
                for line in lines:
                    event = json.loads(line)
                    elapsed = time.monotonic() - started
                    if event['t'] == 'search_page':
                        if first_page is None:
                            first_page = elapsed
                        if event['matches'] and first_match is None:
                            first_match = elapsed
                    elif event['t'] == 'search_done':
                        done = event
        assert not pending, 'Incomplete search event'
        code = process.wait(timeout=60)
        finished = time.monotonic()
        errors.seek(0)
        assert code == 0 and done, errors.read()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stdin.close()
        process.stdout.close()
assert hashlib.sha256(source.read_bytes()).digest() == before, 'Source changed'
print(json.dumps(dict(document=source.name, pages=count, first_page_ms=None if first_page is None else round(first_page*1000),
                      first_match_ms=None if first_match is None else round(first_match*1000),
                      total_ms=round((finished-started)*1000), result=done)))
