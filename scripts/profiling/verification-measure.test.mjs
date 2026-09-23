import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const recorder = new URL('./verification-measure.py', import.meta.url).pathname;
function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-verification-measure-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    return join(root, 'run');
}
function run(output, code) {
    return spawnSync('python3', [recorder, 'run', '--output', output,
        '--owner', 'fixture', '--cache-state', 'retained', '--', 'python3', '-c', code],
    { encoding: 'utf8', timeout: 10_000 });
}

test('records real command duration and exit without persisting arguments or output', (t) => {
    const output = fixture(t);
    const secret = 'private-fixture-value-not-for-artifacts';
    const result = run(output, `import time; print('${secret}'); time.sleep(0.15)`);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(secret));
    const evidence = JSON.parse(readFileSync(join(output, 'result.json'), 'utf8'));
    assert.equal(evidence.commandStatus, 'passed');
    assert.equal(evidence.exitCode, 0);
    assert.ok(evidence.wallSeconds >= 0.15);
    assert.equal(evidence.measurementStatus, 'complete');
    assert.equal(evidence.authority, 'diagnostic-only');
    assert.equal(inspect(output).status, 0);
    assert.doesNotMatch(readFileSync(join(output, 'metadata.json'), 'utf8'), new RegExp(secret));
    assert.doesNotMatch(JSON.stringify(evidence), new RegExp(secret));
});

function inspect(output) {
    return spawnSync('python3', [recorder, 'inspect', output], { encoding: 'utf8', timeout: 10_000 });
}

test('retains failures and launch failures without certifying success', (t) => {
    const output = fixture(t);
    const result = run(output, 'raise SystemExit(17)');
    assert.equal(result.status, 17, result.stderr);
    assert.equal(JSON.parse(readFileSync(join(output, 'result.json'))).commandStatus, 'failed');
    assert.equal(inspect(output).status, 17);
    const missing = fixture(t);
    const launched = spawnSync('python3', [recorder, 'run', '--output', missing,
        '--owner', 'fixture', '--cache-state', 'retained', '--', '/no-such-verification-command'], { encoding: 'utf8' });
    assert.equal(launched.status, 127);
    assert.equal(JSON.parse(readFileSync(join(missing, 'result.json'))).commandStatus, 'launch-failed');
});

test('incomplete, malformed, non-finite and oversized evidence is never accepted', (t) => {
    const output = fixture(t);
    mkdirSync(output);
    writeFileSync(join(output, 'run.json'), '{"state":"running"}');
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), '{');
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), ' '.repeat(70_000));
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), '['.repeat(2000) + ']'.repeat(2000));
    assert.equal(inspect(output).status, 2);
    const good = fixture(t);
    assert.equal(run(good, 'pass').status, 0);
    const path = join(good, 'result.json');
    const evidence = JSON.parse(readFileSync(path));
    for (const invalid of [-1, null, '0', true]) {
        writeFileSync(path, JSON.stringify({ ...evidence, wallSeconds: invalid }));
        assert.equal(inspect(good).status, 2);
    }
    writeFileSync(path, JSON.stringify(evidence).replace(/"wallSeconds":[\d.e+-]+/, '"wallSeconds":NaN'));
    assert.equal(inspect(good).status, 2);
});

test('cannot overwrite an existing run or follow output directory symlinks', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    const before = readFileSync(join(output, 'result.json'), 'utf8');
    assert.equal(run(output, 'raise SystemExit(17)').status, 2);
    assert.equal(readFileSync(join(output, 'result.json'), 'utf8'), before);
    const link = `${output}-link`;
    symlinkSync(output, link);
    assert.equal(run(join(link, 'nested'), 'pass').status, 2);
    assert.equal(existsSync(join(output, 'nested')), false);
});

function start(output, code, extraEnv = {}, options = []) {
    const process = spawn('python3', [recorder, 'run', '--output', output,
        '--owner', 'fixture', '--cache-state', 'retained', ...options, '--', 'python3', '-c', code],
    { env: { ...globalThis.process.env, ...extraEnv }, stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    process.stderr.on('data', (data) => { stderr += data; });
    process.stdout.resume();
    const done = new Promise((resolve, reject) => {
        process.on('error', reject);
        process.on('close', (code, signal) => resolve({ code, signal, stderr }));
    });
    return { process, done };
}
async function waitFor(path) {
    const deadline = Date.now() + 5000;
    while (!existsSync(path)) {
        assert.ok(Date.now() < deadline, `fixture never created ${path}`);
        await new Promise((resolve) => setTimeout(resolve, 20));
    }
}

test('concurrent writers cannot take over the same run directory', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const first = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.5)`);
    t.after(() => first.process.kill('SIGKILL'));
    await waitFor(ready);
    assert.equal(run(output, 'raise SystemExit(17)').status, 2);
    assert.equal((await first.done).code, 0);
    assert.equal(inspect(output).status, 0);
});

test('interruption is retained even when child handles termination as success', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const stopped = `${output}-stopped`;
    const running = start(output, `import signal,time,sys\nfrom pathlib import Path\ndef stop(*_):\n Path(${JSON.stringify(stopped)}).touch()\n sys.exit(0)\nsignal.signal(signal.SIGTERM, stop)\nPath(${JSON.stringify(ready)}).touch()\ntime.sleep(2)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    running.process.kill('SIGTERM');
    const result = await running.done;
    assert.equal(result.code, 143, result.stderr);
    assert.ok(existsSync(stopped));
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.equal(evidence.commandStatus, 'interrupted');
    assert.equal(inspect(output).status, 143);
});

