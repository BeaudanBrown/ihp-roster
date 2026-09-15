import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const repo = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const contract = JSON.parse(readFileSync(join(repo, 'Config/nix/tooling-footprint.json'), 'utf8'));

function physicalLines(text) {
    if (text.length === 0) return 0;
    return text.split('\n').length - (text.endsWith('\n') ? 1 : 0);
}

function baselineLines(commit, paths) {
    return paths.reduce((total, path) => {
        try {
            return total + physicalLines(execFileSync(
                'git', ['show', `${commit}:${path}`], { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
            ));
        } catch {
            return total;
        }
    }, 0);
}

function addedLinesBetween(before, after, paths) {
    const rows = execFileSync('git', ['diff', '--numstat', before, after, '--', ...paths], { cwd: repo, encoding: 'utf8' });
    return rows.trim().split('\n').filter(Boolean).reduce((total, row) => {
        const [added] = row.split('\t');
        assert.match(added, /^\d+$/);
        return total + Number(added);
    }, 0);
}

test('tooling migration baseline preserves historical audit totals', () => {
    assert.equal(contract.version, 1);
    assert.deepEqual(contract.historicalAuditBaseline, {
        commit: '5b0f68c6171b5cca0ce29b49966634c3a8cf6903',
        inventoryFiles: 280,
        inventoryPhysicalLines: 30856,
        shellFiles: 205,
        shellPhysicalLines: 18350,
        migrationCandidateFiles: 41,
        migrationCandidatePhysicalLines: 7375,
        retainedTestFiles: 50,
        retainedTestPhysicalLines: 6025,
    });
});

test('baseline slice records reproducible before and after physical lines by ownership', () => {
    const { commit, snapshotCommit, categories } = contract.baselineSlice;
    for (const [name, category] of Object.entries(categories)) {
        assert.equal(baselineLines(commit, category.paths), category.before, `${name} before count drifted`);
        assert.equal(baselineLines(snapshotCommit, category.paths), category.after, `${name} after count drifted`);
    }
});

test('foundation overhead remains separated from migration deletion targets', () => {
    const foundation = contract.foundationSlice;
    let ownedLines = 0;
    for (const [name, category] of Object.entries(foundation.categories)) {
        const actual = baselineLines(foundation.snapshotCommit, category.paths);
        assert.equal(actual, category.added, `${name} foundation count drifted`);
        ownedLines += actual;
    }
    const wiring = foundation.integrationWiring;
    const wiringLines = addedLinesBetween(wiring.baselineCommit, foundation.snapshotCommit, wiring.paths);
    assert.equal(wiringLines, wiring.added, 'foundation wiring count drifted');
    assert.equal(ownedLines + wiringLines, foundation.totalAddedIncludingWiring);
    assert.ok(foundation.totalAddedIncludingWiring < foundation.deletionTargetImplementationLines);
});
