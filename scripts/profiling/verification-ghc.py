#!/usr/bin/env python3
"""Opt-in GHC link-driver observation; never a compiler/cache owner."""
import ast
import json
import os
from pathlib import Path
import runpy
import shlex
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
PHASES = ('hspec-link', 'e2e-app-link', 'e2e-worker-link', 'e2e-stripe-link')
CONFIG = 'BEPIS_VERIFICATION_LINK_COMMAND'


def wait(command, environment=None):
    """Keep the caller's process group; forward direct cancellation and reap."""
    child = None
    pending = None

    def forward(signum, _frame):
        nonlocal pending
        pending = signum
        if child is not None:
            try:
                child.send_signal(signum)
            except ProcessLookupError:
                pass

    previous = {sig: signal.signal(sig, forward) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        child = subprocess.Popen(command, env=environment)
        if pending is not None:
            forward(pending, None)
        status = child.wait()
        return -pending if pending is not None else status
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def emit(phase, scope, edge):
    # Publishing diagnostics must not suppress linking or replace its result.
    try:
        recorder = runpy.run_path(str(Path(__file__).with_name('verification-measure.py')))
        recorder['event'](phase, scope, edge)
    except (OSError, ValueError):
        print('verification-ghc: link observation unavailable', file=sys.stderr)


def compile_observed(phase, scope, arguments):
    if not os.environ.get('BEPIS_VERIFICATION_EVENTS'):
        os.execvp('ghc', ['ghc', *arguments])
    try:
        if phase not in PHASES or not 0 <= int(scope) <= 65535:
            raise ValueError('invalid phase')
        # Do not guess the effective configuration of a caller-supplied toolchain.
        if any(arg.startswith(('-pgm', '-B')) for arg in arguments):
            raise ValueError('custom toolchain')
        info = subprocess.run(['ghc', '--info'], check=True, stdout=subprocess.PIPE, text=True).stdout
        if len(info) > 65536:
            raise ValueError('oversized compiler settings')
        settings = dict(ast.literal_eval(info))
        driver = settings['C compiler command']
        supports_no_pie = settings['C compiler supports -no-pie']
        if not os.path.isabs(driver) or not os.access(driver, os.X_OK) or supports_no_pie not in ('YES', 'NO'):
            raise ValueError('unknown compiler settings')
        # -pgml clears BOTH the configured flags and the supports-no-pie bit.
        # Restore them, leaving response files and all caller flags untouched.
        command = [driver, *shlex.split(settings['C compiler link flags'])]
        options = ['-pgml', str(Path(__file__).resolve())]
        if supports_no_pie == 'YES':
            options.append('-pgml-supports-no-pie')
        environment = {**os.environ, CONFIG: json.dumps(command),
                       'BEPIS_VERIFICATION_LINK_PHASE': phase, 'BEPIS_VERIFICATION_LINK_SCOPE': scope}
    except (OSError, ValueError, SyntaxError, KeyError, TypeError, subprocess.CalledProcessError):
        emit('ghc-link-observation-unavailable', 0, 'observe')
        print('verification-ghc: unsupported configuration; linking attribution unavailable', file=sys.stderr)
        os.execvp('ghc', ['ghc', *arguments])
    return wait(['ghc', *options, *arguments], environment)


def link(arguments):
    config = os.environ.get(CONFIG, '')
    if len(config) > 65536:
        raise ValueError('oversized configuration')
    command = json.loads(config)
    phase = os.environ['BEPIS_VERIFICATION_LINK_PHASE']
    scope = int(os.environ['BEPIS_VERIFICATION_LINK_SCOPE'])
    if (not isinstance(command, list) or not command or not all(isinstance(item, str) for item in command)
            or phase not in PHASES or not 0 <= scope <= 65535):
        raise ValueError('invalid configuration')
    emit(phase, scope, 'start')
    try:
        code = wait([*command, *arguments])
    except OSError:
        emit(phase, scope, 'fail')
        return 127
    emit(phase, scope, 'finish' if code == 0 else 'fail')
    return code


if __name__ == '__main__':
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == 'ghc':
            status = compile_observed(sys.argv[2], sys.argv[3], sys.argv[4:])
        else:
            status = link(sys.argv[1:])
    except (OSError, ValueError, KeyError):
        print('verification-ghc: cannot launch configured compiler/linker', file=sys.stderr)
        status = 127
    if status < 0:
        signal.signal(-status, signal.SIG_DFL)
        os.kill(os.getpid(), -status)
    sys.exit(status)
