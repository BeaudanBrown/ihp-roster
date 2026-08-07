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

`production-inventory-check` is blocking. It rejects unclassified or stale
modules/scripts, missing deployment consumers, disagreement between deployed
NixOS executable references and the production script list, or leakage through
the filtered production source. `production-package-smoke` builds the optimized
package, checks its exact `bin/` set, enters every binary through the non-mutating
GHC RTS boundary, and evaluates wage-cutover and billing deployment modules.

After intentionally adding or changing a module or script:

1. edit `production-script-inventory.tsv` when an entry point changed;
2. run `bash ./bin/in-env node scripts/production-inventory.mjs --write`;
3. review every changed classification and reason;
4. run `bash ./bin/in-env production-inventory-check`;
5. for production changes, run
   `bash ./bin/in-env production-package-smoke`.

Development seeds, fixtures, generators, probes, and architecture tooling must
not be promoted merely to make a build pass. Promotion requires a concrete
production runtime, deployment, maintenance, recovery, or recurring-service
consumer.
