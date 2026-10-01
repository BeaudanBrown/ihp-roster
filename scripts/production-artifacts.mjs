#!/usr/bin/env node

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, extname, join, relative } from 'node:path';

function files(root) {
    return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
        const path = join(root, entry.name);
        return entry.isDirectory() ? files(path) : [path];
    });
}

// This reads IHP's generated app-lib declaration, not arbitrary handwritten
// Cabal. Reject missing/ambiguous declarations rather than guessing a count.
function declaredModules(cabalPath) {
    const lines = readFileSync(cabalPath, 'utf8').split(/\r?\n/);
    const fields = lines.flatMap((line, index) => /^\s*exposed-modules:/.test(line) ? [index] : []);
    if (fields.length !== 1) throw new Error('expected one generated exposed-modules field');
    const index = fields[0];
    const indentation = lines[index].match(/^\s*/)[0].length;
    const values = [lines[index].split(':')[1]];
    for (const line of lines.slice(index + 1)) {
        if (!line.trim()) continue;
        if (line.match(/^\s*/)[0].length <= indentation) break;
        values.push(line);
    }
    const modules = values.join(' ').trim().split(/[\s,]+/);
    if (modules.some((name) => !/^[A-Z][A-Za-z0-9_']*(\.[A-Z][A-Za-z0-9_']*)*$/.test(name))
        || new Set(modules).size !== modules.length) {
        throw new Error('invalid or duplicate generated exposed modules');
    }
    return modules.map((name) => `${name.replaceAll('.', '/')}.hi`).sort();
}

function inspect(cabalPath, output) {
    const expected = declaredModules(cabalPath);
    const artifacts = files(output);
    for (const path of artifacts) {
        const name = relative(output, path);
        if (!['.hi', '.a', '.conf'].includes(extname(path)) && name !== 'nix-support/propagated-build-inputs') {
            throw new Error(`unexpected app-library artifact: ${name}`);
        }
        // Follow file symlinks to detect broken links, but never traverse a
        // symlinked directory that could hide additional build ways/artifacts.
        if (!statSync(path).isFile()) throw new Error(`not a regular artifact: ${name}`);
    }
    if (!artifacts.includes(join(output, 'nix-support/propagated-build-inputs'))) {
        throw new Error('missing propagated-build-inputs metadata');
    }
    for (const extension of ['.a', '.conf']) {
        if (artifacts.filter((path) => extname(path) === extension).length !== 1) {
            throw new Error(`expected exactly one ${extension} artifact`);
        }
    }
    const libraryRoot = dirname(artifacts.find((path) => extname(path) === '.a'));
    const actual = artifacts.filter((path) => path.endsWith('.hi')).map((path) => relative(libraryRoot, path)).sort();
    const missing = expected.filter((path) => !actual.includes(path));
    const unexpected = actual.filter((path) => !expected.includes(path));
    if (missing.length || unexpected.length) {
        throw new Error(`interfaces differ from generated app-lib modules; missing: ${missing.join(', ') || 'none'}; unexpected: ${unexpected.join(', ') || 'none'}`);
    }
    console.log(`production-artifacts: ok (${actual.length} declared interfaces; static-only)`);
}

try {
    const [cabalPath, output, ...extra] = process.argv.slice(2);
    if (!cabalPath || !output || extra.length) throw new Error('usage: production-artifacts.mjs APP_LIB_CABAL APP_LIB_OUTPUT');
    inspect(cabalPath, output);
} catch (error) {
    console.error(`production-artifacts: ${error.message}`);
    process.exit(1);
}
