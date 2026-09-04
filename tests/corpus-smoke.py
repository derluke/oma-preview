#!/usr/bin/env python3
"""Real Qt rendering, bookmark persistence and Recent menu regression.

Run on a Wayland desktop: tests/corpus-smoke.py PDF [PDF ...].
Uses private state and synthetic input, never modifies the input PDFs.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess as sp
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("FOLIO_TEST_BIN", ROOT / "target/release/folio"))

def run(args, **kwargs):
    return sp.check_output([str(a) for a in args], text=True, **kwargs).strip()

with tempfile.TemporaryDirectory(prefix="folio-corpus-") as scratch:
    work = Path(scratch)
    ui = work / "ui"
    shutil.copytree(Path(os.environ.get("FOLIO_TEST_UI", ROOT / "ui")), ui)
    env = dict(os.environ, FOLIO_UI_DIR=str(ui), XDG_STATE_HOME=str(work / "state"),
               XDG_DATA_HOME=str(work / "data"))
    clicker = work / "click"
    run(["cc", "-O2", ROOT / "tests/uinput-click.c", "-o", clicker])
    process = None
    log = (work / "ui.log").open("w+")

    def call(method, *args):
        return run(["qs", "-p", ui, "ipc", "call", "folio", method, *args], stderr=sp.DEVNULL)

    def wait_for(predicate, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except (sp.CalledProcessError, ValueError):
                pass
            time.sleep(0.025)
        log.flush()
        raise AssertionError("Timed out waiting for Folio; log: " + (work / "ui.log").read_text()[-3000:])

    def stop():
        global process
        if process is not None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
            process = None

    def launch(path=None):
        global process
        process = sp.Popen([str(BIN), "--gui", *([str(path)] if path else [])], env=env,
                           stdout=log, stderr=log, start_new_session=True)
        wait_for(lambda: call("ready") == "true")

    def window():
        # The testing shell is identified by its PID group, not by another Folio window.
        clients = json.loads(run(["hyprctl", "clients", "-j"]))
        return next(c for c in clients if c["class"] == "org.omarchy.folio"
                    and os.getpgid(c["pid"]) == process.pid)

    def click(point):
        time.sleep(0.35)  # Allow compositor tiling and popup transitions to settle.
        client = window()
        x, y = map(int, point.split())
        monitor = next(m for m in json.loads(run(["hyprctl", "monitors", "-j"]))
                       if m["id"] == client["monitor"])
        run([clicker, client["at"][0]+x, client["at"][1]+y,
             int(monitor["width"]/monitor["scale"])-1,
             int(monitor["height"]/monitor["scale"])-1])
        time.sleep(0.35)

    results = []
    try:
        for filename in sys.argv[1:]:
            path = Path(filename).resolve()
            start = time.monotonic()
            inspected = json.loads(run([BIN, "inspect", path]))
            inspect_ms = (time.monotonic()-start)*1000
            start = time.monotonic()
            launch(path)
            wait_for(lambda: json.loads(call("renderState"))["ready"])
            first_ms = (time.monotonic()-start)*1000
            assert int(call("pageCount")) == inspected["page_count"]
            click(call("pagePoint", "0.5", "0.5"))
            if call("bookmarked") != "true":
                run(["wtype", "-M", "ctrl", "-k", "b", "-m", "ctrl"])
            wait_for(lambda: call("bookmarked") == "true")
            turns = []
            for page in range(2, min(inspected["page_count"], 8)+1):
                start = time.monotonic()
                run(["wtype", "-k", "Right"])
                wait_for(lambda: int(call("currentPage")) == page and json.loads(call("renderState"))["ready"])
                turns.append(round((time.monotonic()-start)*1000, 1))
            wait_for(lambda: str(path) in json.loads(call("recentPaths")))
            start = time.monotonic()
            run(["wtype", "-M", "ctrl", "-k", "End", "-m", "ctrl"])
            wait_for(lambda: int(call("currentPage")) == inspected["page_count"] and json.loads(call("renderState"))["ready"])
            last_ms = round((time.monotonic()-start)*1000, 1)
            stop()
            launch()  # History survives closing the app; reopen through actual menu clicks.
            wait_for(lambda: len(json.loads(call("recentPaths"))) > 0)
            click(call("recentButtonCentre"))
            click(call("recentItemCentre", "0"))
            wait_for(lambda: int(call("pageCount")) == inspected["page_count"] and json.loads(call("renderState"))["ready"])
            assert call("bookmarked") == "true", "Bookmark was not restored after reopening from Recent"
            click(call("pagePoint", "0.5", "0.5"))
            run(["wtype", "-M", "ctrl", "-k", "b", "-m", "ctrl"])
            wait_for(lambda: call("bookmarked") == "false")
            results.append(dict(file=path.name, bytes=path.stat().st_size, pages=inspected["page_count"],
                                inspect_ms=round(inspect_ms, 1), first_visible_ms=round(first_ms, 1),
                                page_turn_ms=turns, last_page_ms=last_ms, bookmarks="pass", recents="pass"))
            print(json.dumps(results[-1]), flush=True)
            stop()
    finally:
        stop()
        log.close()
