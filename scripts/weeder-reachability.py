"""Advisory root-set comparisons over the existing fresh Weeder HIE sweep.

Not a second dead-code gate: the complete configuration/baseline remain owners.
Weeder does not expose paths through its graph; provenance here is root-set
membership, not a claimed unique caller or proof that a test seam is obsolete.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from datetime import datetime, timezone

INPUTS = (
    'weeder.toml',
    'Config/nix/production-module-inventory.tsv',
    'Config/nix/production-script-inventory.tsv',
    'Config/nix/production-executable-inventory.tsv',
    'Makefile',
    'Config/nix/weeder-baseline.tsv',
)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as handle:
        json.dump(value, handle, indent=2)
        handle.write('\n')
        temporary = Path(handle.name)
    temporary.replace(path)


def git_state():
    return {
        'revision': subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip(),
        'dirty': bool(subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True, check=True).stdout),
    }


def tool_identity():
    tools = {}
    for name in ('ghc', 'weeder'):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f'required tool unavailable: {name}')
        path = Path(executable).resolve()
        tools[name] = {'path': str(path), 'sha256': digest(path)}
    return tools


def current_sources():
    # Validate the complete shell owner's inventory, not a new compiler subject
    # selector. Additions outside a previously captured inventory are stale too.
    paths = {'Main.hs', 'WorkerMain.hs'}
    for root in ('Application', 'Web', 'Test', 'Config', 'build/Generated'):
        paths.update(str(path) for path in Path(root).rglob('*.hs')
                     if path.is_file() and not path.is_symlink()
                     and not str(path).startswith('Test/CompileFail/'))
    return paths


def validate_context(evidence):
    if git_state() != evidence['gitState']:
        raise ValueError('revision/dirty provenance changed since compiler sweep started')
    if tool_identity() != evidence['toolIdentity']:
        raise ValueError('toolchain changed since compiler sweep started')
    if digest(__file__) != evidence['analysisHash']:
        raise ValueError('analysis changed since compiler sweep started')
    if current_sources() != set(evidence['sources']):
        raise ValueError('source inventory changed since compiler sweep started')


def snapshot(sources, output):
    Path(output).unlink(missing_ok=True)
    paths = Path(sources).read_text().splitlines()
    if not paths or len(set(paths)) != len(paths):
        raise ValueError('empty or duplicate compiler source inventory')
    modules = {}
    for path in paths:
        match = re.search(r'^module\s+([A-Z][\w.]*)\b', Path(path).read_text(), re.M)
        if not match or match[1] in modules.values():
            raise ValueError(f'missing/duplicate module identity: {path}')
        modules[path] = match[1]
    write_json(output, {
        'gitState': git_state(), 'toolIdentity': tool_identity(),
        'analysisHash': digest(__file__),
        'sources': modules,
        'hashes': {path: digest(path) for path in [sources, *paths, *INPUTS, str(Path(sources).parent / 'ghc-options.sha256')]},
        'compilerVersion': subprocess.run(['ghc', '--numeric-version'], capture_output=True, text=True, check=True).stdout.strip(),
    })


def rows(path):
    with open(path) as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


def candidates(text):
    result = {}
    pending = ''
    for line in text.splitlines():
        if pending:
            if line.startswith('main: '):
                raise ValueError('malformed wrapped Weeder evidence')
            line = pending + line
            pending = ''
        if not line:
            continue
        match = re.fullmatch(r'main: (?:\./)?(.+):(\d+):(\d+): (.+)', line)
        if match:
            path, source_line, column, symbol = match.groups()
            key = (path, symbol)
            if key in result:
                raise ValueError(f'duplicate Weeder evidence: {key}')
            result[key] = {'source': path, 'line': int(source_line), 'column': int(column), 'symbol': symbol}
        elif line.startswith('main: '):
            pending = line
        else:
            raise ValueError(f'unrecognised Weeder output: {line[:200]}')
    if pending:
        raise ValueError('unfinished Weeder evidence')
    return result


def toml_value(value):
    if isinstance(value, dict):
        return '{' + ', '.join(f'{key} = {toml_value(item)}' for key, item in value.items()) + '}'
    if isinstance(value, list):
        return '[' + ', '.join(map(toml_value, value)) + ']'
    return json.dumps(value)


def analyse(args):
    evidence = json.loads(Path(args.snapshot).read_text())
    validate_context(evidence)
    for path, expected in evidence['hashes'].items():
        if digest(path) != expected:
            raise ValueError(f'input changed since compiler sweep started: {path}')
    hie = Path(args.hie)
    expected_hie = {hie / (module.replace('.', '/') + '.hie') for module in evidence['sources'].values()}
    actual_hie = set(hie.rglob('*.hie'))
    if actual_hie != expected_hie:
        raise ValueError('missing or stale/deleted-module HIE outside the compiler source inventory')
    # Trust the owner's completed GHC sweep, not timestamps: GHC legitimately
    # retains HIE when touched/restored source has identical content. The source
    # snapshot spans that sweep, and both source and HIE hashes span analysis.
    hie_hashes = {str(path): digest(path) for path in sorted(actual_hie)}
    full_output_hash = digest(args.full_output)
    policy = tomllib.loads(Path('weeder.toml').read_text())
    if policy.get('unused-types') is not False:
        raise ValueError('advisory requires the existing unused-types=false contract')
    # Root allocation uses only the common regex subset used by the canonical
    # policy. Do not silently interpret future POSIX classes/backreferences with
    # Python semantics instead of Weeder's TDFA engine; qualify as unavailable.
    for pattern in policy['roots']:
        simple = pattern.replace('[^.]', '')
        if not re.fullmatch(r'[A-Za-z0-9_.$^+*()|\\]+', simple) or re.search(r'\\(?![.\\])', pattern):
            raise ValueError(f'canonical root regex needs an explicit compatibility check: {pattern}')

    def run(name, config, directory):
        path = Path(directory) / f'{name}.toml'
        path.write_text('\n'.join(f'{key} = {toml_value(value)}' for key, value in config.items()) + '\n')
        result = subprocess.run(['weeder', '--config', str(path), '--no-default-fields', '--hie-directory', str(hie), '--require-hs-files'], capture_output=True, text=True, timeout=120)
        if result.returncode not in (0, 228):
            raise ValueError(f'Weeder {name} failed ({result.returncode}): {(result.stderr + result.stdout)[:4096]}')
        if result.stderr.strip():
            raise ValueError(f'Weeder {name} diagnostic: {result.stderr[:4096]}')
        return candidates(result.stdout)

    with tempfile.TemporaryDirectory(prefix='bepis-reachability-') as directory:
        universe = run('universe', {**policy, 'roots': [], 'root-modules': [], 'root-instances': [], 'type-class-roots': False}, directory)
        packaging = {row['path']: row['packaging'] for row in rows(INPUTS[1])}
        scripts = {row['script']: row for row in rows(INPUTS[2])}
        executables = rows(INPUTS[3])
        executable_names = {row['executable'] for row in executables}
        groups = {'production': [], 'test': [], 'development': []}
        resolved_patterns = set()
        for (path, symbol) in sorted(universe):
            module = evidence['sources'].get(path)
            if module is None:
                raise ValueError(f'Weeder source outside the compiled inventory: {path}')
            qualified = f'{module}.{symbol}'
            matched = [pattern for pattern in policy['roots'] if re.search(pattern, qualified)]
            if not matched:
                continue
            resolved_patterns.update(matched)
            entry = {'symbol': qualified, 'source': path, 'canonicalPatterns': matched}
            if module.startswith('Application.Script.'):
                owner = scripts[module.removeprefix('Application.Script.')]
                group = owner['packaging']
                if group == 'production' and owner['script'] not in executable_names:
                    raise ValueError(f'production script missing executable owner: {module}')
                entry['inventory'] = owner
            elif path.startswith('Test/'):
                group = 'test'
            else:
                group = packaging.get(path)
                if group not in ('production', 'development'):
                    raise ValueError(f'unclassified canonical value root: {qualified}')
            groups[group].append(entry)
        # Preserve canonical category policy in every comparison. Patterns with
        # no reportable value match (e.g. Paths_*) remain conservative roots.
        unresolved = [pattern for pattern in policy['roots'] if pattern not in resolved_patterns]
        category_policy = {**policy, 'roots': unresolved}
        category = run('category', category_policy, directory)
        comparisons = {}
        for group, roots in groups.items():
            comparisons[group] = run(group, {**category_policy, 'roots': unresolved + ['^' + re.escape(root['symbol']) + '$' for root in roots]}, directory)
        full = candidates(Path(args.full_output).read_text())
        if any(set(found) - set(universe) for found in [category, full, *comparisons.values()]):
            raise ValueError('comparison contains evidence outside the unrooted value universe')
        declarations = []
        for key, declaration in sorted(universe.items()):
            retained = [group for group, unreachable in comparisons.items() if key not in unreachable]
            if key not in category:
                status = 'category-retained/unknown'
            elif 'production' in retained:
                status = 'production-root-retained'
            elif key not in full and retained:
                status = 'test/development-retained'
            elif key in full:
                status = 'complete-gate-candidate'
            else:
                status = 'combined-root-retained/unknown'
            declarations.append({**declaration, 'classification': status, 'rootGroups': retained})

    # Do not publish comparisons spanning edits or a concurrent compiler sweep.
    for path, expected in {**evidence['hashes'], **hie_hashes, args.full_output: full_output_hash}.items():
        if digest(path) != expected:
            raise ValueError(f'evidence changed while analysing: {path}')
    validate_context(evidence)
    if set(hie.rglob('*.hie')) != expected_hie:
        raise ValueError('HIE inventory changed while analysing')
    return {
        'status': 'fresh', 'advisoryOnly': True, **evidence['gitState'],
        'toolIdentity': evidence['toolIdentity'],
        'compilerVersion': evidence['compilerVersion'],
        'capturedAt': datetime.now(timezone.utc).isoformat(),
        'inputHashes': evidence['hashes'], 'hieHashes': hie_hashes,
        'completeOutputHash': full_output_hash,
        'analysisHash': evidence['analysisHash'], 'roots': groups,
        'categoryPolicy': {key: value for key, value in category_policy.items() if key != 'unused-types'},
        'executables': executables,
        'limitations': [
            'Root-set provenance, not unique caller paths or proof of removability.',
            'Mandatory class/instance/generated roots are retained; their runtime reachability is conservative/unknown.',
            'Executable inventory owns packaging, not a value-symbol mapping for framework-generated server/worker mains; dynamic entrypoints remain category/unknown.',
            'Only Weeder-reportable values are classified. unused-types=false is unchanged.',
            'Test/development-retained means absent from production+category reachability, never automatically dead.',
        ],
        'declarations': declarations,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    capture = sub.add_parser('snapshot')
    capture.add_argument('sources')
    capture.add_argument('output')
    report = sub.add_parser('report')
    for name in ('snapshot', 'hie', 'full-output', 'output'):
        report.add_argument('--' + name, required=True)
    args = parser.parse_args()
    if args.command == 'snapshot':
        snapshot(args.sources, args.output)
    else:
        write_json(args.output, {'status': 'unavailable', 'advisoryOnly': True, 'reason': 'analysis in progress'})
        try:
            result = analyse(args)
        except Exception as error:
            result = {'status': 'unavailable', 'advisoryOnly': True, 'reason': str(error)[:4096]}
        write_json(args.output, result)
        print(f'weeder reachability advisory: {result["status"]} ({args.output})')
        if result['status'] == 'unavailable':
            print(result['reason'], file=sys.stderr)


if __name__ == '__main__':
    main()
