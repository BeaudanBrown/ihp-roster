import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, truncateSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const checker = fileURLToPath(new URL('./production-artifacts.mjs', import.meta.url));

function put(path, content = 'fixture') {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, content);
}

function fixture(t, count = 2) {
    const root = mkdtempSync(join(tmpdir(), 'production-artifacts-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const cabal = join(root, 'app-lib.cabal');
    const output = join(root, 'output');
    const library = join(output, 'lib', 'app-lib');
    const modules = Array.from({ length: count }, (_, index) => `Application.Module${index}`);
    put(cabal, `name: app-lib\nlibrary\n    exposed-modules:\n        ${modules.join('\n        ')}\n    default-language: GHC2021\n`);
    for (const name of modules) put(join(library, `${name.replaceAll('.', '/')}.hi`));
    put(join(library, 'libHSapp-lib.a'));
    put(join(output, 'lib', 'package.conf.d', 'app-lib.conf'));
    put(join(output, 'nix-support', 'propagated-build-inputs'));
    return { cabal, output, library };
}

function run(input) {
    const result = spawnSync(process.execPath, [checker, input.cabal, input.output], { encoding: 'utf8' });
    assert.ifError(result.error);
    return result;
}

function fails(input, diagnostic) {
    const result = run(input);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, diagnostic);
}

test('current declared modules and large sparse artifacts pass without historical count or byte caps', (t) => {
    const input = fixture(t, 610);
    truncateSync(join(input.library, 'Application/Module0.hi'), 700 * 1024 * 1024);
    truncateSync(join(input.library, 'libHSapp-lib.a'), 1100 * 1024 * 1024);
    const result = run(input);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /610 declared interfaces; static-only/);
});

test('a wrong interface fails even when the total count is unchanged', (t) => {
    const input = fixture(t);
    rmSync(join(input.library, 'Application/Module0.hi'));
    put(join(input.library, 'Application/Unexpected.hi'));
    fails(input, /missing: Application\/Module0.hi; unexpected: Application\/Unexpected.hi/);
});

test('missing and additional interfaces fail independently', (t) => {
    const input = fixture(t);
    put(join(input.library, 'Application/Unexpected.hi'));
    fails(input, /unexpected: Application\/Unexpected.hi/);
    rmSync(join(input.library, 'Application/Unexpected.hi'));
    rmSync(join(input.library, 'Application/Module0.hi'));
    fails(input, /missing: Application\/Module0.hi/);
});

for (const name of ['Extra.dyn_hi', 'Extra.p_hi', 'libExtra.so', 'libExtra.so.1', 'Extra.o', 'undeclared-output']) {
    test(`unexpected ${name} artifacts fail, including symlinks`, (t) => {
        const input = fixture(t);
        const path = join(input.library, name);
        put(path);
        fails(input, /unexpected app-library artifact/);
        rmSync(path);
        symlinkSync('libHSapp-lib.a', path);
        fails(input, /unexpected app-library artifact/);
    });
}

for (const [name, extra] of [['libHSapp-lib.a', 'extra.a'], ['../package.conf.d/app-lib.conf', 'extra.conf']]) {
    test(`missing or duplicate ${name} fails`, (t) => {
        const input = fixture(t);
        put(join(input.library, extra));
        fails(input, /expected exactly one/);
        rmSync(join(input.library, extra));
        rmSync(join(input.library, name));
        fails(input, /expected exactly one/);
    });
}

test('required Nix dependency metadata cannot disappear', (t) => {
    const input = fixture(t);
    rmSync(join(input.output, 'nix-support/propagated-build-inputs'));
    fails(input, /missing propagated-build-inputs metadata/);
});

test('file symlinks remain supported, but broken links and symlinked directories fail', (t) => {
    const input = fixture(t);
    const path = join(input.library, 'Application/Module0.hi');
    rmSync(path);
    symlinkSync('Module1.hi', path);
    assert.equal(run(input).status, 0);
    rmSync(path);
    symlinkSync('Missing.hi', path);
    fails(input, /ENOENT/);
    rmSync(path);
    symlinkSync('..', path);
    fails(input, /not a regular artifact/);
});

test('unavailable or malformed module declarations fail instead of guessing a count', (t) => {
    const input = fixture(t);
    for (const content of ['', 'library\n    exposed-modules:\n', 'library\n    exposed-modules: A A\n', 'library\n    exposed-modules: A\n    exposed-modules: B\n', 'library\n    exposed-modules: ../A\n']) {
        put(input.cabal, content);
        fails(input, /exposed.modules/);
    }
    rmSync(input.cabal);
    fails(input, /ENOENT/);
});
