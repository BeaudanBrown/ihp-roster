import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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

function run(root, environment = {}) {
    const result = spawnSync('bash', [join(scripts, 'haskell/application-warnings')], {
        cwd: root,
        env: { ...process.env, BEPIS_SCRIPTS_ROOT: scripts, APPLICATION_WARNINGS_BUILD_DIR: join(root, 'cache'), ...environment },
        encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024,
    });
    assert.ifError(result.error);
    return result;
}

function passes(result) {
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /application-warnings: ok \(3 app-owned production modules\)/);
}

function rejects(result, diagnostic) {
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, new RegExp(diagnostic));
    assert.doesNotMatch(result.stdout, /application-warnings: ok/);
}

test('real gate accepts marker/type and instance-only imports, constructor patterns and generated dependencies, cold and warm', (t) => {
    const root = fixture(t);
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -ibuild -XOverloadedRecordDot -j4"\n');
    const inventory = 'Config/nix/production-module-inventory.tsv';
    for (let n = 0; n < 8; n++) {
        put(root, `build/Generated/Unused${n}.hs`, `module Generated.Unused${n} where\nimport Data.List (sort)\n`);
        put(root, inventory, readFileSync(join(root, inventory), 'utf8') + `build/Generated/Unused${n}.hs\tproduction\n`);
    }
    passes(run(root));
    passes(run(root));
});

test('unused app imports fail both cold and after a successful cached run', (t) => {
    const root = fixture(t, good.replace('import Data.Proxy', 'import Data.List (sort)\nimport Data.Proxy'));
    rejects(run(root), 'GHC-66111');
    put(root, 'Application/Subject.hs', good);
    passes(run(root));
    put(root, 'Application/Subject.hs', good.replace('import Data.Proxy', 'import Data.List (sort)\nimport Data.Proxy'));
    rejects(run(root), 'GHC-66111');
});

for (const [name, expression, diagnostic] of [
    ['named partial selector', 'unsafe :: Choice -> Int\nunsafe = value\n', 'GHC-17335'],
    ['record-dot partial selector', 'unsafe :: Choice -> Int\nunsafe x = x.value\n', 'GHC-86894'],
    ['partial record update', 'unsafe :: Choice -> Choice\nunsafe x = x { value = 1 }\n', 'GHC-62161'],
    ['incomplete function pattern', 'unsafe :: Choice -> Int\nunsafe (Present n) = n\n', 'GHC-62161'],
    ['incomplete let pattern', 'unsafe :: Choice -> Int\nunsafe x = let Present n = x in n\n', 'GHC-62161'],
]) {
    test(`${name} fails the real owned warning pass`, (t) => {
        rejects(run(fixture(t, good + expression)), diagnostic);
    });
}

test('required inventory failures cannot silently reduce the warning authority', (t) => {
    const root = fixture(t);
    rmSync(join(root, 'Config/nix/production-module-inventory.tsv'));
    rejects(run(root), 'production-module-inventory');
});

test('caller warning-disable flags cannot weaken the owned warning policy', (t) => {
    const root = fixture(t, good.replace('import Data.Proxy', 'import Data.List (sort)\nimport Data.Proxy'));
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -ibuild -XOverloadedRecordDot -Wno-unused-imports"\n');
    rejects(run(root), 'GHC-66111');
});

test('fresh forced compilation observes Template Haskell file and environment changes', (t) => {
    const root = fixture(t, good.replace('import Data.Proxy', 'import qualified Language.Haskell.TH as TH\nimport qualified System.Environment as Env\nimport Data.Proxy') + `
$(do
    contents <- TH.runIO (readFile "ambient.txt")
    setting <- TH.runIO (Env.lookupEnv "WARNING_TEST_INPUT")
    if contents == "valid" && setting == Just "valid"
        then pure []
        else fail "ambient compile input changed")
`);
    put(root, 'Makefile', 'print-ghc-options:\n\t@echo "-i. -ibuild -XOverloadedRecordDot -XTemplateHaskell"\n');
    put(root, 'ambient.txt', 'valid');
    passes(run(root, { WARNING_TEST_INPUT: 'valid' }));
    put(root, 'ambient.txt', 'changed');
    rejects(run(root, { WARNING_TEST_INPUT: 'valid' }), 'ambient compile input changed');
    put(root, 'ambient.txt', 'valid');
    rejects(run(root, { WARNING_TEST_INPUT: 'changed' }), 'ambient compile input changed');
    passes(run(root, { WARNING_TEST_INPUT: 'valid' }));
});

