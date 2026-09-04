# UI automation safety

The old demo sent global input while an unexpected native file dialog remained
open. It continued after focus moved. Do not repeat that workflow.

## Safe default checks (no desktop input)

```
cargo test --locked
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tests/dialog-smoke.py
```

For a long PDF (at least ten pages), `python3 tests/thumbnail-smoke.py INPUT.pdf`
checks viewport-only rendering, navigation to the last page, renderer release
on collapse, and selection retention on expand, all offscreen.

The dialog test uses a temporary UI copy, isolated state and Qt's offscreen
platform. It opens/closes the actual Open/Add/Save dialogs and checks that live
review updates are blocked. It never invokes wtype, uinput or the compositor.

## Real interaction tests and recordings

Use a disposable VM or dedicated test desktop, not a daily-use desktop with
terminals, chats, browsers or private documents open. Existing `ui-flow.sh`,
`pinch-flow.sh` and `corpus-smoke.py` are legacy global-input tests. They refuse
to run unless `OMA_PREVIEW_DEDICATED_TEST_DESKTOP=1` is explicitly set. That
variable is an operator assertion, not an isolation mechanism, and those tests
are not a safe recording driver for a shared desktop.

New recording drivers must use `input_guard.py` around input, with bounded
app/compositor queries and exact PID + window-address matching. Require an
expected precondition and observed postcondition for every action. Typing
requires the exact selected text editor and confirmation after each character.
Missing fields, timeouts, dialogs, focus loss or changed process identity must
terminate input, without retries or Escape/Return recovery. Recording teardown
must target only the recorder process created by that driver.

Do not select windows by class or title alone. Do not assume monitor geometry,
fullscreen state, a closed dialog, or successful focus. Validate coordinates
against the target window and monitor immediately before using them. Do not
capture until a visual preflight confirms only the intended sample is visible.

A check followed by global input has an unavoidable race: focus can change
between the two. The guard reduces risk; only a dedicated input environment
keeps unrelated applications out of reach. Do not describe focus checks as
absolute isolation. The failed temporary demo runner is disabled, not repaired
or approved for reuse. No replacement recording has been validated yet.
