import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const recorder = new URL('./verification-measure.py', import.meta.url).pathname;
const compiler = new URL('./verification-ghc.py', import.meta.url).pathname;
const command = (exe, args, options = {}) => spawnSync(exe, args, { encoding: 'utf8', timeout: 30_000, ...options });
const succeeds = (result) => assert.equal(result.status, 0, result.stderr + result.stdout);

test('real GHC link observation preserves executable behavior, ELF type and warm object reuse', (t) => {
    const root = mkdtempSync(join(tmpdir(), 'bepis-link-observation-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const source = join(root, 'Main.hs');
    writeFileSync(source, 'module Main where\nmain :: IO ()\nmain = putStrLn "linked-behavior"\n');
    const control = join(root, 'control');
    const candidate = join(root, 'candidate');
    const controlBuild = command('ghc', [source, '-o', control, '-optl-Wl,-v']);
    succeeds(controlBuild);
    const objectTime = statSync(join(root, 'Main.o')).mtimeMs;
    const output = join(root, 'capture');
    const candidateBuild = command('python3', [recorder, 'run', '--output', output, '--owner', 'link-fixture',
        '--cache-state', 'retained', '--', 'python3', compiler, 'ghc', 'hspec-link', '0', source, '-o', candidate, '-optl-Wl,-v']);
    succeeds(candidateBuild);
    const linkerVersion = (result) => (result.stdout + result.stderr).match(/(?:GNU gold|GNU ld|LLD)[^\n]*/)?.[0];
    assert.ok(linkerVersion(controlBuild), 'real linker must report its identity');
    assert.equal(linkerVersion(candidateBuild), linkerVersion(controlBuild), 'configured linker selection must survive -pgml');
    assert.equal(statSync(join(root, 'Main.o')).mtimeMs, objectTime, 'observation must not recompile objects');
    const original = command(control, []);
    const observed = command(candidate, []);
    succeeds(original);
    succeeds(observed);
    assert.equal(observed.stdout, original.stdout);
    const elfType = (path) => command('readelf', ['-h', path]).stdout.match(/Type:\s+([^\n]+)/)?.[1];
    assert.match(elfType(control), /EXEC/);
    assert.equal(elfType(candidate), elfType(control));
    succeeds(command('python3', [recorder, 'inspect', output]));
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.state, 'observed');
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].phase, 'hspec-link');
    assert.equal(phases.intervals[0].status, 'finished');
    assert.ok(phases.intervals[0].durationSeconds > 0);
    const warm = join(root, 'warm');
    succeeds(command('python3', [recorder, 'run', '--output', warm, '--owner', 'link-fixture',
        '--cache-state', 'warm', '--', 'python3', compiler, 'ghc', 'hspec-link', '0', source, '-o', candidate, '-optl-Wl,-v']));
    assert.deepEqual(JSON.parse(readFileSync(join(warm, 'phases.json'))).intervals, [], 'no invented linking on an unchanged warm build');
    const off = command('ghc', [source, '-o', candidate, '-optl-Wl,-v']);
    succeeds(off);
    assert.doesNotMatch(off.stdout + off.stderr, /Compiling|Linking/, 'turning observation off must not invalidate the build');
    const pie = join(root, 'pie');
    succeeds(command('ghc', [source, '-dynamic', '-fPIC', '-pie', '-o', join(root, 'control-pie')]));
    succeeds(command('python3', [compiler, 'ghc', 'hspec-link', '0', source, '-dynamic', '-fPIC', '-pie', '-o', pie],
        { env: { ...process.env, BEPIS_VERIFICATION_EVENTS: join(root, 'nonexistent-events') } }));
    assert.match(elfType(pie), /DYN/, 'caller PIE choice survives; failed emission never replaces compiler success');
});

test('a real unresolved symbol retains compiler failure and a failed link interval', (t) => {
    const root = mkdtempSync(join(tmpdir(), 'bepis-link-failure-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const source = join(root, 'Main.hs');
    writeFileSync(source, '{-# LANGUAGE ForeignFunctionInterface #-}\nmodule Main where\nforeign import ccall "bepis_missing_fixture_symbol" missing :: IO ()\nmain :: IO ()\nmain = missing\n');
    const args = [source, '-o', join(root, 'missing')];
    const control = command('ghc', args);
    assert.notEqual(control.status, 0);
    assert.match(control.stderr, /bepis_missing_fixture_symbol/);
    const output = join(root, 'capture');
    const observed = command('python3', [recorder, 'run', '--output', output, '--owner', 'link-fixture',
        '--cache-state', 'retained', '--', 'python3', compiler, 'ghc', 'hspec-link', '0', ...args]);
    assert.equal(observed.status, control.status);
    assert.match(observed.stderr, /bepis_missing_fixture_symbol/);
    assert.equal(command('python3', [recorder, 'inspect', output]).status, control.status);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].status, 'failed');
});

test('a signalled driver is reaped and reported failed without converting cancellation to success', (t) => {
    const root = mkdtempSync(join(tmpdir(), 'bepis-link-signal-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const output = join(root, 'capture');
    // Fault at the executable-driver boundary; use the same public hook GHC invokes.
    const result = command('python3', [recorder, 'run', '--output', output, '--owner', 'link-fixture',
        '--cache-state', 'retained', '--', compiler], { env: { ...process.env,
        BEPIS_VERIFICATION_LINK_COMMAND: JSON.stringify(['python3', '-c', 'import os,signal; os.kill(os.getpid(),signal.SIGTERM)']),
        BEPIS_VERIFICATION_LINK_PHASE: 'hspec-link', BEPIS_VERIFICATION_LINK_SCOPE: '0' } });
    assert.equal(result.status, 143);
    assert.equal(command('python3', [recorder, 'inspect', output]).status, 143);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals[0].status, 'failed');
});
