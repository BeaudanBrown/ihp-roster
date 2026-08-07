# Production packaging

Production Haskell packaging is closed over explicit executable roots rather
than every non-test source file.

## Inventories

- `production-script-inventory.tsv` classifies every `Application/Script/*.hs`
  entry point as `production` or `development`, names its category, identifies
  its concrete consumer, and records why it belongs there.
- `production-executable-inventory.tsv` owns every packaged binary—including
  the app and worker—and traces each to an exact NixOS consumer marker.
- `production-module-inventory.tsv` is the reviewed, generated reachability
  closure from `Main`, `Config`, and the production script roots. Every Haskell
  source under `Application/`, `Web/`, and `Config/` is classified. Production
  rows enter `project-source.nix`; development rows remain available from the
  working tree and devenv shell.
- `production-package-dependency-inventory.tsv` maps every external module
  imported by that production closure to its reviewed Cabal package. It is the
  direct dependency authority for generated `app-lib.cabal`; package
  availability in the GHC environment is not declaration authority.

`production-inventory-check` is blocking. It rejects unclassified or stale
modules/scripts, missing deployment consumers, disagreement between deployed
NixOS executable references and the production script list, or leakage through
the filtered production source. `production-package-smoke` builds the optimized
package, checks its exact `bin/` set, enters every binary through the non-mutating
GHC RTS boundary, and evaluates wage-cutover and billing deployment modules.

After intentionally adding or changing a module or script:

1. edit `production-script-inventory.tsv` when an entry point changed;
2. run `bash ./bin/in-env node scripts/production-inventory.mjs --write`;
3. when external imports changed, run
   `bash ./bin/in-env node scripts/production-inventory.mjs --write-dependencies`,
   replace every `UNCLASSIFIED` package, and review every mapping and reason;
4. review every changed classification and reason;
5. run `bash ./bin/in-env production-inventory-check`;
6. for production changes, run
   `bash ./bin/in-env production-package-smoke`.

Development seeds, fixtures, generators, probes, and architecture tooling must
not be promoted merely to make a build pass. Promotion requires a concrete
production runtime, deployment, maintenance, recovery, or recurring-service
consumer.

## Test-only Haskell dependencies

`hspec`, `ihp-hspec`, and `QuickCheck` belong to `ihp.devHaskellPackages`, so
Hspec and compile-failure verification retain them while production does not
register them as direct app dependencies. The production inventory rejects
imports of `IHP.Hspec`, `Test.Hspec`, or `Test.QuickCheck` from any reachable
production module.

Upstream IHP builds `app-lib.cabal` from every package registered in its GHC
environment. `production-nix-support.nix` is the managed, fail-closed seam that
replaces that exact upstream command. Production emits the unique packages from
`production-package-dependency-inventory.tsv` instead; it never falls back to
`ghc-pkg list`. During source generation, `ghc-pkg find-module` verifies that
each reviewed package actually exposes its mapped module and reports the module,
declaration, and available packages on disagreement.

`production-inventory-check` rejects new undeclared external imports and stale
mappings with source provenance. `production-package-smoke` independently
compares the generated optimized `app-lib.cabal` dependency set to the reviewed
inventory. Some declared runtime packages themselves retain test packages
transitively—`aeson` retains QuickCheck and monolithic `ihp` retains Hspec—but
those packages are not direct app declarations. Hspec, compile-failure, and
tooling dependencies remain in their separate development/tool package sets.

## Frontend-contract tooling package

`frontend-contract-tool-module-inventory.tsv` is the exact closure of the three
contract, Surface-adapter, and architecture generator roots.
`frontend-contract-tooling-only-policy.tsv` is the reviewed, reason-bearing
negative authority: those modules are forbidden from production reachability,
and a new non-runtime tool module fails until explicitly classified there.
`shared-authority` rows are the single canonical Haskell declarations
legitimately consumed by both runtime and generation. Regenerate the derived
closure with
`bash ./bin/in-env node scripts/production-inventory.mjs --write-tooling` and
review every ownership change.

`.#frontend-contract-tools` compiles that closure independently and exposes
exactly three generator binaries. Its source filter includes only the reviewed
Haskell closure, `Application/Schema.sql`, and `Makefile`: tooling-only edits do
not change the production derivation, and unrelated runtime edits do not change
the tooling derivation. Development commands compile the working tree by default
so uncommitted authoring remains usable; CI and `verify-full` set
`FRONTEND_CONTRACT_USE_PACKAGE=1` and consume the isolated output.

`frontend-contract-package-check` is blocking in both paths. It proves the
optimized production closure does not reference the tooling output, checks the
exact binary set, retains interface/build-resource metrics, and reruns generated
TypeScript, all generated Haskell adapters plus private proofs, and architecture
emission through packaged binaries. Generated repository artifacts are accepted
only when those package-backed freshness checks pass.
