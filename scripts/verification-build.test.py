"""Real compiler/image owner fixtures; no application runtime or test database."""
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = REPO / 'Config/nix/scripts'
ARTIFACTS = subprocess.check_output([str(REPO / 'bin/tooling-run'), 'artifacts', '--print-binary'], text=True).strip()


class VerificationBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bepis-verification-build-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.graph = self.root / 'graph'
        self.opts = '-i. -iTest'
        self.put('Makefile', 'print-ghc-options:\n\t@echo "-i."\n')
        self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = 1\n')
        for name in ('E2EAppMain', 'E2EWorkerMain', 'StripeProcessMockMain', 'HspecMain'):
            self.put(f'Test/{name}.hs', f'module Test.{name} where\nimport Shared\nmain :: IO ()\nmain = print value\n')
        self.put('Application/Script/GenerateBepisArchitectureContracts.hs', 'module Application.Script.GenerateBepisArchitectureContracts where\nimport Shared\nmain :: IO ()\nmain = print value\n')
        for name in ('ghc.sh', 'verification.sh'):
            self.link(SCRIPTS / 'lib' / name, 'helpers/lib/' + name)
        self.link(SCRIPTS / 'haskell/ghc-build-run', 'helpers/haskell/ghc-build-run')
        # Only unrelated model/scanner setup is stubbed; the typecheck owner,
        # native lock/process owner, GHC and all image publishers are real.
        for name in ('generated-ensure', 'module-name-check'):
            self.put('helpers/haskell/' + name, 'exit 0\n')
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.env = dict(os.environ, BEPIS_SCRIPTS_ROOT=str(self.root / 'helpers'),
                        IHP_ROSTER_ARTIFACTS_BINARY=ARTIFACTS, TYPECHECK_BUILD_DIR=str(self.graph))
        self.env.pop('BEPIS_VERIFICATION_EVENTS', None)

    def put(self, path, contents):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents)
        return target

    def link(self, source, path):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(source)

    def command(self, args, env=None):
        return subprocess.run(args, cwd=self.root, env=env or self.env, capture_output=True, text=True, timeout=30)

    def passes(self, args, env=None):
        result = self.command(args, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def owned(self, command, opts=None):
        return ['bash', str(SCRIPTS / 'haskell/ghc-build-run'), str(self.graph), opts or self.opts,
                'fixture-build-lock', '--', *command]

    def images(self, state='run', opts=None):
        return self.owned(['bash', str(SCRIPTS / 'e2e/build-images'), str(self.graph),
                           str(self.root / state), 'compiled', opts or self.opts], opts)

    def output(self, image):
        return self.passes([str(image)]).stdout.strip()

    def test_typecheck_cannot_write_or_prepare_while_graph_is_owned(self):
        command = ['bash', str(SCRIPTS / 'haskell/typecheck'), 'Shared.hs']
        self.passes(command)
        original = (self.graph / 'obj/Shared.o').read_bytes()
        self.put('Makefile', 'print-ghc-options:\n\t@echo "-i. -O1"\n')
        self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = 2\n')
        with Path(str(self.graph) + '.owner.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            child = subprocess.Popen(command, cwd=self.root, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                # Completion is the negative control, not a normal-flow sleep:
                # the old real owner completes instead of waiting for this lease.
                with self.assertRaises(subprocess.TimeoutExpired):
                    child.communicate(timeout=3)
                self.assertEqual((self.graph / 'obj/Shared.o').read_bytes(), original)
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
                stdout, stderr = child.communicate(timeout=30)
            self.assertEqual(child.returncode, 0, stdout + stderr)
        self.assertNotEqual((self.graph / 'obj/Shared.o').read_bytes(), original)

    def test_stable_images_reuse_links_but_snapshots_do_not_share_writes(self):
        self.passes(self.images())
        stable = self.graph / 'bin/RunE2EApp'
        private = self.root / 'run/build/RunE2EApp'
        self.assertNotEqual(stable.stat().st_ino, private.stat().st_ino)
        self.assertEqual(private.stat().st_nlink, 1)
        stamp = stable.stat().st_mtime_ns
        self.passes(self.images('second'))
        self.assertEqual(stable.stat().st_mtime_ns, stamp)
        self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = 2\n')
        self.passes(self.images('third'))
        self.assertEqual(self.output(private), '1')
        self.assertEqual(self.output(self.root / 'third/build/RunE2EApp'), '2')
        self.assertEqual(self.output(self.root / 'third/build/RunE2EWorker'), '2')
        self.assertEqual(self.output(self.root / 'third/build/StripeProcessMock'), '2')

    def test_hspec_and_architecture_snapshots_survive_later_graph_publication(self):
        hspec = ['bash', str(SCRIPTS / 'haskell/hspec-build-image'), str(self.graph), str(self.root / 'hspec'), self.opts]
        architecture = ['bash', str(SCRIPTS / 'architecture/build-image'), str(self.graph), self.opts, str(self.root / 'architecture-image')]
        self.passes(self.owned(hspec))
        self.passes(self.owned(architecture))
        self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = 3\n')
        self.passes(self.images())
        self.assertEqual(self.output(self.root / 'hspec/build/Main'), '1')
        self.assertEqual(self.output(self.root / 'architecture-image'), '1')
        self.assertEqual(self.output(self.root / 'run/build/RunE2EApp'), '3')

    def test_option_change_and_deleted_object_recompute_without_result_certificate(self):
        self.passes(self.images())
        (self.graph / 'obj/Shared.o').unlink()
        self.passes(self.images('replacement', self.opts + ' -O1'))
        self.assertTrue((self.graph / 'obj/Shared.o').is_file())
        self.assertEqual(self.output(self.root / 'replacement/build/RunE2EApp'), '1')
        self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = True\n')
        result = self.command(self.images('invalid'))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'invalid/build/RunE2EApp').exists())

    def test_running_snapshot_does_not_hold_graph_or_change_during_relink(self):
        self.put('Test/E2EAppMain.hs', 'module Test.E2EAppMain where\nimport Shared\nimport System.IO\nmain :: IO ()\nmain = do\n print value\n hFlush stdout\n _ <- getLine\n print value\n')
        self.passes(self.images())
        image = self.root / 'run/build/RunE2EApp'
        child = subprocess.Popen([str(image)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert child.stdout is not None
            self.assertEqual(child.stdout.readline().strip(), '1')
            self.put('Shared.hs', 'module Shared where\nvalue :: Int\nvalue = 4\n')
            self.passes(self.images('changed'))
            stdout, stderr = child.communicate('\n', timeout=5)
            self.assertEqual(child.returncode, 0, stderr)
            self.assertEqual(stdout.strip(), '1')
        finally:
            if child.poll() is None:
                child.kill()
                child.communicate()

    def test_native_linked_input_changes_and_compiler_failure_cannot_reuse_success(self):
        self.put('native.c', 'int nativeValue(void) { return 1; }\n')
        self.put('Shared.hs', 'module Shared where\nimport Foreign.C.Types\nimport System.IO.Unsafe\nforeign import ccall "nativeValue" nativeValue :: IO CInt\nvalue :: Int\nvalue = fromIntegral (unsafePerformIO nativeValue)\n')
        options = self.opts + ' -XForeignFunctionInterface native.c'
        self.passes(self.images(opts=options))
        self.put('native.c', 'int nativeValue(void) { return 7; }\n')
        self.passes(self.images('native-change', options))
        self.assertEqual(self.output(self.root / 'run/build/RunE2EApp'), '1')
        self.assertEqual(self.output(self.root / 'native-change/build/RunE2EApp'), '7')
        compiler = shutil.which('ghc')
        adapter = self.put('tools/ghc', f'#!/usr/bin/env bash\nif [[ "$*" == *"-main-is"* ]]; then exit 71; fi\nexec "{compiler}" "$@"\n')
        adapter.chmod(0o755)
        result = self.command(self.images('failed-compiler', options), dict(self.env, PATH=str(adapter.parent) + ':' + self.env['PATH']))
        self.assertEqual(result.returncode, 71)
        self.assertFalse((self.root / 'failed-compiler/build/RunE2EApp').exists())
        result = self.command(self.images('failed-package', options + ' -hide-package base'))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'failed-package/build/RunE2EApp').exists())

    def test_interrupted_copy_releases_only_after_owned_children_stop(self):
        real_cp = shutil.which('cp')
        self.assertIsNotNone(real_cp)
        marker = self.root / 'copy-started'
        adapter = self.put('tools/cp', f'#!/usr/bin/env bash\nprintf ready > "{marker}"\nsleep 30\nexec "{real_cp}" "$@"\n')
        adapter.chmod(0o755)
        env = dict(self.env, PATH=str(adapter.parent) + ':' + self.env['PATH'])
        child = subprocess.Popen(self.images(), cwd=self.root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 15
            while not marker.exists():
                self.assertIsNone(child.poll())
                self.assertLess(time.monotonic(), deadline)
                time.sleep(.01)
        finally:
            child.terminate()
            stdout, stderr = child.communicate(timeout=10)
        self.assertEqual(child.returncode, 143, stdout + stderr)
        self.assertFalse((self.root / 'run/build/RunE2EApp').exists())
        self.passes([ARTIFACTS, 'lock-exec', '--nonblocking', '--lock', str(self.graph) + '.owner.lock', '--', 'true'])
        self.passes(self.images('retry'))
        self.assertEqual(self.output(self.root / 'retry/build/RunE2EApp'), '1')


if __name__ == '__main__':
    unittest.main()
