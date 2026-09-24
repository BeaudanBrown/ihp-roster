#!/usr/bin/env python3
"""Opt-in diagnostic command evidence; never a verification certificate."""
from contextlib import contextmanager
import json
import os
import sys
import time

# Diagnostic capture must not create new source-tree inputs while inspecting it.
sys.dont_write_bytecode = True


MAX_ARTIFACT_BYTES = 65536
MAX_PHASE_EVENTS = 256
PHASES = ('compile', 'hspec-execution', 'database-create', 'database-drop', 'parallel-run',
          'e2e-app-compile', 'e2e-worker-compile', 'e2e-stripe-compile',
          'e2e-app-startup', 'e2e-worker-startup', 'e2e-stripe-startup',
          'e2e-database-create', 'e2e-database-drop', 'e2e-browser', 'e2e-parallel-run',
          'e2e-mailhog-startup', 'hspec-link', 'e2e-app-link', 'e2e-worker-link', 'e2e-stripe-link')
EDGES = ('start', 'finish', 'fail', 'ready')


@contextmanager
def directory(path, create=False):
    path = os.fspath(path)
    if '..' in path.split('/'):
        raise ValueError('invalid artifact directory')
    parts = ('/', *filter(None, os.path.abspath(path).split('/')))
    if len(parts) < 2:
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
    temporary = '.' + os.urandom(8).hex() + '.pending'
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
        raise ValueError('scope must be an integer from 0 to 65535') from error
    if not 0 <= scope <= 65535:
        raise ValueError('scope must be an integer from 0 to 65535')
    return scope


def event_cli(arguments):
    # Keep the high-frequency operation independent of capture/parser imports.
    import getopt

    try:
        options, remaining = getopt.getopt(arguments, 'h', ['help', 'phase=', 'scope=', 'edge=', 'if-unfinished'])
    except getopt.GetoptError as error:
        raise ValueError('invalid event options') from error
    if any(key in ('-h', '--help') for key, _ in options):
        print('usage: verification-measure.py event --phase {' + ','.join(PHASES)
              + '} --scope 0..65535 --edge {' + ','.join(EDGES) + '} [--if-unfinished (fail only, after producer reap)]')
        return 0
    conditional = any(key == '--if-unfinished' for key, _ in options)
    values = {key[2:]: value for key, value in options if key != '--if-unfinished'}
    if (remaining or set(values) != {'phase', 'scope', 'edge'}
            or values['phase'] not in PHASES or values['edge'] not in EDGES
            or (conditional and values['edge'] != 'fail')):
        raise ValueError('invalid event boundary')
    return event(values['phase'], phase_scope(values['scope']), values['edge'], conditional)


def event(phase, scope, edge, if_unfinished=False):
    target = os.environ.get('BEPIS_VERIFICATION_EVENTS')
    if not target:
        return 0
    value = {'schemaVersion': 1, 'phase': phase, 'scope': scope,
             'edge': edge, 'atSeconds': time.monotonic()}
    with directory(target) as root:
        if if_unfinished:
            # Only the owner of an exited/reaped producer may use this. It is
            # not a compare-and-swap against a concurrent same-scope publisher.
            phases = collect_phases(root, 0, None)
            if phases['state'] in ('invalid', 'truncated'):
                return 2
            if not any(item['phase'] == phase and item['scope'] == scope
                       and item['status'] == 'unfinished' for item in phases['intervals']):
                return 0
        try:
            publish_available(root, (f'{index:03}.json' for index in range(MAX_PHASE_EVENTS)), value)
        except FileExistsError:
            try:
                publish(root, 'overflow.json', {'schemaVersion': 1, 'overflow': True})
            except FileExistsError:
                pass
            return 2
    return 0


