"""Deterministic startup-boundary fixtures; run inside the pinned Nix shell."""
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(__file__).resolve().parents[1] / "Config/nix/scripts/payroll-workbook/libreoffice-recalculate.py"
spec = importlib.util.spec_from_file_location("libreoffice_recalculate", SOURCE)
assert spec is not None and spec.loader is not None
runner = importlib.util.module_from_spec(spec)
with patch.object(sys, "dont_write_bytecode", True):
    spec.loader.exec_module(runner)


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.waits = []
        self.expired = False
        self.exit_code = None
        self.office = Mock()
        self.office.poll.side_effect = lambda: self.exit_code
        self.event = Mock()
        self.event.is_set.side_effect = lambda: self.expired
        self.event.wait.side_effect = self.wait
        self.context = object()
        self.resolver = Mock()
        manager = Mock()
        manager.createInstanceWithContext.return_value = self.resolver
        uno = Mock()
        uno.getComponentContext.return_value = SimpleNamespace(ServiceManager=manager)
        for replacement in (patch.object(runner, "uno", uno),
                            patch.object(runner.time, "monotonic", lambda: self.now)):
            replacement.start()
            self.addCleanup(replacement.stop)

    def wait(self, seconds):
        self.waits.append(seconds)
        self.now += seconds
        return self.expired

    def connect(self):
        return runner.connect_to_office(self.office, 12345, 30.0, self.event)

    def test_ready_immediately(self):
        self.resolver.resolve.return_value = self.context
        self.assertIs(self.connect(), self.context)
        self.assertEqual(self.waits, [])

    def test_ready_after_old_five_second_cutoff(self):
        def resolve(_):
            if self.now < 6:
                raise ConnectionRefusedError("not ready")
            return self.context
        self.resolver.resolve.side_effect = resolve
        self.assertIs(self.connect(), self.context)
        self.assertGreaterEqual(self.now, 6)
        self.assertLess(self.now, 30)

    def test_never_ready_exhausts_only_remaining_budget(self):
        self.now = 25  # Startup does not get a fresh timeout after launch overhead.
        self.resolver.resolve.side_effect = ConnectionRefusedError("not ready")
        with self.assertRaisesRegex(RuntimeError, "safety deadline exceeded.*elapsed=30.000s.*child_exit=None"):
            self.connect()
        self.assertEqual(self.now, 30)
        self.assertTrue(all(0 <= seconds <= 0.05 for seconds in self.waits))

    def test_exited_process_fails_without_polling_resolver(self):
        self.exit_code = 17
        with self.assertRaisesRegex(RuntimeError, "process exited before readiness.*attempts=0 child_exit=17"):
            self.connect()
        self.resolver.resolve.assert_not_called()
        self.assertEqual(self.waits, [])

    def test_process_exit_after_failed_attempt_is_detected(self):
        def resolve(_):
            self.exit_code = 23
            raise ConnectionRefusedError("closed")
        self.resolver.resolve.side_effect = resolve
        with self.assertRaisesRegex(RuntimeError, "process exited before readiness.*attempts=1 child_exit=23"):
            self.connect()
        self.assertLessEqual(self.now, 0.05)

    def test_late_resolver_success_cannot_escape_deadline(self):
        def resolve(_):
            self.now = 31
            return self.context
        self.resolver.resolve.side_effect = resolve
        with self.assertRaisesRegex(RuntimeError, "safety deadline exceeded"):
            self.connect()

    def test_watchdog_signal_rejects_resolver_success(self):
        def resolve(_):
            self.expired = True
            return self.context
        self.resolver.resolve.side_effect = resolve
        with self.assertRaisesRegex(RuntimeError, "safety deadline exceeded"):
            self.connect()

    def test_process_exit_during_resolver_success_is_not_readiness(self):
        def resolve(_):
            self.exit_code = 0
            return self.context
        self.resolver.resolve.side_effect = resolve
        with self.assertRaisesRegex(RuntimeError, "process exited during readiness.*child_exit=0"):
            self.connect()


if __name__ == "__main__":
    unittest.main()
