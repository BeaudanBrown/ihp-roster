import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repo = fileURLToPath(new URL('../', import.meta.url));
const scripts = join(repo, 'Config/nix/scripts');
const hlint = spawnSync('bash', ['-c', 'command -v hlint'], { encoding: 'utf8' }).stdout.trim();

function put(root, path, contents, mode = 0o600) {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, contents, { mode });
}

function fixture(t, module, body) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-error-boundary-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    for (const path of ['.hlint.yaml', 'Application/Error/Types.hs', 'Application/Error/Types/Internal.hs',
        'Test/CompileFail/ApplicationErrorEitherTextBoundary.hs']) {
        put(root, path, readFileSync(join(repo, path)));
    }
    const subject = `${module.replaceAll('.', '/')}.hs`;
    put(root, subject, `module ${module} where\n${body}\n`);
    put(root, 'Config/nix/production-module-inventory.tsv', `path\tpackaging\n${subject}\tproduction\n`);
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -XNoImplicitPrelude -XOverloadedStrings"\n');
    // Inventory ownership is a separate gate. The actual HLint, project policy,
    // typed-error script and negative GHC fixture all execute here unchanged.
    put(root, 'bin/production-manifest-check', '#!/usr/bin/env bash\nexit 0\n', 0o700);
    return { root, subject };
}

function run({ root }) {
    const result = spawnSync('bash', [join(scripts, 'haskell/typed-error-boundary-check')], {
        cwd: root,
        env: { ...process.env, BEPIS_SCRIPTS_ROOT: scripts,
            PATH: `${join(root, 'bin')}:${process.env.PATH}` },
        encoding: 'utf8', timeout: 30_000,
    });
    assert.ifError(result.error);
    return result;
}

test('scoped restriction scan preserves every default-HLint diagnostic, including qualified and unapplied uses', (t) => {
    const primitives = ['error', 'fail', 'ioError', 'userError', 'undefined', 'fromJust',
        'head', 'tail', 'init', 'last', '(!!)', 'read', 'foldl1', 'foldr1', 'maximum', 'minimum'];
    const input = fixture(t, 'Application.Subject', 'import qualified Prelude as P\n'
        + primitives.map((name, i) => `bad${i} = ${name}`).join('\n')
        + '\nqualifiedFailure = P.error "failure"');
    const original = spawnSync(hlint, ['-XQuasiQuotes', '--only=Avoid restricted function', '--json', input.subject], {
        cwd: input.root, encoding: 'utf8', timeout: 30_000,
    });
    assert.ifError(original.error);
    assert.equal(original.status, 1, original.stderr);
    const expected = JSON.parse(original.stdout);
    assert.equal(expected.length, primitives.length + 1);
    const actual = run(input);
    assert.equal(actual.status, 1, actual.stderr);
    assert.deepEqual(JSON.parse(actual.stdout), expected);
});

for (const [module, body] of [
    ['Application.Error.Startup', 'approved = error "startup"'],
    ['Application.Error.Runtime', 'approved = error "invariant"'],
    ['Application.Error.Parser', 'approved = fail "parser"'],
    ['Application.Subject', 'total [] = Nothing\ntotal (x:_) = Just x'],
]) {
    test(`the real gate retains ${module} policy and rejects the real Either Text boundary fixture`, (t) => {
        const result = run(fixture(t, module, body));
        assert.equal(result.status, 0, result.stderr);
        assert.match(result.stdout, /AppResult rejects Either Text/);
    });
}

test('malformed source cannot pass a restriction-only scan', (t) => {
    const result = run(fixture(t, 'Application.Subject', 'broken = ('));
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /Parse error/);
});

test('missing project restriction policy fails instead of falling back to shipped defaults', (t) => {
    const input = fixture(t, 'Application.Subject', 'bad = head []');
    rmSync(join(input.root, '.hlint.yaml'));
    assert.notEqual(run(input).status, 0);
});

test('malformed scanner output and execution failure cannot become an empty restriction inventory', (t) => {
    const input = fixture(t, 'Application.Subject', 'safe = ()');
    for (const command of ["printf '{}'", "printf 'not JSON'", 'exit 42']) {
        put(input.root, 'bin/hlint', `#!/usr/bin/env bash\n${command}\n`, 0o700);
        assert.notEqual(run(input).status, 0);
    }
});
