// frontend-check compiles the representative golden once, outside Hspec.
// FrontendContractSpec independently requires exact equality to fresh output.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";

const directory = mkdtempSync(join(tmpdir(), "bepis-contract-empty-"));
try {
    const source = join(directory, "contract.ts");
    writeFileSync(source, readFileSync(0, "utf8"));
    const types = join(directory, "types");
    mkdirSync(types);
    // Expect errors for callers attempting to inhabit the empty vocabularies.
    writeFileSync(join(directory, "consumer.ts"), `
import { surfaceFragmentKeyIdentity, type SurfaceScope, type SurfaceFragmentKey, type FrontendSurfaceInteractionSurfaceName } from "./contract";
type RequireNever<Value extends never> = Value;
type EmptyScopes = RequireNever<SurfaceScope>;
type EmptyFragmentKeys = RequireNever<SurfaceFragmentKey>;
type EmptyInteractionNames = RequireNever<FrontendSurfaceInteractionSurfaceName>;
// @ts-expect-error Untyped objects must not become legal fragment keys.
surfaceFragmentKeyIdentity({});
`);
    const result = spawnSync("tsc", [
        "--strict", "--target", "ES2020", "--module", "commonjs",
        "--typeRoots", types, "--outDir", join(directory, "out"),
        source, join(directory, "consumer.ts"),
    ], { encoding: "utf8", timeout: 30_000 });
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const contract = createRequire(import.meta.url)(join(directory, "out", "contract.js"));
    // Simulate untyped JS callers at the boundary; TS callers cannot supply keys.
    for (const value of [undefined, null, false, 0, "", "invented", [], {}, { surface: "invented", kind: "invented", params: {} }]) {
        assert.equal(contract.isFrontendSurfaceInteractionSurfaceName(value), false);
        assert.equal(contract.isSurfaceFragmentKey(value), false);
        assert.equal(contract.isSurfaceScope(value), false);
        assert.throws(() => contract.surfaceFragmentKeyIdentity(value), {
            message: "No Surface fragment keys are declared",
        });
        assert.throws(() => contract.surfaceFragmentKeysEqual(value, value), {
            message: "No Surface fragment keys are declared",
        });
    }
    console.log("frontend-contract-empty: strict fixture compilation and runtime rejection passed");
} finally {
    rmSync(directory, { recursive: true, force: true });
}
