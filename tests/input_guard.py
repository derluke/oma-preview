"""Fail-closed action gate. Global input still requires a dedicated desktop.

read_state must use bounded IPC calls and return both application and compositor
state. No automatic focus stealing, retry, or recovery keystrokes are allowed.
"""
import time


class InputGuard:
    def __init__(self, read_state, target_pid, target_address, dedicated=False):
        if not dedicated:
            raise RuntimeError("A dedicated test desktop is required")
        self.read_state = read_state
        self.pid = target_pid
        self.address = target_address
        self.failed = False

    def check(self):
        if self.failed:
            raise RuntimeError("Input stopped after an earlier failure")
        try:
            s = self.read_state()
            if not (s['pid'] == self.pid == s['focused_pid']
                    and s['focused_address'] == self.address
                    and s['active'] and s['ready']
                    and not s['busy'] and not s['modal']):
                raise RuntimeError("Target changed, lost focus, is busy, or has a modal")
            return s
        except Exception:
            self.failed = True
            raise

    def perform(self, action, before, after, timeout=2):
        try:
            if not before(self.check()):
                raise RuntimeError("Action precondition failed")
            action()
            deadline = time.monotonic() + timeout
            while True:
                if after(self.check()):
                    return
                if time.monotonic() >= deadline:
                    raise RuntimeError("Action was not confirmed; stopping input")
                time.sleep(.025)
        except Exception:
            self.failed = True
            raise

    def type_text(self, text, send_character, annotation_index):
        # Verify focus and the exact editor before and after every character.
        for char in text:
            s = self.check()
            previous = s['text']
            self.perform(lambda: send_character(char),
                         lambda v: v['editing'] and v['selected_annotation'] == annotation_index,
                         lambda v: v['editing'] and v['selected_annotation'] == annotation_index
                         and v['text'] == previous + char)
