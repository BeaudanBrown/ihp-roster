import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repo = fileURLToPath(new URL('../', import.meta.url));
const resolveCommand = (name) => execFileSync('bash', ['-c', 'command -v "$1"', 'probe', name], { encoding: 'utf8' }).trim();
const bash = resolveCommand('bash');
const rg = resolveCommand('rg');
const entrypoints = ['frontend-surface-guardrails', 'typed-contract-authority-check'].map((name) => ({ name, path: resolveCommand(name) }));
// Derive fixture topology from tracked source, not a second gate inventory.
const sources = execFileSync('git', ['ls-files', '-z'], { cwd: repo, encoding: 'utf8' }).split('\0').filter(Boolean);

function put(root, path, text, mode = 0o644) {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text, { mode });
}

function fixture(t, { checkout = true } = {}) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-authority-fixture-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    if (checkout) {
        for (const path of sources) {
            const target = join(root, path);
            mkdirSync(dirname(target), { recursive: true });
            copyFileSync(join(repo, path), target);
        }
    }
    mkdirSync(join(root, 'scan-temp'));
    mkdirSync(join(root, 'stub-bin'));
    // These independent authorities are outside scanner execution coverage.
    for (const command of ['enum-authority-check', 'node']) {
        put(root, `stub-bin/${command}`, `#!${bash}\nexit 0\n`, 0o755);
    }
    return root;
}

function env(root, path = `${join(root, 'stub-bin')}:${process.env.PATH}`) {
    return { ...process.env, FRONTEND_REPO_ROOT: root, TYPED_AUTHORITY_REPO_ROOT: root, TMPDIR: join(root, 'scan-temp'), PATH: path };
}

function run(root, entrypoint, path) {
    const result = spawnSync(entrypoint.path, [], { cwd: root, env: env(root, path), encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
    assert.ifError(result.error);
    assert.deepEqual(readdirSync(join(root, 'scan-temp')), [], 'scanner temporary files leaked');
    return result;
}

function clean(result) {
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /frontend-surface-guardrails: ok|typed-contract-authority-check: zero bypasses/);
}

function failed(result, errorPattern) {
    assert.notEqual(result.status, 0, result.stdout);
    assert.doesNotMatch(result.stdout, /frontend-surface-guardrails: ok|typed-contract-authority-check: zero bypasses/);
    assert.match(result.stderr, errorPattern);
}

function stubRg(root, body) {
    put(root, 'stub-bin/rg', `#!${bash}\n${body}\n`, 0o755);
}

test('primitive distinguishes successful empty/matching output from regex and read errors', (t) => {
    const root = fixture(t, { checkout: false });
    put(root, 'input.txt', 'forbidden\n');
    for (const [pattern, input, status, stdout] of [
        ['clean', 'input.txt', 0, ''],
        ['forbidden', 'input.txt', 0, 'forbidden\n'],
        ['[', 'input.txt', 2, ''],
        ['forbidden', 'missing.txt', 2, ''],
    ]) {
        const result = spawnSync(bash, ['-c', '. "$1"; shift; authority_scan rg "$@"', 'probe', join(repo, 'Config/nix/scripts/lib/authority-scan.sh'), pattern, input], { cwd: root, env: env(root), encoding: 'utf8' });
        assert.equal(result.status, status, result.stderr);
        assert.equal(result.stdout, stdout);
        if (status !== 0) assert.match(result.stderr, /rg scan failed/);
        assert.deepEqual(readdirSync(join(root, 'scan-temp')), []);
    }
});

test('primitive cleans temporary stderr when its process group is terminated', async (t) => {
    const root = fixture(t, { checkout: false });
    const ready = join(root, 'ready');
    stubRg(root, `printf ready > '${ready}'\nread -r ignored`);
    const child = spawn(bash, ['-c', '. "$1"; authority_scan rg fixture', 'probe', join(repo, 'Config/nix/scripts/lib/authority-scan.sh')], { cwd: root, env: env(root), detached: true });
    t.after(() => {
        if (child.exitCode === null && child.signalCode === null) process.kill(-child.pid, 'SIGKILL');
    });
    const closed = new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
    const deadline = Date.now() + 5000;
    while (!existsSync(ready) && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 10));
    assert.ok(existsSync(ready), 'stub scanner did not start');
    process.kill(-child.pid, 'SIGTERM');
    await closed;
    assert.deepEqual(readdirSync(join(root, 'scan-temp')), []);
});

