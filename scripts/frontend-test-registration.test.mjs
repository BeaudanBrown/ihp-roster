import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
function run(files) {
    const root = mkdtempSync(resolve(tmpdir(), "frontend-registration-"));
    try {
        mkdirSync(resolve(root, "scripts"));
        copyFileSync(resolve(repository, "scripts/frontend-test-registration.mjs"), resolve(root, "scripts/frontend-test-registration.mjs"));
        for (const [name, content] of Object.entries(files)) {
            const path = resolve(root, "frontend/ts", name);
            mkdirSync(dirname(path), { recursive: true });
            writeFileSync(path, content);
        }
        return spawnSync("bash", [resolve(repository, "Config/nix/scripts/frontend/test")], {
            cwd: root, env: { ...process.env, FRONTEND_REPO_ROOT: root }, encoding: "utf8",
        });
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

test("direct imports retain execution order; support files need no registration", () => {
    const result = run({
        "tests/main.ts": 'import "./first.test"; import "./second.test";',
        "tests/first.test.ts": 'console.log("first");',
        "tests/second.test.ts": 'console.log("second");',
        "tests/support.ts": 'throw new Error("unused support");',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "first\nsecond\n");
});

test("static transitive imports register nested and colocated tests", () => {
    const result = run({
        "tests/main.ts": 'import "./group";',
        "tests/group.ts": 'import "./nested/example.test"; import "../feature/example.test";',
        "tests/nested/example.test.ts": 'console.log("nested");',
        "feature/example.test.ts": 'console.log("colocated");',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "nested\ncolocated\n");
});

for (const registration of ["", 'if (false) import("./omitted.test");', 'import("./omitted.test");', 'import type { Example } from "./omitted.test";']) {
    test(`omitted throwing sentinel is rejected before execution: ${registration || "no import"}`, () => {
        const result = run({
            "tests/main.ts": `${registration}\nconsole.log("entry executed");`,
            "tests/omitted.test.ts": 'export type Example = string; throw new Error("SENTINEL");',
        });
        assert.equal(result.status, 1, result.stderr);
        assert.match(result.stderr, /missing static registration/);
        assert.match(result.stderr, /frontend\/ts\/tests\/omitted\.test\.ts/);
        assert.equal(result.stdout, "");
        assert.doesNotMatch(result.stderr, /Error: SENTINEL/);
    });
}

test("registering the same throwing sentinel propagates its failure", () => {
    const result = run({
        "tests/main.ts": 'import "./omitted.test";',
        "tests/omitted.test.ts": 'export type Example = string; throw new Error("SENTINEL");',
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Error: SENTINEL/);
    assert.doesNotMatch(result.stderr, /missing static registration/);
});
