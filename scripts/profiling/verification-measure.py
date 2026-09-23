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
import time

# Diagnostic capture must not create new source-tree inputs while inspecting it.
sys.dont_write_bytecode = True
import verification_provenance


MAX_ARTIFACT_BYTES = 65536
MAX_PHASE_EVENTS = 128
PHASES = ('compile', 'hspec-execution', 'database-create', 'database-drop', 'parallel-run')
EDGES = ('start', 'finish', 'fail', 'ready')


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
    publish_available(descriptor, [name], value)


def publish_available(descriptor, names, value):
    temporary = '.' + secrets.token_hex(8) + '.pending'
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
        for name in names:
            try:
                os.link(temporary, name, src_dir_fd=descriptor, dst_dir_fd=descriptor, follow_symlinks=False)
            except FileExistsError:
                continue
            os.fsync(descriptor)
            return
        raise FileExistsError('no unclaimed publication slot')
    finally:
        os.unlink(temporary, dir_fd=descriptor)


def phase_scope(value):
    try:
        scope = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('scope must be an integer from 0 to 65535') from error
    if not 0 <= scope <= 65535:
        raise argparse.ArgumentTypeError('scope must be an integer from 0 to 65535')
    return scope


def event(args):
    target = os.environ.get('BEPIS_VERIFICATION_EVENTS')
    if not target:
        return 0
    value = {'schemaVersion': 1, 'phase': args.phase, 'scope': args.scope,
             'edge': args.edge, 'atSeconds': time.monotonic()}
    with directory(target) as root:
        try:
            publish_available(root, (f'{index:03}.json' for index in range(MAX_PHASE_EVENTS)), value)
        except FileExistsError:
            try:
                publish(root, 'overflow.json', {'schemaVersion': 1, 'overflow': True})
            except FileExistsError:
                pass
            return 2
    return 0


def collect_phases(root, start, wall):
    events, invalid = [], 0
    for index in range(MAX_PHASE_EVENTS):
        try:
            value = read_artifact(root, f'{index:03}.json')
        except FileNotFoundError:
            continue
        except (OSError, ValueError):
            invalid += 1
            continue
        if (set(value) != {'schemaVersion', 'phase', 'scope', 'edge', 'atSeconds'}
                or type(value['schemaVersion']) is not int or value['schemaVersion'] != 1
                or value['phase'] not in PHASES or value['edge'] not in EDGES
                or type(value['scope']) is not int or not 0 <= value['scope'] <= 65535
                or not finite_number(value['atSeconds'])
                or not start <= value['atSeconds'] <= start + wall + 0.000001):
            invalid += 1
            continue
        events.append(value)
    overflow = False
    try:
        marker = read_artifact(root, 'overflow.json')
        overflow = True
        if marker != {'schemaVersion': 1, 'overflow': True}:
            invalid += 1
    except FileNotFoundError:
        pass
    except (OSError, ValueError):
        invalid += 1
    active, intervals = {}, []
    for value in sorted(events, key=lambda item: item['atSeconds']):
        key = (value['phase'], value['scope'])
        if value['edge'] == 'start':
            if key in active:
                invalid += 1
            else:
                active[key] = value['atSeconds']
        elif key not in active:
            invalid += 1
        else:
            began = active.pop(key)
            intervals.append({'phase': key[0], 'scope': key[1],
                              'status': {'finish': 'finished', 'fail': 'failed', 'ready': 'ready'}[value['edge']],
                              'offsetSeconds': began - start, 'durationSeconds': value['atSeconds'] - began})
    for (phase, scope), began in active.items():
        intervals.append({'phase': phase, 'scope': scope, 'status': 'unfinished',
                          'offsetSeconds': began - start, 'durationSeconds': None})
    return {'schemaVersion': 1, 'state': 'invalid' if invalid else 'truncated' if overflow else 'observed' if events else 'unavailable',
            'clockOriginSeconds': start, 'invalidEvents': invalid, 'overflow': overflow, 'intervals': intervals}


