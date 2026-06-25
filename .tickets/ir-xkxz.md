---
id: ir-xkxz
status: open
deps: [ir-ftfp]
links: []
created: 2026-06-25T11:32:58Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, interaction]
---
# Introduce generated frontend contract foundation

Replace the broad string-embedded frontend contract output with a generator pipeline based on Haskell-owned schemas and `aeson-typescript`.

## Design

Keep the existing `frontend-contracts` and `frontend-contracts-check` entrypoints, but change the implementation behind `Application.Helper.Frontend.Contracts` so generated TypeScript declarations come from Haskell schema/type metadata rather than large handwritten TypeScript source blocks. Use `aeson-typescript` for declarations where possible, and keep only small composition/header helpers where needed. Add guardrails that reject new large handwritten TypeScript declaration blocks for Haskell-owned contracts.

This foundation should support later tickets that generate live-update protocol types, interaction schemas, surface manifests, and schema-driven validators/type guards.

## Acceptance Criteria

`frontend-contracts` still writes `frontend/ts/generated/contracts.ts`; `frontend-contracts-check` still detects drift; large handwritten live-update/interaction TypeScript declaration blocks are removed or replaced by generator output for at least the foundation/prototype path; guard tests or lint checks document and enforce the no-large-handwritten-TS-declarations rule; `typecheck` and focused contract tests pass.

