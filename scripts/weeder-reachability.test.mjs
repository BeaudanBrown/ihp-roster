import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repo = fileURLToPath(new URL('../', import.meta.url));
const gate = join(repo, 'Config/nix/scripts/haskell/weeder-check');
const advisory = join(repo, 'scripts/weeder-reachability.py');

function put(root, path, text) {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text);
}

function command(root, executable, args, extra = {}) {
    const result = spawnSync(executable, args, { cwd: root, env: { ...process.env, ...extra }, encoding: 'utf8', timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return result;
}

function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-reachability-fixture-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const sources = {
        'Main.hs': 'module Main where\nimport Web.FrontController (serve)\nmain :: IO ()\nmain = print serve\n',
        // IHP 1.6 has a separately inventoried worker module, not a second Main.
        'WorkerMain.hs': 'module WorkerMain () where\n',
        'Web/FrontController.hs': 'module Web.FrontController where\nimport Application.Shared (runtimeOnly)\nserve :: Int\nserve = runtimeOnly\n',
        'Application/Shared.hs': 'module Application.Shared where\nruntimeOnly, testOnly, productionScriptOnly, developmentScriptOnly :: Int\nruntimeOnly = 1\ntestOnly = 2\nproductionScriptOnly = 3\ndevelopmentScriptOnly = 4\ninstanceOnly :: String\ninstanceOnly = "instance"\n',
        'Application/Instances.hs': 'module Application.Instances where\nimport Data.String (IsString(..))\nimport Application.Shared (instanceOnly)\nnewtype Marker = Marker String\ninstance IsString Marker where fromString _ = Marker instanceOnly\n',
        'Test/HspecMain.hs': 'module Test.HspecMain where\nimport Application.Shared (testOnly)\nmain :: IO ()\nmain = print testOnly\n',
        'Application/Script/SeedProfile.hs': 'module Application.Script.SeedProfile where\nimport Application.Shared (developmentScriptOnly)\nrun :: IO ()\nrun = print developmentScriptOnly\n',
        'Application/Script/XeroPayItemProbe.hs': 'module Application.Script.XeroPayItemProbe where\nrun :: IO ()\nrun = pure ()\n',
        'Application/Script/ProductionFixture.hs': 'module Application.Script.ProductionFixture where\nimport Application.Shared (productionScriptOnly)\nrun :: IO ()\nrun = print productionScriptOnly\n',
        'build/Generated/Statements/FetchAppJob.hs': 'module Generated.Statements.FetchAppJob where\ngeneratedOnly :: Int\ngeneratedOnly = 5\n',
    };
    for (const [path, text] of Object.entries(sources)) put(root, path, text);
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -ibuild"\n');
    put(root, 'Config/nix/production-module-inventory.tsv', 'path\tpackaging\n' + Object.keys(sources).map((path) => `${path}\t${path.includes('SeedProfile') || path.includes('XeroPayItemProbe') || path.startsWith('Test/') ? 'development' : 'production'}\n`).join(''));
    put(root, 'Config/nix/production-script-inventory.tsv', 'script\tpackaging\tcategory\tconsumer\treason\nSeedProfile\tdevelopment\tseed\tfixture\tdeveloper seed\nXeroPayItemProbe\tdevelopment\tprobe\tfixture\tdeveloper probe\nProductionFixture\tproduction\tmaintenance\tfixture\toperator entrypoint\n');
    put(root, 'Config/nix/production-executable-inventory.tsv', 'executable\tcategory\tconsumer\tmarker\treason\nRunProdServer\truntime\tfixture\tserver\tframework main\nRunJobs\truntime\tfixture\tworker\tdynamic worker\nProductionFixture\tmaintenance\tfixture\tscript\toperator entrypoint\n');
    put(root, 'Config/nix/weeder-baseline.tsv', '# deliberately empty\n');
    copyFileSync(join(repo, 'weeder.toml'), join(root, 'weeder.toml'));
    mkdirSync(join(root, 'scripts'));
    symlinkSync(advisory, join(root, 'scripts/weeder-reachability.py'));
    // Stub only unrelated model generation. The complete gate, source sweep,
    // GHC, Weeder, canonical root policy and baseline policy all run for real.
    put(root, 'helpers/haskell/generated-ensure', 'exit 0\n');
    mkdirSync(join(root, 'helpers/lib'));
    symlinkSync(join(repo, 'Config/nix/scripts/lib/ghc.sh'), join(root, 'helpers/lib/ghc.sh'));
    symlinkSync(join(repo, 'Config/nix/scripts/haskell/weeder-policy'), join(root, 'helpers/haskell/weeder-policy'));
    command(root, 'git', ['init', '-q']);
    command(root, 'git', ['add', '.']);
    command(root, 'git', ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
    command(root, 'bash', [gate], { BEPIS_SCRIPTS_ROOT: join(root, 'helpers'), WEEDER_BUILD_DIR: join(root, 'cache') });
    return root;
}

function report(root) {
    return JSON.parse(readFileSync(join(root, 'cache/reachability-advisory.json'), 'utf8'));
}

function rerun(root) {
    command(root, 'python3', [advisory, 'report', '--snapshot', join(root, 'cache/reachability-inputs.json'), '--hie', join(root, 'cache/hie'), '--full-output', join(root, 'cache/weeder-output.txt'), '--output', join(root, 'cache/reachability-advisory.json')]);
    return report(root);
}

test('real complete sweep distinguishes runtime, test, script and conservative category roots', (t) => {
    const root = fixture(t);
    const result = report(root);
    assert.equal(result.status, 'fresh', result.reason);
    const classification = (symbol) => result.declarations.find((row) => row.symbol === symbol)?.classification;
    assert.equal(classification('runtimeOnly'), 'production-root-retained');
    assert.equal(classification('productionScriptOnly'), 'production-root-retained');
    assert.equal(classification('testOnly'), 'test/development-retained');
    assert.equal(classification('developmentScriptOnly'), 'test/development-retained');
    assert.equal(classification('instanceOnly'), 'category-retained/unknown');
    assert.equal(classification('generatedOnly'), 'category-retained/unknown');
    assert.deepEqual(result.declarations.find((row) => row.symbol === 'testOnly').rootGroups, ['test']);
    assert.deepEqual(result.declarations.find((row) => row.symbol === 'developmentScriptOnly').rootGroups, ['development']);
    assert.equal(result.roots.production.find((row) => row.symbol.includes('ProductionFixture')).inventory.category, 'maintenance');
    assert.match(result.revision, /^[0-9a-f]{40}$/);
    assert.ok(Object.keys(result.hieHashes).length >= 10);
    assert.match(result.inputHashes['WorkerMain.hs'], /^[0-9a-f]{64}$/);
    assert.equal(result.advisoryOnly, true);
});

test('unrecognised regex dialect features qualify the advisory, not the complete gate', (t) => {
    const root = fixture(t);
    const path = join(root, 'weeder.toml');
    writeFileSync(path, readFileSync(path, 'utf8').replace('roots = [', 'roots = [\n    "^Main[.]main$",'));
    command(root, 'bash', [gate], { BEPIS_SCRIPTS_ROOT: join(root, 'helpers'), WEEDER_BUILD_DIR: join(root, 'cache') });
    assert.equal(report(root).status, 'unavailable');
    assert.match(report(root).reason, /regex needs an explicit compatibility check/);
});

test('byte-identical source touches do not invalidate compiler evidence', (t) => {
    const root = fixture(t);
    const before = report(root);
    const path = join(root, 'Application/Shared.hs');
    writeFileSync(path, readFileSync(path));
    const after = rerun(root);
    assert.equal(after.status, 'fresh', after.reason);
    assert.deepEqual(after.hieHashes, before.hieHashes);
    assert.deepEqual(after.inputHashes, before.inputHashes);
});

for (const [name, change] of [
    ['source changed since sweep', (root) => appendFileSync(join(root, 'Application/Shared.hs'), '\n')],
    ['deleted source', (root) => rmSync(join(root, 'Application/Shared.hs'))],
    ['deleted worker source', (root) => rmSync(join(root, 'WorkerMain.hs'))],
    ['missing HIE', (root) => rmSync(join(root, 'cache/hie/Application/Shared.hie'))],
    ['stale deleted-module HIE', (root) => copyFileSync(join(root, 'cache/hie/Application/Shared.hie'), join(root, 'cache/hie/Deleted.hie'))],
    ['root policy changed', (root) => appendFileSync(join(root, 'weeder.toml'), '\n')],
    ['malformed compiler evidence', (root) => appendFileSync(join(root, 'cache/weeder-output.txt'), 'not a candidate\n')],
]) {
    test(`${name} replaces prior success with unavailable, without becoming a gate`, (t) => {
        const root = fixture(t);
        assert.equal(report(root).status, 'fresh', report(root).reason);
        change(root);
        const result = rerun(root);
        assert.equal(result.status, 'unavailable');
        assert.ok(result.reason);
        assert.equal(result.declarations, undefined);
    });
}
