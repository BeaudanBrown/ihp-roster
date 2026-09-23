"""Bounded diagnostic input snapshots, never cache or verification authority."""
import hashlib
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import time


MAX_BYTES = 16 * 1024 * 1024
MAX_FILES = 4096


def git_output(*arguments):
    """Bound both time and bytes while reading, not after buffering all stdout."""
    process = None
    try:
        process = subprocess.Popen(['git', *arguments], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                   env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'},
                                   start_new_session=True)
        assert process.stdout is not None
        deadline = time.monotonic() + 5
        value = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while time.monotonic() < deadline:
                if not selector.select(timeout=0.05):
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    if process.wait(timeout=max(0.001, deadline - time.monotonic())) == 0:
                        return bytes(value)
                    return None
                value.extend(chunk)
                if len(value) > MAX_BYTES:
                    return None
    except (OSError, subprocess.TimeoutExpired):
        pass
    finally:
        if process is not None:
            if process.returncode is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            if process.stdout is not None:
                process.stdout.close()
    return None


def empty_snapshot(state='unavailable'):
    return {'state': state, 'files': None, 'sha256': None}


def fingerprint(root, names, open_directory):
    """Hash names/modes/content without publishing names; reject unstable files."""
    try:
        digest, count, total = hashlib.sha256(), 0, 0
        for name in sorted(names):
            count += 1
            if count > MAX_FILES or name.is_absolute() or '..' in name.parts:
                raise ValueError('input inventory exceeds bounds')
            with open_directory(root / name.parent) as parent:
                fd = os.open(name.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                with os.fdopen(fd, 'rb') as handle:
                    before = os.fstat(handle.fileno())
                    if not stat.S_ISREG(before.st_mode) or total + before.st_size > MAX_BYTES:
                        raise ValueError('unsupported or oversized input')
                    encoded = os.fsencode(name)
                    digest.update(len(encoded).to_bytes(8, 'big'))
                    digest.update(encoded)
                    digest.update((before.st_mode & 0o777).to_bytes(2, 'big'))
                    digest.update(before.st_size.to_bytes(8, 'big'))
                    while chunk := handle.read(65536):
                        total += len(chunk)
                        if total > MAX_BYTES:
                            raise ValueError('input bytes exceed bounds')
                        digest.update(chunk)
                    after = os.fstat(handle.fileno())
                    current = os.stat(name.name, dir_fd=parent, follow_symlinks=False)
                    identity = lambda item: (item.st_dev, item.st_ino, item.st_size,
                                             item.st_mode, item.st_mtime_ns, item.st_ctime_ns)
                    if identity(before) != identity(after) or identity(after) != identity(current):
                        raise ValueError('input changed during capture')
        return {'state': 'captured', 'files': count, 'sha256': digest.hexdigest()}
    except (OSError, ValueError):
        return empty_snapshot()


def generated(root, relative, suffix, open_directory):
    path = root / relative
    try:
        # Checking via directory descriptors also rejects symlinked ancestors.
        with open_directory(path):
            pass
        names, visited = [], 0
        def failed(_error):
            raise ValueError('unreadable generated inventory')
        for current, directories, files in os.walk(path, onerror=failed, followlinks=False):
            visited += 1 + len(files)
            if visited > MAX_FILES:
                raise ValueError('generated traversal exceeds bounds')
            if any((Path(current) / child).is_symlink() for child in directories):
                raise ValueError('symlinked generated inventory')
            for name in files:
                if name.endswith(suffix) or name == '.bepis-input-hash':
                    names.append((Path(current) / name).relative_to(root))
                    if len(names) > MAX_FILES:
                        raise ValueError('generated inventory exceeds bounds')
        return fingerprint(root, names, open_directory)
    except FileNotFoundError:
        return empty_snapshot('absent')
    except (OSError, ValueError):
        return empty_snapshot()


def capture(open_directory):
    result = {'schemaVersion': 1, 'dirty': None, 'trackedDiffSha256': None,
              'untracked': empty_snapshot(), 'generatedHaskell': empty_snapshot(),
              'generatedFrontend': empty_snapshot()}
    raw_root = git_output('rev-parse', '--show-toplevel')
    if raw_root is None:
        return result
    root = Path(os.fsdecode(raw_root.rstrip(b'\n')))
    try:
        with open_directory(root):
            pass
    except (OSError, ValueError):
        return result
    status = git_output('-C', str(root), 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    diff = git_output('-C', str(root), 'diff', '--no-ext-diff', '--no-textconv', '--binary', 'HEAD', '--')
    untracked = git_output('-C', str(root), 'ls-files', '--others', '--exclude-standard', '-z')
    if status is not None:
        result['dirty'] = bool(status)
    if diff is not None:
        result['trackedDiffSha256'] = hashlib.sha256(diff).hexdigest()
    if (untracked is not None and untracked.count(b'\0') <= MAX_FILES
            and (not untracked or untracked.endswith(b'\0'))):
        names = [Path(os.fsdecode(name)) for name in untracked.split(b'\0') if name]
        result['untracked'] = fingerprint(root, names, open_directory)
    result['generatedHaskell'] = generated(root, 'build/Generated', '.hs', open_directory)
    result['generatedFrontend'] = generated(root, 'frontend/ts/generated', '.ts', open_directory)
    return result


def validate(value):
    keys = {'schemaVersion', 'dirty', 'trackedDiffSha256', 'untracked',
            'generatedHaskell', 'generatedFrontend'}
    def digest(item):
        return isinstance(item, str) and re.fullmatch(r'[0-9a-f]{64}', item) is not None
    if (set(value) != keys or type(value['schemaVersion']) is not int or value['schemaVersion'] != 1
            or (value['dirty'] is not None and type(value['dirty']) is not bool)
            or (value['trackedDiffSha256'] is not None and not digest(value['trackedDiffSha256']))):
        raise ValueError('invalid provenance')
    for key in ('untracked', 'generatedHaskell', 'generatedFrontend'):
        item = value[key]
        if not isinstance(item, dict) or set(item) != {'state', 'files', 'sha256'}:
            raise ValueError('invalid input snapshot')
        if item['state'] == 'captured':
            if type(item['files']) is not int or not 0 <= item['files'] <= MAX_FILES or not digest(item['sha256']):
                raise ValueError('invalid captured inputs')
        elif item['state'] not in ('absent', 'unavailable') or item['files'] is not None or item['sha256'] is not None:
            raise ValueError('invalid unavailable inputs')
        if key == 'untracked' and item['state'] == 'absent':
            raise ValueError('untracked inventory cannot be absent')
