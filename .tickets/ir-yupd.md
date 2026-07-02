---
id: ir-yupd
status: open
deps: [ir-xopg]
links: []
created: 2026-07-02T04:06:23Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, nix]
---
# Wire FrontendSurface generator into Nix/dev scripts

Add Nix/devenv-owned commands for the GHC API `FrontendSurface` generator and integrate them with the existing frontend contract generation/check/watch workflows.

## Design

- Generator execution is owned by repo/Nix scripts. Developers should not need global tools or ad hoc `ghc` commands.
- Expose the `ghc` package/GHC API only in the generator command path as needed.
- Prefer folding generated surface contracts into existing commands once stable:

  ```bash
  bash ./bin/in-env frontend-contracts
  bash ./bin/in-env frontend-contracts-check
  bash ./bin/in-env frontend-contracts-watch
  ```

- Generated output must be deterministic and atomically written.
- Watch mode initially may fingerprint broad Haskell sources for correctness, but the target is registry module, surface DSL/extractor/renderer modules, and feature surface specs.
- If a temporary separate command is useful during implementation, it must still be Nix-owned and later folded into the canonical frontend contract commands.

## Acceptance Criteria

- `frontend-contracts` runs the new surface generator deterministically and writes generated TypeScript/runtime metadata, while preserving any required legacy generated sections during hybrid migration.
- `frontend-contracts-check` fails on stale generated output or extractor validation errors.
- `frontend-contracts-watch` regenerates on relevant Haskell surface/registry changes.
- No global install, `npm`/`npx`, or ad hoc host package setup is required.
- CI/local checks use the same Nix-owned command path.
