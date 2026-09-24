import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const recorder = new URL('./verification-measure.py', import.meta.url).pathname;
const repository = new URL('../../', import.meta.url).pathname;
const zero = { attempts: 0, failures: 0, durationNanoseconds: 0 };
const summary = (scope) => ({ schemaVersion: 1, scope, overflow: false, suites: [], unattributed: zero });
function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-reset-journal-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    return root;
}
function capture(output, code) {
    return command(['run', '--output', output, '--owner', 'reset-fixture', '--cache-state', 'retained', '--', 'python3', '-c', code]);
}
const command = (args, options = {}) => spawnSync('python3', [recorder, ...args], { encoding: 'utf8', timeout: 30_000, ...options });

test('native reset aggregates preserve suite/thread attribution, failures and unscoped work', (t) => {
    const root = mkdtempSync(join(tmpdir(), 'bepis-reset-observation-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const source = join(root, 'Main.hs');
    writeFileSync(source, `module Main where
import Prelude
import Control.Concurrent
import Control.Exception
import Control.Monad
import Test.ResetMetrics
main :: IO ()
main = withResetMetrics ["Alpha", "Beta"] $ do
    done <- newEmptyMVar
    forM_ ["Alpha", "Beta"] $ \\name -> forkIO $ do
        withResetSuite name $ replicateM_ 100 (measureReset (pure ()))
        putMVar done ()
    replicateM_ 2 (takeMVar done)
    withResetSuite "Alpha" $ do
        withResetSuite "Beta" $ measureReset (pure ())
        _ <- try (measureReset (ioError (userError "private-error"))) :: IO (Either IOException ())
        pure ()
    measureReset (pure ())
`);
    const binary = join(root, 'fixture');
    const built = spawnSync('ghc', ['-i' + repository, '-outputdir', root, source, '-o', binary],
        { encoding: 'utf8', timeout: 60_000 });
    assert.equal(built.status, 0, built.stderr + built.stdout);
    const output = join(root, 'capture');
    const result = command(['run', '--output', output, '--owner', 'reset-fixture', '--cache-state', 'retained', '--', binary],
        { env: { ...process.env, BEPIS_SCRIPTS_ROOT: join(repository, 'Config/nix/scripts'), TEST_SHARD_INDEX: '1' } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(command(['inspect', output]).status, 0);
    const raw = readFileSync(join(output, 'resets.json'), 'utf8');
    assert.doesNotMatch(raw, /private-error/);
    const report = JSON.parse(raw);
    assert.equal(report.state, 'observed');
    assert.deepEqual(report.missingScopes, []);
    const summaries = report.summaries;
    assert.equal(summaries.length, 1);
    assert.equal(summaries[0].scope, 1);
    assert.deepEqual(summaries[0].suites.map(({ suite, attempts, failures }) => ({ suite, attempts, failures })),
        [{ suite: 'Alpha', attempts: 101, failures: 1 }, { suite: 'Beta', attempts: 101, failures: 0 }]);
    assert.equal(summaries[0].unattributed.attempts, 1);
    assert.ok(summaries[0].suites.every((suite) => suite.durationNanoseconds > 0));
});

test('concurrent aggregate publishers retain every scope; successful empty producers mean observed zero', (t) => {
    const output = join(fixture(t), 'capture');
    const payload = JSON.stringify(Array.from({ length: 8 }, (_, index) => summary(index + 1)));
    const result = capture(output, `import json,subprocess,sys
rows=json.loads(${JSON.stringify(payload)})
children=[(subprocess.Popen([sys.executable,${JSON.stringify(recorder)},'reset-summary'],stdin=subprocess.PIPE),row) for row in rows]
for child,row in children:
    child.stdin.write(json.dumps(row).encode()); child.stdin.close()
assert all(child.wait()==0 for child,row in children)
`);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(command(['inspect', output]).status, 0);
    const report = JSON.parse(readFileSync(join(output, 'resets.json')));
    assert.equal(report.state, 'observed');
    assert.deepEqual(report.summaries.map((row) => row.scope).sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8]);
    assert.ok(report.summaries.every((row) => row.unattributed.attempts === 0));
});

test('producer failure leaves reset scope unavailable, never fabricated zero', (t) => {
    const output = join(fixture(t), 'capture');
    const result = capture(output, `import subprocess,sys
subprocess.run([sys.executable,${JSON.stringify(recorder)},'event','--phase','hspec-execution','--scope','1','--edge','start'],check=True)
sys.exit(9)
`);
    assert.equal(result.status, 9);
    assert.equal(command(['inspect', output]).status, 9);
    const report = JSON.parse(readFileSync(join(output, 'resets.json')));
    assert.equal(report.state, 'unavailable');
    assert.deepEqual(report.missingScopes, [1]);
    assert.deepEqual(report.summaries, []);
});

test('malformed, duplicate, overflowing and tampered reset evidence cannot certify measurement', (t) => {
    const root = fixture(t);
    const bad = [
        { ...summary(1), scope: true },
        { ...summary(1), overflow: true },
        { ...summary(1), unattributed: { ...zero, attempts: -1 } },
        { ...summary(1), unattributed: { ...zero, attempts: true } },
        { ...summary(1), unattributed: { ...zero, failures: 1 } },
        { ...summary(1), unattributed: { ...zero, durationNanoseconds: 1 } },
        { ...summary(1), suites: [{ suite: 'private@example.invalid', ...zero }] },
        { ...summary(1), suites: [{ suite: 'Alpha', ...zero }, { suite: 'Alpha', ...zero }] },
        [],
    ];
    bad.forEach((row, index) => {
        const output = join(root, `bad-${index}`);
        const result = capture(output, `import os
open(os.path.join(os.environ['BEPIS_VERIFICATION_EVENTS'],'reset-000.json'),'w').write(${JSON.stringify(JSON.stringify(row))})`);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(command(['inspect', output]).status, 2);
        assert.equal(JSON.parse(readFileSync(join(output, 'result.json'))).measurementStatus, 'incomplete');
    });
    const output = join(root, 'duplicate-scopes');
    assert.equal(capture(output, `import os
for i in range(2):
    open(os.path.join(os.environ['BEPIS_VERIFICATION_EVENTS'],f'reset-{i:03}.json'),'w').write(${JSON.stringify(JSON.stringify(summary(1)))})`).status, 0);
    assert.equal(command(['inspect', output]).status, 2);
    const empty = join(root, 'tampered');
    assert.equal(capture(empty, 'pass').status, 0);
    writeFileSync(join(empty, 'resets.json'), JSON.stringify({ state: 'observed' }));
    assert.equal(command(['inspect', empty]).status, 2);
});
