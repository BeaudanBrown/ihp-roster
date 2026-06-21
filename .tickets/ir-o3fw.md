---
id: ir-o3fw
status: closed
deps: [ir-j3hy]
links: []
created: 2026-06-21T04:02:33Z
type: task
priority: 2
assignee: beaudan
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, haskell, contracts]
---
# Establish Haskell-to-TypeScript frontend contracts

Add a narrow backend-owned contract generation layer so TypeScript browser code consumes Haskell-defined frontend boundary DTOs instead of duplicating backend assumptions.

## Design

Define a small Haskell-owned frontend contract module for browser boundary data only, such as JSON embedded in data attributes, live-update surface configs/messages, roster UI config enums, overlay lanes, and capability/config objects. Generate TypeScript types under frontend/ts/generated/ through Nix/devenv commands, e.g. frontend-contracts and frontend-contracts-check. Keep the frontend thin: do not generate broad database model types or move domain authority into TypeScript. Integrate contract drift into frontend-check when practical, and keep the production/live NixOS runtime Node-free with generated contract files checked in or reproducibly generated during checks.

## Acceptance Criteria

At least one Haskell-owned frontend DTO/enum generates a TypeScript type consumed by the migrated frontend baseline. Generated TS contract files are reproducible and not hand-edited. bash ./bin/in-env frontend-contracts and bash ./bin/in-env frontend-contracts-check work through Nix/devenv without npm/npx. The contract layer is documented as backend-owned and limited to frontend boundary payloads. Future conversion tickets can rely on generated contracts for JSON/data-* boundaries where applicable.


## Notes

**2026-06-21T04:29:56Z**

Implemented initial backend-owned frontend contract generator. Application.Helper.Frontend.Contracts defines a Haskell OverlayLane enum and emits frontend/ts/generated/contracts.ts; frontend-contracts and frontend-contracts-check run through Nix/devenv; frontend-check now includes contract drift, tsc, and generated JS drift. The initial migrated app.ts consumes the generated OverlayLane type as a compile-time smoke test. Verified frontend-contracts, frontend-contracts-check, frontend-check, typecheck Application/Script/GenerateFrontendContracts.hs, stale contract detection, and nix build .#checks.x86_64-linux.frontend-drift.