def watch_mailhog(args):
    import http.client
    import socket

    if (not 1 <= args.http_port <= 65535 or not 1 <= args.smtp_port <= 65535
            or not 1 <= args.pid <= 2147483647 or not finite_number(args.timeout_seconds)
            or not 0 < args.timeout_seconds <= 60):
        raise ValueError('invalid local observer bounds')
    if not os.environ.get('BEPIS_VERIFICATION_EVENTS'):
        return 0
    deadline = time.monotonic() + args.timeout_seconds
    while time.monotonic() < deadline:
        try:
            os.kill(args.pid, 0)
        except ProcessLookupError:
            event('e2e-mailhog-startup', args.scope, 'fail')
            return 1
        timeout = min(0.2, max(0.001, deadline - time.monotonic()))
        connection = http.client.HTTPConnection('127.0.0.1', args.http_port, timeout=timeout)
        try:
            # Fixed read-only endpoint, no proxies, response bodies or mail payloads.
            connection.request('GET', '/api/v2/messages?limit=0', headers={'Connection': 'close'})
            response = connection.getresponse()
            if response.status == 200:
                with socket.create_connection(('127.0.0.1', args.smtp_port), timeout=timeout) as smtp:
                    if smtp.recv(256).startswith((b'220 ', b'220-')):
                        smtp.sendall(b'QUIT\r\n')
                        return event('e2e-mailhog-startup', args.scope, 'ready')
        except (OSError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))
    # A diagnostic observation timeout is not proof that the service failed.
    return 2


def collect_phases(root, start, wall):
    events, unvalidated, invalid = [], [], 0
    for index in range(MAX_PHASE_EVENTS):
        try:
            value = read_artifact(root, f'{index:03}.json')
        except FileNotFoundError:
            continue
        except (OSError, ValueError):
            invalid += 1
            continue
        unvalidated.append(value)
    if wall is None:
        wall = time.monotonic() - start
    for value in unvalidated:
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


def validate_reset_summary(value):
    import re

    if (not isinstance(value, dict) or set(value) != {'schemaVersion', 'scope', 'overflow', 'suites', 'unattributed'}
            or type(value['schemaVersion']) is not int or value['schemaVersion'] != 1
            or type(value['scope']) is not int or not 0 <= value['scope'] <= 65535
            or type(value['overflow']) is not bool or value['overflow']
            or not isinstance(value['suites'], list) or len(value['suites']) > 256):
        raise ValueError('invalid reset summary')
    labels = set()
    for row in [*value['suites'], value['unattributed']]:
        named = row is not value['unattributed']
        if (not isinstance(row, dict)
                or set(row) != ({'suite'} if named else set()) | {'attempts', 'failures', 'durationNanoseconds'}
                or any(type(row[key]) is not int or not 0 <= row[key] <= 10**18
                       for key in ('attempts', 'failures', 'durationNanoseconds'))
                or row['failures'] > row['attempts']
                or (row['attempts'] == 0 and row['durationNanoseconds'] != 0)):
            raise ValueError('invalid reset counters')
        if named:
            if (not isinstance(row['suite'], str) or not re.fullmatch(r'[A-Z][A-Za-z0-9.-]{0,63}', row['suite'])
                    or row['suite'] in labels):
                raise ValueError('invalid reset suite')
            labels.add(row['suite'])


def reset_summary():
    raw = sys.stdin.buffer.read(MAX_ARTIFACT_BYTES + 1)
    if len(raw) > MAX_ARTIFACT_BYTES:
        raise ValueError('reset summary too large')
    value = json.loads(raw, object_pairs_hook=unique_object)
    validate_reset_summary(value)
    target = os.environ.get('BEPIS_VERIFICATION_EVENTS')
    if target:
        with directory(target) as root:
            try:
                publish_available(root, (f'reset-{index:03}.json' for index in range(64)), value)
            except FileExistsError:
                try:
                    publish(root, 'reset-overflow.json', {'schemaVersion': 1, 'overflow': True})
                except FileExistsError:
                    pass
                return 2
    return 0


def collect_resets(root, phases):
    summaries, invalid, seen = [], 0, set()
    for index in range(64):
        try:
            value = read_artifact(root, f'reset-{index:03}.json')
            validate_reset_summary(value)
            if value['scope'] in seen:
                raise ValueError('duplicate reset scope')
            seen.add(value['scope'])
            summaries.append(value)
        except FileNotFoundError:
            continue
        except (OSError, ValueError):
            invalid += 1
    try:
        read_artifact(root, 'reset-overflow.json')
        invalid += 1
    except FileNotFoundError:
        pass
    except (OSError, ValueError):
        invalid += 1
    expected = {item['scope'] for item in phases['intervals'] if item['phase'] == 'hspec-execution'}
    missing = sorted(expected - seen)
    if sum(len(value['suites']) for value in summaries) > 256:
        invalid += 1
        summaries = []
    return {'schemaVersion': 1, 'state': 'invalid' if invalid else 'partial' if missing and seen else 'observed' if seen else 'unavailable',
            'invalidSummaries': invalid, 'missingScopes': missing, 'summaries': summaries}


