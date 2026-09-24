import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

const modules = process.env.E2E_PLAYWRIGHT_NODE_MODULES;
assert.ok(modules, 'Run through bin/in-env to use the pinned Playwright cache implementation');
const cacheModule = path.join(modules, 'playwright/lib/transform/compilationCache.js');

// Pause the pinned implementation at its non-atomic .js publication boundary.
// Only disposable fixture files are touched; the Nix package is never modified.
const writer = String.raw`
    const fs = require('node:fs');
    const { spawnSync } = require('node:child_process');
    const cache = require(process.env.CACHE_MODULE);
    const originalWrite = fs.writeFileSync;
    const code = 'function value() { return 42; }';
    fs.writeFileSync = function(file, data, ...rest) {
        if (String(file).endsWith('.js')) {
            originalWrite.call(fs, file, 'function value() {', ...rest);
            const reader = spawnSync(process.execPath, ['-e', process.env.READER], {
                env: { ...process.env, PWTEST_CACHE_DIR: process.env.READER_CACHE },
                encoding: 'utf8', timeout: 10000,
            });
            if (reader.error) throw reader.error;
            process.stdout.write(JSON.stringify({ status: reader.status, stdout: reader.stdout, stderr: reader.stderr }));
        }
        return originalWrite.call(fs, file, data, ...rest);
    };
    cache.getFromCompilationCache('/fixture/shared.ts', '123456789abcdef').addToCache(code, null, new Map());
`;
const reader = String.raw`
    const { Script } = require('node:vm');
    const entry = require(process.env.CACHE_MODULE).getFromCompilationCache('/fixture/shared.ts', '123456789abcdef');
    const code = entry.cachedCode ?? 'function value() { return 42; }';
    new Script(code);
    process.stdout.write(entry.cachedCode === undefined ? 'cache-miss' : 'cache-hit');
`;

function observePublication(shared) {
    const root = mkdtempSync(path.join(tmpdir(), 'bepis-playwright-cache-'));
    try {
        const writerCache = path.join(root, 'shard-1');
        const child = spawnSync(process.execPath, ['-e', writer], {
            env: { ...process.env, CACHE_MODULE: cacheModule, READER: reader,
                PWTEST_CACHE_DIR: writerCache,
                READER_CACHE: shared ? writerCache : path.join(root, 'shard-2') },
            encoding: 'utf8', timeout: 15000,
        });
        assert.ifError(child.error);
        assert.equal(child.status, 0, child.stderr);
        return JSON.parse(child.stdout);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

test('shared Playwright cache can expose incomplete JavaScript to another shard', () => {
    const result = observePublication(true);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /SyntaxError: Unexpected end of input/);
});

test('separate shard caches cannot read another shard publication in progress', () => {
    const result = observePublication(false);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'cache-miss');
});

test('E2E owner overrides inherited cache with distinct run/shard-owned paths', () => {
    // Narrow ownership guard, not an application source-text behavior test.
    // Execute the actual owner assignment with different native lease paths.
    const owner = readFileSync(new URL('../Config/nix/scripts/e2e/e2e', import.meta.url), 'utf8');
    const assignments = owner.match(/^\s*export PWTEST_CACHE_DIR=.*$/gm) ?? [];
    assert.ok(assignments.length > 0, 'E2E must explicitly own its Playwright transform cache');
    const assignment = assignments.at(-1);
    const paths = ['run one/shard-1', 'run one/shard-2', 'run two/shard-1'].map(shard => {
        const child = spawnSync('bash', ['-eu', '-c', `${assignment}\nprintf '%s' "$PWTEST_CACHE_DIR"`], {
            env: { ...process.env, STATE_DIR: '/fixture', shard_dir: `/fixture/${shard}`, PWTEST_CACHE_DIR: '/borrowed/cache' },
            encoding: 'utf8', timeout: 1000,
        });
        assert.ifError(child.error);
        assert.equal(child.status, 0, child.stderr);
        assert.ok(child.stdout.startsWith(`/fixture/${shard}/`));
        return child.stdout;
    });
    assert.equal(new Set(paths).size, paths.length);
});
