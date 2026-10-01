"""Real native artifact-lock command lifecycle; private processes/files only."""
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time
import unittest


class ArtifactCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = subprocess.check_output(
            ['./bin/tooling-run', 'artifacts', '--print-binary'], text=True).strip()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bepis-artifact-command-')
        self.root = Path(self.temporary.name)
        self.owners = []
        self.pidfds = []

    def tearDown(self):
        for fd in self.pidfds:
            try:
                signal.pidfd_send_signal(fd, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.close(fd)
        for owner in self.owners:
            if owner.poll() is None:
                owner.terminate()
            try:
                owner.communicate(timeout=6)
            except subprocess.TimeoutExpired:
                owner.kill()
                owner.communicate(timeout=2)
        self.temporary.cleanup()

    def arguments(self, command, lock='owner', nonblocking=False):
        return [self.binary, 'lock-exec', '--lock', str(self.root / lock)] + (
            ['--nonblocking'] if nonblocking else []) + ['--', *command]

    def run_command(self, command, **options):
        return subprocess.run(self.arguments(command, **options), capture_output=True,
                              text=True, timeout=6)

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while not predicate():
            self.assertLess(time.monotonic(), deadline, 'fixture deadline')
            time.sleep(0.01)

    def start(self, *, lock='owner', exit_on_signal=False, exit_normally=False, descendant=False):
        script = f'''
import os, pathlib, signal, sys, time
root = pathlib.Path({str(self.root)!r})
prefix = {lock!r}
def interrupted(number, frame):
    (root / (prefix + '.signal')).write_text(str(number))
    if {exit_on_signal!r}: sys.exit(0)
signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
if {descendant!r}:
    if os.fork() == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        (root / (prefix + '.descendant.pid')).write_text(str(os.getpid()))
        time.sleep(30)
        sys.exit(0)
    while not (root / (prefix + '.descendant.pid')).exists(): time.sleep(0.01)
(root / (prefix + '.pid')).write_text(str(os.getpid()))
if {exit_normally!r}: sys.exit(0)
time.sleep(30)
'''
        owner = subprocess.Popen(self.arguments(['python3', '-c', script], lock=lock),
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, start_new_session=True)
        self.owners.append(owner)
        self.wait_for(lambda: (self.root / (lock + '.pid')).exists())
        for suffix in ['.pid'] + (['.descendant.pid'] if descendant else []):
            self.pidfds.append(os.pidfd_open(int((self.root / (lock + suffix)).read_text())))
        return owner

    def assert_children_stopped(self):
        for fd in self.pidfds:
            self.assertTrue(select.select([fd], [], [], 0)[0], 'owned child still live')

    def test_status_output_and_launch_failure(self):
        result = self.run_command(['python3', '-c', 'import sys; print("out"); print("err",file=sys.stderr); sys.exit(7)'])
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, 'out\n')
        self.assertEqual(result.stderr, 'err\n')
        self.assertEqual(self.run_command(['/nonexistent/bepis-command']).returncode, 69)
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 0)

    def test_term_holds_lock_until_uncooperative_child_is_killed(self):
        owner = self.start()
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 75)
        owner.terminate()
        self.wait_for(lambda: (self.root / 'owner.signal').exists())
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 75)
        self.assertEqual(owner.wait(timeout=6), 143)
        self.assert_children_stopped()
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 0)

    def test_interrupt_is_not_success_when_child_handler_returns_zero(self):
        owner = self.start(exit_on_signal=True, descendant=True)
        owner.send_signal(signal.SIGINT)
        self.wait_for(lambda: (self.root / 'owner.signal').exists())
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 75)
        self.assertEqual(owner.wait(timeout=6), 130)
        self.assert_children_stopped()
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 0)

    def test_normal_leader_exit_stops_descendants_before_unlocking(self):
        owner = self.start(exit_normally=True, descendant=True)
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 75)
        self.assertEqual(owner.wait(timeout=6), 0)
        self.assert_children_stopped()
        self.assertEqual(self.run_command(['true'], nonblocking=True).returncode, 0)

    def test_other_lock_owner_is_not_signalled(self):
        owner = self.start()
        unrelated = self.start(lock='other')
        owner.terminate()
        self.assertEqual(owner.wait(timeout=6), 143)
        self.assertIsNone(unrelated.poll())
        self.assertFalse((self.root / 'other.signal').exists())
        unrelated.terminate()
        self.assertEqual(unrelated.wait(timeout=6), 143)
        self.assert_children_stopped()

    def test_cancelled_waiter_does_not_interrupt_holder(self):
        owner = self.start()
        waiter = subprocess.Popen(self.arguments(['true']), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.owners.append(waiter)
        time.sleep(0.05)
        self.assertIsNone(waiter.poll())
        waiter.terminate()
        self.assertNotEqual(waiter.wait(timeout=3), 0)
        self.assertIsNone(owner.poll())
        self.assertFalse((self.root / 'owner.signal').exists())
        owner.terminate()
        self.assertEqual(owner.wait(timeout=6), 143)


if __name__ == '__main__':
    unittest.main()
