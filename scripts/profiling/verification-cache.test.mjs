import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const repository = new URL('../../', import.meta.url).pathname;
const recorder = join(repository, 'scripts/profiling/verification-measure.py');

test('native dependency owner exposes lock acquisition and actual reuse/reset decisions', (t) => {
    const root = mkdtempSync(join(tmpdir(), 'bepis-cache-observation-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: root }).status, 0);
    writeFileSync(join(root, 'input'), 'first');
    const inventory = join(root, 'inventory');
    writeFileSync(inventory, '#!/usr/bin/env bash\nprintf "path\\tinput\\n"\n');
    chmodSync(inventory, 0o700);
    const output = join(root, 'capture');
    const result = spawnSync('python3', [recorder, 'run', '--output', output, '--owner', 'cache-fixture',
        '--cache-state', 'output-cold', '--', 'bash', '-c', `set -euo pipefail
source "$BEPIS_SCRIPTS_ROOT/lib/ghc.sh"
ihp_roster_prepare_verification_cache surface-adapter-validation '' fixture
printf retained > "$IHP_ROSTER_GHC_CACHE_DIR/obj/probe"
ihp_roster_release_verification_cache
ihp_roster_prepare_verification_cache surface-adapter-validation '' fixture
test -f "$IHP_ROSTER_GHC_CACHE_DIR/obj/probe"
ihp_roster_release_verification_cache
printf changed > input
ihp_roster_prepare_verification_cache surface-adapter-validation '' fixture
test ! -f "$IHP_ROSTER_GHC_CACHE_DIR/obj/probe"
ihp_roster_release_verification_cache
`], { cwd: root, encoding: 'utf8', timeout: 60_000, env: { ...process.env,
        BEPIS_SCRIPTS_ROOT: join(repository, 'Config/nix/scripts'),
        BEPIS_TOOLING_LAUNCHER: join(repository, 'bin/tooling-run'),
        BEPIS_GHC_CACHE_PARENT: join(root, 'cache'), IHP_ROSTER_GHC_CACHE_INVENTORY: inventory } });
    assert.equal(result.status, 0, result.stderr + result.stdout);
    const inspected = spawnSync('python3', [recorder, 'inspect', output], { encoding: 'utf8' });
    assert.equal(inspected.status, 0, inspected.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.deepEqual(phases.observations?.map((row) => row.phase),
        ['ghc-dependency-manifest-reset', 'ghc-dependency-manifest-reused', 'ghc-dependency-manifest-reset']);
    assert.equal(phases.intervals.length, 3);
    assert.ok(phases.intervals.every((row) => row.phase === 'ghc-dependency-lock' && row.scope === 1 && row.status === 'finished'));
});