for (const entrypoint of entrypoints) {
    test(`${entrypoint.name}: real wrapper accepts clean source and absent optional tombstones`, (t) => {
        clean(run(fixture(t), entrypoint));
    });

    test(`${entrypoint.name}: real wrapper rejects a forbidden match with line diagnostics`, (t) => {
        const root = fixture(t);
        put(root, 'Web/ScannerFixture.hs', 'module ScannerFixture where\nforbidden = frontendSurfaceAction\n');
        failed(run(root, entrypoint), /Web\/ScannerFixture\.hs:2:/);
    });

    test(`${entrypoint.name}: real wrapper preserves generated exclusions`, (t) => {
        const root = fixture(t);
        if (entrypoint.name === 'frontend-surface-guardrails') {
            put(root, 'frontend/ts/generated/scanner-excluded.ts', 'data-passkey-management\n');
        } else {
            put(root, 'Application/Helper/FrontendContract/Fixture/Generated/Excluded.hs', "Field FeedbackTypeField 'WireText\n");
        }
        clean(run(root, entrypoint));
    });

    test(`${entrypoint.name}: missing rg is fatal, not a clean scan`, (t) => {
        const root = fixture(t);
        const tools = join(root, 'without-rg');
        mkdirSync(tools);
        for (const name of ['bash', 'mktemp', 'head', 'rm']) symlinkSync(resolveCommand(name), join(tools, name));
        failed(run(root, entrypoint, tools), /rg scan failed \(status 127\)/);
    });

    test(`${entrypoint.name}: real wrapper propagates an invalid regex from rg`, (t) => {
        const root = fixture(t);
        stubRg(root, `exec '${rg}' -e '[' "$@"`);
        failed(run(root, entrypoint), /regex parse error/);
    });

    test(`${entrypoint.name}: partial matches do not mask read errors; diagnostics are bounded`, (t) => {
        const root = fixture(t);
        stubRg(root, "printf 'partial match\\n'; printf 'fixture read error: ' >&2; printf '%06000d' 0 >&2; exit 2");
        const result = run(root, entrypoint);
        failed(result, /rg scan failed \(status 2\).*\nfixture read error:/);
        assert.ok(Buffer.byteLength(result.stderr) < 4500, 'unbounded scanner stderr');
    });

    test(`${entrypoint.name}: missing required scan roots are fatal`, (t) => {
        const root = fixture(t);
        const required = entrypoint.name === 'frontend-surface-guardrails' ? 'Web' : 'Application/Schema.sql';
        rmSync(join(root, required), { recursive: true, force: true });
        failed(run(root, entrypoint), /rg scan failed \(status 2\)/);
    });
}

test('typed wrapper rejects an unreadable required Weeder inventory instead of hiding grep errors', (t) => {
    const root = fixture(t);
    rmSync(join(root, 'Config/nix/weeder-baseline.tsv'));
    failed(run(root, entrypoints[1]), /grep scan failed \(status 2\)/);
});

test('surface wrapper scans the explicitly included generated contract', (t) => {
    const root = fixture(t);
    put(root, 'frontend/ts/generated/contracts.ts', 'export type FrontendSurfaceRegistry = never;\n');
    failed(run(root, entrypoints[0]), /generated browser output must not restore retired aggregate manifests/);
});

test('surface token counts require two production uses and exclude generated/test copies', (t) => {
    const root = fixture(t);
    // Keep real generated topology, adding one independent fixture token.
    appendFileSync(join(root, 'frontend/ts/generated/contracts.ts'), 'export const fixtureDomToken = "fixture";\n');
    put(root, 'frontend/ts/scan-count.ts', 'const one = fixtureDomToken;\n');
    put(root, 'frontend/ts/tests/scan-count.ts', 'fixtureDomToken; fixtureDomToken;\n');
    failed(run(root, entrypoints[0]), /generated browser DOM token has no production import and use: fixtureDomToken/);
    put(root, 'frontend/ts/scan-count.ts', 'import { fixtureDomToken } from "./generated/contracts";\nconst one = fixtureDomToken;\n');
    clean(run(root, entrypoints[0]));
});

test('surface wrapper propagates count-pipeline errors even with two partial matches', (t) => {
    const root = fixture(t);
    appendFileSync(join(root, 'frontend/ts/generated/contracts.ts'), 'export const fixtureDomToken = "fixture";\n');
    put(root, 'frontend/ts/scan-count.ts', 'import { fixtureDomToken } from "./generated/contracts";\nconst one = fixtureDomToken;\n');
    stubRg(root, `for arg in "$@"; do if [[ "$arg" == -o ]]; then printf 'partial\\npartial\\n'; echo 'count read error' >&2; exit 2; fi; done\nexec '${rg}' "$@"`);
    failed(run(root, entrypoints[0]), /count read error/);
});

test('surface wrapper propagates a discovery error instead of losing it in mapfile', (t) => {
    const root = fixture(t);
    stubRg(root, `for arg in "$@"; do if [[ "$arg" == -l ]]; then echo 'discovery read error' >&2; exit 2; fi; done\nexec '${rg}' "$@"`);
    failed(run(root, entrypoints[0]), /discovery read error/);
});