def revision():
    import re
    import verification_provenance

    # Metadata subprocesses finish before timing/resource collection begins.
    try:
        output = verification_provenance.git_output('rev-parse', 'HEAD')
        value = output.decode('ascii').strip() if output is not None else ''
        if re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', value):
            return value
    except (OSError, UnicodeError):
        pass
    return None


def tree_rss(root):
    """Sum live descendants in one sweep, not per-process historical maxima.

    Shared pages can be counted more than once; short-lived, reparented or
    detached service work can be missed. Missing samples are never zero bytes.
    """
    from pathlib import Path

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
    import math

    return type(value) in (int, float) and 0 <= value <= 1e18 and math.isfinite(value)


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('duplicate JSON field')
        value[key] = item
    return value


def read_artifact(root, name):
    import stat

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
    from datetime import datetime
    import re

    if (set(metadata) != {'schemaVersion', 'owner', 'cacheState', 'revision', 'capturedAt', 'commandSha256'}
            or type(metadata['schemaVersion']) is not int or metadata['schemaVersion'] not in (1, 2, 3, 4)
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
    from pathlib import Path
    import verification_provenance

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
                if metadata['schemaVersion'] >= 4:
                    resets = read_artifact(root, 'resets.json')
                    if resets != collect_resets(events_root, phases) or resets['state'] == 'invalid':
                        raise ValueError('invalid reset journal or summary')
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
    import signal
    import subprocess

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
    from datetime import datetime, timezone
    import hashlib
    from pathlib import Path
    import re
    import verification_provenance

    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        raise ValueError('command required')
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', args.owner):
        raise ValueError('invalid public owner label')
    with directory(args.output, create=True) as root:
        publish(root, 'metadata.json', {
            'schemaVersion': 4, 'owner': args.owner, 'cacheState': args.cache_state,
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
            resets = collect_resets(events_root, phases)
        verify_directory(args.output, root)
        publish(root, 'phases.json', phases)
        publish(root, 'resets.json', resets)
        publish(root, 'result.json', {
            'schemaVersion': 1, 'authority': 'diagnostic-only',
            'commandStatus': status,
            'measurementStatus': 'incomplete' if phases['state'] in ('invalid', 'truncated') or resets['state'] == 'invalid' else 'complete',
            'exitCode': code,
            'wallSeconds': wall, 'cpuSeconds': cpu,
            'cpuScope': 'waited-command-and-waited-descendants', 'memory': memory,
        })
        verify_directory(args.output, root)
        return code


def parse_command():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    capture = commands.add_parser('run')
    capture.add_argument('--output', required=True)
    capture.add_argument('--owner', required=True)
    capture.add_argument('--cache-state', choices=['retained', 'warm', 'output-cold'], required=True)
    capture.add_argument('--termination-grace-seconds', type=int, choices=range(1, 61), default=10)
    capture.add_argument('command', nargs=argparse.REMAINDER)
    commands.add_parser('event', help='emit a bounded phase boundary')
    commands.add_parser('reset-summary', help='publish one bounded native shard reset aggregate from stdin')
    observer = commands.add_parser('watch-mailhog', help='observe isolated MailHog readiness without gating tests')
    observer.add_argument('--http-port', type=int, required=True)
    observer.add_argument('--smtp-port', type=int, required=True)
    observer.add_argument('--pid', type=int, required=True)
    observer.add_argument('--scope', type=phase_scope, default=0)
    observer.add_argument('--timeout-seconds', type=float, default=30)
    check = commands.add_parser('inspect')
    check.add_argument('output')
    return parser.parse_args()


def main():
    try:
        if len(sys.argv) > 1 and sys.argv[1] == 'event':
            return event_cli(sys.argv[2:])
        args = parse_command()
        if args.operation == 'reset-summary':
            return reset_summary()
        if args.operation == 'watch-mailhog':
            return watch_mailhog(args)
        return run(args) if args.operation == 'run' else inspect(args.output)
    except (OSError, ValueError):
        print('verification-measure: capture failed; no valid completion implied', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
