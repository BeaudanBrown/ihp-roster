#!/usr/bin/env python3
"""Opt-in diagnostic command evidence; never a verification certificate."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
import time


MAX_ARTIFACT_BYTES = 65536


@contextmanager
def directory(path, create=False):
    parts = Path(path).absolute().parts
    if '..' in parts or len(parts) < 2:
        raise ValueError('invalid artifact directory')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    descriptor = os.open('/', flags)
    try:
        for index, part in enumerate(parts[1:], 1):
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    if index == len(parts) - 1:
                        raise
            child = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        yield descriptor
    finally:
        os.close(descriptor)


def verify_directory(path, descriptor):
    with directory(path) as current:
        left, right = os.fstat(current), os.fstat(descriptor)
        if (left.st_dev, left.st_ino) != (right.st_dev, right.st_ino):
            raise ValueError('artifact directory replaced')


def publish(descriptor, name, value):
    temporary = '.' + name + '.' + secrets.token_hex(8) + '.pending'
    encoded = json.dumps(value, indent=2, allow_nan=False).encode() + b'\n'
    if len(encoded) > MAX_ARTIFACT_BYTES:
        raise ValueError('artifact too large')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    with os.fdopen(os.open(temporary, flags, 0o600, dir_fd=descriptor), 'wb') as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())
    try:
        # Atomic create-only publication: never replace another writer's file.
        os.link(temporary, name, src_dir_fd=descriptor, dst_dir_fd=descriptor, follow_symlinks=False)
        os.fsync(descriptor)
    finally:
        os.unlink(temporary, dir_fd=descriptor)


def revision():
    # Metadata subprocesses finish before timing/resource collection begins.
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=output,
                                    stderr=subprocess.DEVNULL, timeout=5, check=False)
            output.seek(0)
            value = output.read(128).decode('ascii').strip()
        if result.returncode == 0 and re.fullmatch(r'[0-9a-f]{40,64}', value):
            return value
    except (OSError, UnicodeError, subprocess.TimeoutExpired):
        pass
    return None


def tree_rss(root):
    """Sum live descendants in one sweep, not per-process historical maxima.

    Shared pages can be counted more than once; short-lived, reparented or
    detached service work can be missed. Missing samples are never zero bytes.
    """
    pending, seen, total, partial = [root], set(), 0, False
    while pending:
        pid = pending.pop()
        if pid in seen:
            continue
        seen.add(pid)
        try:
            stat = Path(f'/proc/{pid}/stat').read_text()
            fields = stat[stat.rfind(')') + 2:].split()
            total += int(fields[21]) * os.sysconf('SC_PAGE_SIZE')
            for task in Path(f'/proc/{pid}/task').iterdir():
                pending.extend(int(child) for child in (task / 'children').read_text().split())
        except (OSError, ValueError, IndexError):
            partial = True
    return (total if total else None), partial


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('duplicate JSON field')
        value[key] = item
    return value


def read_artifact(root, name):
    descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=root)
    with os.fdopen(descriptor, 'rb') as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError('artifact is not a regular file')
        raw = handle.read(MAX_ARTIFACT_BYTES + 1)
    if len(raw) > MAX_ARTIFACT_BYTES:
        raise ValueError('artifact too large')
    value = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(value, dict):
        raise ValueError('invalid artifact')
    return value


def validate_metadata(metadata, lifecycle):
    if (set(metadata) != {'schemaVersion', 'owner', 'cacheState', 'revision', 'capturedAt', 'commandSha256'}
            or type(metadata['schemaVersion']) is not int or metadata['schemaVersion'] != 1
            or not isinstance(metadata['owner'], str)
            or not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', metadata['owner'])
            or metadata['cacheState'] not in ('retained', 'warm', 'output-cold')
            or not isinstance(metadata['commandSha256'], str)
            or not re.fullmatch(r'[0-9a-f]{64}', metadata['commandSha256'])
            or not isinstance(metadata['capturedAt'], str)
            or (metadata['revision'] is not None and
                (not isinstance(metadata['revision'], str) or
                 not re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', metadata['revision'])))):
        raise ValueError('invalid metadata')
    if datetime.fromisoformat(metadata['capturedAt']).tzinfo is None:
        raise ValueError('timestamp lacks timezone')
    if (set(lifecycle) != {'schemaVersion', 'state'} or type(lifecycle['schemaVersion']) is not int
            or lifecycle['schemaVersion'] != 1 or lifecycle['state'] != 'started'):
        raise ValueError('invalid lifecycle')


def inspect(path):
    with directory(path) as root:
        validate_metadata(read_artifact(root, 'metadata.json'), read_artifact(root, 'run.json'))
        result = read_artifact(root, 'result.json')
        verify_directory(path, root)
    wall = result.get('wallSeconds')
    code = result.get('exitCode')
    memory = result.get('memory')
    cpu = result.get('cpuSeconds')
    if (set(result) != {'schemaVersion', 'authority', 'commandStatus', 'measurementStatus',
                        'exitCode', 'wallSeconds', 'cpuSeconds', 'cpuScope', 'memory'}
            or type(result.get('schemaVersion')) is not int or result['schemaVersion'] != 1 or result.get('authority') != 'diagnostic-only'
            or result.get('measurementStatus') != 'complete'
            or type(code) is not int or not 0 <= code <= 255
            or not finite_number(wall)
            or (cpu is not None and not finite_number(cpu))
            or (cpu is None and result.get('commandStatus') != 'launch-failed')
            or result.get('cpuScope') != 'waited-command-and-waited-descendants'
            or result.get('commandStatus') not in ('passed', 'failed', 'launch-failed', 'interrupted')
            or (result.get('commandStatus') == 'launch-failed' and code != 127)
            or (result.get('commandStatus') == 'interrupted' and code not in (130, 143))
            or (result['commandStatus'] == 'passed') != (code == 0)):
        raise ValueError('invalid or incomplete result')
    if (not isinstance(memory, dict)
            or set(memory) != {'method', 'peakBytes', 'samples', 'partialSamples'}
            or memory.get('method') != 'sampled-simultaneous-tree-rss'
            or type(memory.get('samples')) is not int or memory['samples'] < 0
            or type(memory.get('partialSamples')) is not int or memory['partialSamples'] < 0
            or (memory.get('peakBytes') is not None and
                (type(memory['peakBytes']) is not int or memory['peakBytes'] < 0))
            or (memory['samples'] == 0) != (memory.get('peakBytes') is None)):
        raise ValueError('invalid resource evidence')
    print(json.dumps(result, allow_nan=False))
    return code


def execute(command, termination_grace_seconds):
    process = None
    interrupted = None
    interrupted_at = None

    def forward(signum, _frame):
        nonlocal interrupted, interrupted_at
        if interrupted is None:
            interrupted, interrupted_at = signum, time.monotonic()
        if process is not None:
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass

    previous = {sig: signal.signal(sig, forward) for sig in (signal.SIGINT, signal.SIGTERM)}
    memory = {'method': 'sampled-simultaneous-tree-rss', 'peakBytes': None,
              'samples': 0, 'partialSamples': 0}
    next_sample = 0
    start = time.monotonic()
    try:
        try:
            process = subprocess.Popen(command, start_new_session=True)
        except OSError:
            return 127, 'launch-failed', time.monotonic() - start, None, memory
        if interrupted is not None:
            forward(interrupted, None)
        while True:
            pid, status, usage = os.wait4(process.pid, os.WNOHANG)
            if pid:
                process.returncode = os.waitstatus_to_exitcode(status)
                wall = time.monotonic() - start
                cpu = usage.ru_utime + usage.ru_stime
                break
            if time.monotonic() >= next_sample:
                rss, partial = tree_rss(process.pid)
                if rss is not None:
                    memory['peakBytes'] = max(memory['peakBytes'] or 0, rss)
                    memory['samples'] += 1
                memory['partialSamples'] += int(partial)
                next_sample = time.monotonic() + 0.1
            if interrupted_at is not None and time.monotonic() - interrupted_at >= termination_grace_seconds:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            time.sleep(0.02)
        if interrupted is not None:
            # Only our newly created process group; never unrelated host services.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            return 128 + interrupted, 'interrupted', wall, cpu, memory
        code = process.returncode if process.returncode >= 0 else 128 - process.returncode
        return code, 'passed' if code == 0 else 'failed', wall, cpu, memory
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def run(args):
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        raise ValueError('command required')
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', args.owner):
        raise ValueError('invalid public owner label')
    with directory(args.output, create=True) as root:
        publish(root, 'metadata.json', {
            'schemaVersion': 1, 'owner': args.owner, 'cacheState': args.cache_state,
            'revision': revision(),
            'capturedAt': datetime.now(timezone.utc).isoformat(),
            'commandSha256': hashlib.sha256(json.dumps(command).encode()).hexdigest(),
        })
        publish(root, 'run.json', {'schemaVersion': 1, 'state': 'started'})
        code, status, wall, cpu, memory = execute(command, args.termination_grace_seconds)
        verify_directory(args.output, root)
        publish(root, 'result.json', {
            'schemaVersion': 1, 'authority': 'diagnostic-only',
            'commandStatus': status,
            'measurementStatus': 'complete', 'exitCode': code,
            'wallSeconds': wall, 'cpuSeconds': cpu,
            'cpuScope': 'waited-command-and-waited-descendants', 'memory': memory,
        })
        verify_directory(args.output, root)
        return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    capture = commands.add_parser('run')
    capture.add_argument('--output', required=True)
    capture.add_argument('--owner', required=True)
    capture.add_argument('--cache-state', choices=['retained', 'warm', 'output-cold'], required=True)
    capture.add_argument('--termination-grace-seconds', type=int, choices=range(1, 61), default=10)
    capture.add_argument('command', nargs=argparse.REMAINDER)
    check = commands.add_parser('inspect')
    check.add_argument('output')
    args = parser.parse_args()
    try:
        return run(args) if args.operation == 'run' else inspect(args.output)
    except (OSError, ValueError):
        print('verification-measure: capture failed; no valid completion implied', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
