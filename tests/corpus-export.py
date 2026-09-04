#!/usr/bin/env python3
"""Exercise backend export on real files; requires pypdf and Poppler."""
import json
from pathlib import Path
import subprocess as sp
import sys
import tempfile
import time
from pypdf import PdfReader

root = Path(__file__).resolve().parents[1]
binary = root / "target/release/oma-preview"
outdir = root / "tmp/corpus/exports"
outdir.mkdir(parents=True, exist_ok=True)
for filename in sys.argv[1:]:
    source = Path(filename).resolve()
    before = PdfReader(source)
    fields_before = before.get_fields() or {}
    inspected = json.loads(sp.check_output([binary, "inspect", source]))
    pages = [dict(path=str(source), key=f"p{i}", **p) for i, p in enumerate(inspected["pages"])]
    output = outdir / source.name
    request = dict(c="export", id=1, dest=str(output), pages=pages,
                   annotations=[dict(kind="text", page_key="p0", x=0.05, y=0.02,
                                     text="OMA_PREVIEW EXPORT TEST", size=10)])
    start = time.monotonic()
    result = sp.run([binary, "--backend"], input=json.dumps(request)+"\n", text=True, capture_output=True, check=True)
    assert '"t":"exported"' in result.stdout, result.stdout + result.stderr
    elapsed = (time.monotonic()-start)*1000
    after = PdfReader(output)
    fields_after = after.get_fields() or {}
    assert len(after.pages) == len(before.pages)
    assert set(fields_before) == set(fields_after), "Lost native form fields"
    assert {k:str(v.get('/V')) for k,v in fields_before.items()} == {k:str(v.get('/V')) for k,v in fields_after.items()}
    sp.run([binary, "verify", output], check=True, stdout=sp.DEVNULL)
    sp.run(["pdftoppm", "-f", "1", "-singlefile", "-scale-to", "1100", "-png", output, outdir/source.stem], check=True)
    assert "OMA_PREVIEW EXPORT TEST" in sp.check_output(["pdftotext", "-f", "1", "-l", "1", output, "-"], text=True)
    # The UI backend must reject saving over an input, not just the agent CLI.
    request["dest"] = str(source)
    refused = sp.run([binary, "--backend"], input=json.dumps(request)+"\n", text=True, capture_output=True, check=True)
    assert "never overwrites" in refused.stdout
    print(json.dumps(dict(file=source.name, pages=len(after.pages), native_fields=len(fields_after), export_ms=round(elapsed,1), verified=True)), flush=True)
