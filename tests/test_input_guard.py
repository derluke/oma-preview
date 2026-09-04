import unittest
from input_guard import InputGuard


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.state = dict(pid=123, focused_pid=123, focused_address='test',
                          active=True, ready=True, busy=False, modal=False,
                          editing=True, selected_annotation=0, text='')
        self.sent = []
        self.guard = InputGuard(lambda: self.state, 123, 'test', dedicated=True)

    def test_requires_dedicated_desktop(self):
        with self.assertRaises(RuntimeError):
            InputGuard(lambda: self.state, 123, 'test')

    def test_wrong_focus_modal_busy_and_restart_send_nothing(self):
        for key, value in [('focused_pid', 999), ('focused_address', 'other'),
                           ('modal', True), ('busy', True), ('pid', 456), ('active', False)]:
            with self.subTest(key=key):
                self.setUp()
                self.state[key] = value
                with self.assertRaises(RuntimeError):
                    self.guard.perform(lambda: self.sent.append('bad'), lambda s: True, lambda s: True)
                self.assertEqual(self.sent, [])

    def test_missing_ipc_state_fails_closed(self):
        self.state.clear()
        with self.assertRaises(KeyError): self.guard.check()
        self.assertTrue(self.guard.failed)

    def test_unconfirmed_action_latches_stop(self):
        with self.assertRaises(RuntimeError):
            self.guard.perform(lambda: self.sent.append('first'), lambda s: True, lambda s: False, timeout=0)
        with self.assertRaises(RuntimeError): self.guard.check()
        self.assertEqual(self.sent, ['first'])

    def test_focus_loss_during_typing_stops_remaining_characters(self):
        def send(char):
            self.sent.append(char)
            self.state['focused_pid'] = 999
        with self.assertRaises(RuntimeError): self.guard.type_text('abc', send, 0)
        self.assertEqual(self.sent, ['a'])

    def test_confirmed_typing(self):
        def send(char): self.state['text'] += char
        self.guard.type_text('abc', send, 0)
        self.assertEqual(self.state['text'], 'abc')


if __name__ == '__main__': unittest.main()