def validate_phases(value, wall):
    if (not finite_number(wall)
            or set(value) != {'schemaVersion', 'state', 'clockOriginSeconds', 'invalidEvents', 'overflow', 'intervals'}
            or not finite_number(value['clockOriginSeconds'])
            or type(value['schemaVersion']) is not int or value['schemaVersion'] != 1
            or type(value['invalidEvents']) is not int or value['invalidEvents'] < 0
            or type(value['overflow']) is not bool
            or not isinstance(value['intervals'], list) or len(value['intervals']) > MAX_PHASE_EVENTS):
        raise ValueError('invalid phase evidence')
    expected = ('invalid' if value['invalidEvents'] else 'truncated' if value['overflow']
                else 'observed' if value['intervals'] else 'unavailable')
    if value['state'] != expected or expected in ('invalid', 'truncated'):
        raise ValueError('invalid or truncated phase evidence')
    for item in value['intervals']:
        if (not isinstance(item, dict)
                or set(item) != {'phase', 'scope', 'status', 'offsetSeconds', 'durationSeconds'}
                or item['phase'] not in PHASES or type(item['scope']) is not int or not 0 <= item['scope'] <= 65535
                or item['status'] not in ('finished', 'failed', 'ready', 'unfinished')
                or not finite_number(item['offsetSeconds']) or item['offsetSeconds'] > wall + 0.000001
                or (item['status'] == 'unfinished' and item['durationSeconds'] is not None)
                or (item['status'] != 'unfinished' and
                    (not finite_number(item['durationSeconds']) or item['durationSeconds'] > wall - item['offsetSeconds'] + 0.000001))):
            raise ValueError('invalid phase interval')


def revision():
    # Metadata subprocesses finish before timing/resource collection begins.
    try:
        output = verification_provenance.git_output('rev-parse', 'HEAD')
        value = output.decode('ascii').strip() if output is not None else ''
        if re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', value):
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
    return type(value) in (int, float) and 0 <= value <= 1e18 and math.isfinite(value)


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
            or type(metadata['schemaVersion']) is not int or metadata['schemaVersion'] not in (1, 2, 3)
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
        metadata = read_artifact(root, 'metadata.json')
        validate_metadata(metadata, read_artifact(root, 'run.json'))
        if metadata['schemaVersion'] >= 2:
            verification_provenance.validate(read_artifact(root, 'provenance.json'))
        result = read_artifact(root, 'result.json')
        if metadata['schemaVersion'] >= 3:
            phases = read_artifact(root, 'phases.json')
            validate_phases(phases, result.get('wallSeconds'))
            with directory(Path(path) / 'events') as events_root:
                if collect_phases(events_root, phases['clockOriginSeconds'], result['wallSeconds']) != phases:
                    raise ValueError('phase journal disagrees with summary')
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


def execute(command, termination_grace_seconds, environment):
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
            process = subprocess.Popen(command, start_new_session=True, env=environment)
        except OSError:
            return 127, 'launch-failed', time.monotonic() - start, None, memory, start
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
            return 128 + interrupted, 'interrupted', wall, cpu, memory, start
        code = process.returncode if process.returncode >= 0 else 128 - process.returncode
        return code, 'passed' if code == 0 else 'failed', wall, cpu, memory, start
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
            'schemaVersion': 3, 'owner': args.owner, 'cacheState': args.cache_state,
            'revision': revision(),
            'capturedAt': datetime.now(timezone.utc).isoformat(),
            'commandSha256': hashlib.sha256(json.dumps(command).encode()).hexdigest(),
        })
        publish(root, 'provenance.json', verification_provenance.capture(directory))
        publish(root, 'run.json', {'schemaVersion': 1, 'state': 'started'})
        os.mkdir('events', mode=0o700, dir_fd=root)
        events_path = Path(args.output).absolute() / 'events'
        with directory(events_path) as events_root:
            environment = {**os.environ, 'BEPIS_VERIFICATION_EVENTS': str(events_path)}
            code, status, wall, cpu, memory, start = execute(command, args.termination_grace_seconds, environment)
            verify_directory(events_path, events_root)
            phases = collect_phases(events_root, start, wall)
        verify_directory(args.output, root)
        publish(root, 'phases.json', phases)
        publish(root, 'result.json', {
            'schemaVersion': 1, 'authority': 'diagnostic-only',
            'commandStatus': status,
            'measurementStatus': 'incomplete' if phases['state'] in ('invalid', 'truncated') else 'complete',
            'exitCode': code,
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
    emission = commands.add_parser('event')
    emission.add_argument('--phase', choices=PHASES, required=True)
    emission.add_argument('--scope', type=phase_scope, required=True)
    emission.add_argument('--edge', choices=EDGES, required=True)
    check = commands.add_parser('inspect')
    check.add_argument('output')
    args = parser.parse_args()
    try:
        if args.operation == 'event':
            return event(args)
        return run(args) if args.operation == 'run' else inspect(args.output)
    except (OSError, ValueError):
        print('verification-measure: capture failed; no valid completion implied', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
