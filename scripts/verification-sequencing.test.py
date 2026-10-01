#!/usr/bin/env python3
"""Public focused-check handoffs; real migration semantics remain Hspec-owned."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILTERS = [
    'date-native roster foundation migration',
    'date-native Timesheet migration',
    'Operational payroll sealing migration',
    'gives roster template days explicit calendar-weekday identity',
    'date-native Roster compatibility retirement',
    'date-native roster compatibility retirement migration',
]


class SequencingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='bepis-verification-sequencing-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'bin').mkdir()
        self.log = self.root / 'calls.jsonl'
        probe = self.root / 'bin' / 'probe'
        probe.write_text('''#!/usr/bin/env python3
import json, os, signal, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['HANDOFF_LOG'], 'a') as log:
    log.write(json.dumps({'name': name, 'args': sys.argv[1:]}) + '\\n')
if os.environ.get('HANDOFF_FAIL') == name:
    raise SystemExit(37)
if os.environ.get('HANDOFF_BLOCK') == name:
    ready = Path(os.environ['HANDOFF_READY'])
    def stopped(signum, _frame):
        ready.with_suffix('.stopped').write_text(str(signum))
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, stopped)
    ready.write_text(str(os.getpid()))
    while True:
        signal.pause()
''')
        probe.chmod(0o755)
        for name in ['authority', 'regen-types', 'typecheck', 'hspec-test']:
            (self.root / 'bin' / name).symlink_to(probe)
        (self.root / 'bin' / 'date-native-roster-authority-check').write_text('exec authority "$@"\n')
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'], HANDOFF_LOG=str(self.log))

    def run_check(self, *args, **env):
        return subprocess.run(['bash', str(ROOT / 'bin/date-native-roster-migration-check'), *args], cwd=self.root, env=dict(self.env, **env), text=True, capture_output=True, timeout=15)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_preserves_order_and_batches_all_six_filters_at_the_native_owner(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertEqual([call['name'] for call in calls], ['authority', 'regen-types', 'typecheck', 'hspec-test'])
        self.assertEqual(calls[-1]['args'], [part for pattern in FILTERS for part in ['--match', pattern]])
        self.assertIn('date-native-roster-migration-check: ok', result.stdout)

    def test_failed_producers_never_reach_later_authority_or_success(self):
        owners = ['authority', 'regen-types', 'typecheck', 'hspec-test']
        for index, owner in enumerate(owners):
            with self.subTest(owner=owner):
                self.log.unlink(missing_ok=True)
                result = self.run_check(HANDOFF_FAIL=owner)
                self.assertEqual(result.returncode, 37)
                self.assertEqual([call['name'] for call in self.calls()], owners[:index + 1])
                self.assertNotIn('date-native-roster-migration-check: ok', result.stdout)

    def test_group_cancellation_stops_the_producer_without_later_handoffs(self):
        owners = ['authority', 'regen-types', 'typecheck', 'hspec-test']
        for index, owner in enumerate(owners):
            with self.subTest(owner=owner):
                self.log.unlink(missing_ok=True)
                ready = self.root / f'{owner}.ready'
                process = subprocess.Popen(['bash', str(ROOT / 'bin/date-native-roster-migration-check')], cwd=self.root, env=dict(self.env, HANDOFF_BLOCK=owner, HANDOFF_READY=str(ready)), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
                try:
                    deadline = time.monotonic() + 5
                    while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(ready.exists(), 'producer did not reach its public boundary')
                    os.killpg(process.pid, signal.SIGTERM)
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertIn(process.returncode, [-signal.SIGTERM, 128 + signal.SIGTERM], stderr)
                    self.assertEqual(ready.with_suffix('.stopped').read_text(), str(signal.SIGTERM))
                    self.assertEqual([call['name'] for call in self.calls()], owners[:index + 1])
                    self.assertNotIn('date-native-roster-migration-check: ok', stdout)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate(timeout=5)

    def test_help_and_invalid_arguments_do_not_start_owners(self):
        self.assertEqual(self.run_check('--help').returncode, 0)
        self.assertNotEqual(self.run_check('--unexpected').returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
