import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const scripts = fileURLToPath(new URL('../Config/nix/scripts/', import.meta.url));
const good = `module Application.Subject where
import Application.Instances ()
import Application.Model (Marker(..), Render(..))
import Data.Proxy (Proxy(..))
import Generated.Dependency ()
data Choice = Present { value :: Int } | Absent
safe :: Choice -> Int
safe Present {value = n} = n
safe Absent = 0
marker :: Proxy Marker
marker = Proxy
rendered :: String
rendered = render Marker
`;

function put(root, path, text) {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text);
}

function fixture(t, subject = good) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-warning-fixture-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    // Real GHC, real gate and real ghc.sh; only the fixture's ordinary Makefile
    // and owned inventory differ. No duplicate warning flags or fake compiler.
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -ibuild -XOverloadedRecordDot"\n');
    put(root, 'Application/Model.hs', 'module Application.Model where\ndata Marker = Marker\nclass Render a where render :: a -> String\n');
    put(root, 'Application/Instances.hs', 'module Application.Instances where\nimport Application.Model\ninstance Render Marker where render _ = "marker"\n');
    put(root, 'Application/Subject.hs', subject);
    // Both redundant imports and partial accesses in generated code must stay
    // outside application warning authority, even with a cold dependency cache.
    put(root, 'build/Generated/Dependency.hs', 'module Generated.Dependency where\nimport Data.List (sort)\ndata Choice = Present { value :: Int } | Absent\nunsafe :: Choice -> Int\nunsafe x = x.value\n');
    put(root, 'Config/nix/production-module-inventory.tsv', 'path\tpackaging\nApplication/Instances.hs\tproduction\nApplication/Model.hs\tproduction\nApplication/Subject.hs\tproduction\nbuild/Generated/Dependency.hs\tproduction\n');
    return root;
}

function run(root) {
    const result = spawnSync('bash', [join(scripts, 'haskell/application-warnings')], {
        cwd: root,
        env: { ...process.env, BEPIS_SCRIPTS_ROOT: scripts, APPLICATION_WARNINGS_BUILD_DIR: join(root, 'cache') },
        encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024,
    });
    assert.ifError(result.error);
    return result;
}

function passes(result) {
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /application-warnings: ok \(3 app-owned production modules\)/);
}

function rejects(result, flag) {
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, new RegExp(flag));
    assert.doesNotMatch(result.stdout, /application-warnings: ok/);
}

test('real gate accepts marker/type and instance-only imports, constructor patterns and generated dependencies, cold and warm', (t) => {
    const root = fixture(t);
    passes(run(root));
    passes(run(root));
});

test('unused app imports fail both cold and after a successful cached run', (t) => {
    const root = fixture(t, good.replace('import Data.Proxy', 'import Data.List (sort)\nimport Data.Proxy'));
    rejects(run(root), 'unused-imports');
    put(root, 'Application/Subject.hs', good);
    passes(run(root));
    put(root, 'Application/Subject.hs', good.replace('import Data.Proxy', 'import Data.List (sort)\nimport Data.Proxy'));
    rejects(run(root), 'unused-imports');
});

for (const [name, expression, flag] of [
    ['named partial selector', 'unsafe :: Choice -> Int\nunsafe = value\n', 'incomplete-record-selectors'],
    ['record-dot partial selector', 'unsafe :: Choice -> Int\nunsafe x = x.value\n', 'incomplete-record-selectors'],
    ['partial record update', 'unsafe :: Choice -> Choice\nunsafe x = x { value = 1 }\n', 'incomplete-record-updates'],
    ['incomplete function pattern', 'unsafe :: Choice -> Int\nunsafe (Present n) = n\n', 'incomplete-patterns'],
    ['incomplete let pattern', 'unsafe :: Choice -> Int\nunsafe x = let Present n = x in n\n', 'incomplete-uni-patterns'],
]) {
    test(`${name} fails the real owned warning pass`, (t) => {
        rejects(run(fixture(t, good + expression)), flag);
    });
}

test('required inventory failures cannot silently reduce the warning authority', (t) => {
    const root = fixture(t);
    rmSync(join(root, 'Config/nix/production-module-inventory.tsv'));
    rejects(run(root), 'production-module-inventory');
});

test('the original dependency-first multi-file skip cannot conceal an unused import', (t) => {
    const root = fixture(t);
    passes(run(root));
    const path = join(root, 'Application/Model.hs');
    put(root, 'Application/Model.hs', readFileSync(path, 'utf8').replace('data Marker', 'import Data.List (sort)\ndata Marker'));
    rejects(run(root), 'unused-imports');
});