test('deleted generated inputs and compiler errors cannot inherit an earlier success', (t) => {
    const root = fixture(t);
    passes(run(root));
    rmSync(join(root, 'build/Generated/Dependency.hs'));
    rejects(run(root), 'Generated.Dependency|find file');
    put(root, 'build/Generated/Dependency.hs', 'module Generated.Dependency where\nbroken :: Int\nbroken = "not an Int"\n');
    rejects(run(root), 'GHC-|Int');
});

// The adapter delegates to real GHC. Faults alter only its diagnostic transport
// after compilation, or hold its boundary so contention can be observed.
function compilerAdapter(root) {
    const realGhc = spawnSync('bash', ['-c', 'command -v ghc'], { encoding: 'utf8' }).stdout.trim();
    assert.ok(realGhc);
    put(root, 'tools/ghc', `#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, time
args = sys.argv[1:]
if '-ddump-json' not in args:
    os.execv(${JSON.stringify(realGhc)}, [${JSON.stringify(realGhc)}, *args])
marker = os.environ.get('WARNING_TEST_MARKER')
if marker:
    pathlib.Path(marker).write_text('entered')
    while not pathlib.Path(marker + '.release').exists(): time.sleep(0.01)
result = subprocess.run([${JSON.stringify(realGhc)}, *args], stdout=subprocess.PIPE)
mode = os.environ.get('WARNING_TEST_FAULT')
if result.returncode == 0 and mode == 'malformed':
    sys.stdout.write('{not JSON\\n')
elif result.returncode == 0 and mode == 'missing-span':
    for line in result.stdout.decode().splitlines():
        diagnostic = json.loads(line)
        if diagnostic['messageClass'].startswith('MCDiagnostic SevWarning'):
            diagnostic.pop('span', None)
        print(json.dumps(diagnostic))
else: sys.stdout.buffer.write(result.stdout)
sys.exit(result.returncode)
`);
    chmodSync(join(root, 'tools/ghc'), 0o755);
    return { PATH: `${join(root, 'tools')}:${process.env.PATH}` };
}

for (const fault of ['malformed', 'missing-span']) {
    test(`invalid ${fault} compiler diagnostics cannot certify strict success`, (t) => {
        const root = fixture(t);
        passes(run(root));
        rejects(run(root, { ...compilerAdapter(root), WARNING_TEST_FAULT: fault }), 'parse error|unsupported GHC diagnostic');
        passes(run(root));
    });
}

async function waitUntil(predicate) {
    const deadline = Date.now() + 10_000;
    while (!predicate()) {
        assert.ok(Date.now() < deadline, 'fixture boundary deadline exceeded');
        await new Promise((resolve) => setTimeout(resolve, 10));
    }
}

function start(root, environment) {
    const child = spawn('bash', [join(scripts, 'haskell/application-warnings')], {
        cwd: root, env: { ...process.env, BEPIS_SCRIPTS_ROOT: scripts, APPLICATION_WARNINGS_BUILD_DIR: join(root, 'cache'), ...environment },
    });
    let stdout = '', stderr = '';
    child.stdout.on('data', (data) => { stdout += data; });
    child.stderr.on('data', (data) => { stderr += data; });
    const finished = new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('close', (status) => resolve({ status, stdout, stderr }));
    });
    return finished;
}

test('same-output concurrent callers cannot overwrite each other’s diagnostics', async (t) => {
    const root = fixture(t);
    const adapter = compilerAdapter(root);
    const first = join(root, 'first'), second = join(root, 'second');
    const a = start(root, { ...adapter, WARNING_TEST_MARKER: first, WARNING_TEST_FAULT: 'malformed' });
    let b;
    try {
        await waitUntil(() => existsSync(first));
        b = start(root, { ...adapter, WARNING_TEST_MARKER: second });
        await new Promise((resolve) => setTimeout(resolve, 500));
        assert.equal(existsSync(second), false, 'second compiler entered a shared output graph before the first owner finished');
    } finally {
        writeFileSync(first + '.release', 'release');
        writeFileSync(second + '.release', 'release');
        const resultA = await a;
        rejects(resultA, 'parse error');
        if (b) passes(await b);
    }
});

test('the original dependency-first multi-file skip cannot conceal an unused import', (t) => {
    const root = fixture(t);
    passes(run(root));
    const path = join(root, 'Application/Model.hs');
    put(root, 'Application/Model.hs', readFileSync(path, 'utf8').replace('data Marker', 'import Data.List (sort)\ndata Marker'));
    rejects(run(root), 'GHC-66111');
});