test('metadata work is outside command wall and child CPU measurements', async (t) => {
    const output = fixture(t);
    const bin = `${output}-bin`;
    mkdirSync(bin);
    const git = join(bin, 'git');
    writeFileSync(git, '#!/usr/bin/env python3\nimport time\nend=time.process_time()+0.25\nwhile time.process_time()<end: pass\ntime.sleep(0.25)\nprint("a"*40)\n');
    chmodSync(git, 0o755);
    const started = performance.now();
    const running = start(output, 'import time; time.sleep(0.15)', { PATH: `${bin}:${process.env.PATH}` });
    assert.equal((await running.done).code, 0);
    const elapsed = (performance.now() - started) / 1000;
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    const metadata = JSON.parse(readFileSync(join(output, 'metadata.json')));
    assert.equal(metadata.revision, 'a'.repeat(40));
    assert.ok(elapsed - evidence.wallSeconds >= 0.45, `metadata included in timer: ${elapsed}/${evidence.wallSeconds}`);
    assert.ok(evidence.cpuSeconds < 0.2, `metadata CPU included: ${evidence.cpuSeconds}`);
});

test('samples simultaneous descendant memory and measures CPU of only this command', (t) => {
    const output = fixture(t);
    const result = run(output, 'import subprocess,sys,time\nx=bytearray(24*1024*1024)\np=subprocess.Popen([sys.executable,"-c","import time; x=bytearray(24*1024*1024); time.sleep(0.3)"])\np.wait()');
    assert.equal(result.status, 0, result.stderr);
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.equal(evidence.memory.method, 'sampled-simultaneous-tree-rss');
    assert.ok(evidence.memory.samples >= 1);
    assert.ok(evidence.memory.peakBytes >= 48 * 1024 * 1024, JSON.stringify(evidence.memory));
    assert.ok(evidence.cpuSeconds >= 0 && Number.isFinite(evidence.cpuSeconds));
    assert.equal(evidence.cpuScope, 'waited-command-and-waited-descendants');
});

test('non-overlapping child allocations are not added as historical peak memory', (t) => {
    const output = fixture(t);
    const result = run(output, 'import subprocess,sys\nfor _ in range(2):\n subprocess.run([sys.executable,"-c","import time; x=bytearray(48*1024*1024); time.sleep(0.2)"],check=True)');
    assert.equal(result.status, 0, result.stderr);
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.ok(evidence.memory.peakBytes >= 48 * 1024 * 1024);
    assert.ok(evidence.memory.peakBytes < 100 * 1024 * 1024, JSON.stringify(evidence.memory));
});

test('hard-killed recorder leaves incomplete evidence, never a result', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.3)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    running.process.kill('SIGKILL');
    assert.equal((await running.done).signal, 'SIGKILL');
    assert.equal(existsSync(join(output, 'result.json')), false);
    assert.equal(inspect(output).status, 2);
});

test('publication stays bound to the original directory if its pathname is replaced', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const victim = `${output}-victim`;
    mkdirSync(victim);
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.4)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    renameSync(output, `${output}-original`);
    symlinkSync(victim, output);
    assert.equal((await running.done).code, 2);
    assert.equal(existsSync(join(victim, 'result.json')), false);
});

test('publication cannot overwrite an injected completion file', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.4)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    writeFileSync(join(output, 'result.json'), 'foreign result');
    assert.equal((await running.done).code, 2);
    assert.equal(readFileSync(join(output, 'result.json'), 'utf8'), 'foreign result');
});

test('inspection requires bounded valid metadata and lifecycle evidence', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    for (const name of ['metadata.json', 'run.json']) {
        const path = join(output, name);
        const valid = readFileSync(path, 'utf8');
        rmSync(path);
        assert.equal(inspect(output).status, 2);
        for (const invalid of ['{', '{}', ' '.repeat(70_000)]) {
            writeFileSync(path, invalid);
            assert.equal(inspect(output).status, 2);
        }
        writeFileSync(path, valid);
        assert.equal(inspect(output).status, 0);
    }
});

test('termination escalates for an uncooperative command without killing an unrelated process', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const sibling = spawn('python3', ['-c', 'import time; time.sleep(10)'], { stdio: 'ignore' });
    t.after(() => sibling.kill('SIGKILL'));
    const running = start(output, `import signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nPath(${JSON.stringify(ready)}).touch()\ntime.sleep(3)`, {}, ['--termination-grace-seconds', '1']);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    const before = performance.now();
    running.process.kill('SIGTERM');
    assert.equal((await running.done).code, 143);
    assert.ok(performance.now() - before < 2500);
    assert.equal(sibling.exitCode, null);
    assert.equal(sibling.signalCode, null);
});

test('unknown fields, inconsistent outcomes and malformed resource metrics fail inspection', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    const path = join(output, 'result.json');
    const evidence = JSON.parse(readFileSync(path));
    for (const change of [
        { secret: 'not-a-schema-field' }, { commandStatus: 'failed' },
        { commandStatus: 'interrupted', exitCode: 17 },
        { commandStatus: 'launch-failed', exitCode: 1, cpuSeconds: null },
        { cpuSeconds: -1 }, { memory: { ...evidence.memory, peakBytes: '1024' } },
    ]) {
        writeFileSync(path, JSON.stringify({ ...evidence, ...change }));
        const checked = inspect(output);
        assert.equal(checked.status, 2);
        assert.doesNotMatch(checked.stdout, /not-a-schema-field/);
    }
    writeFileSync(path, JSON.stringify(evidence).replace('"exitCode":0', '"exitCode":17,"exitCode":0'));
    assert.equal(inspect(output).status, 2);
});
