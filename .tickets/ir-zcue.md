---
id: ir-zcue
status: closed
deps: []
links: []
created: 2026-07-09T05:06:02Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, frontend-contracts, interaction]
---
# Add source/dropzone compatibility to typed interaction contracts

Extend the typed FrontendSurface interaction contract so source refs can declare compatible dropzone refs instead of relying only on shared session kind.

## Design

Update Application.Helper.FrontendContract.Surface DSL, IR, reflection/lowering, validation, adapter, and TypeScript generation to model source/dropzone compatibility. Preserve current behavior by default for existing one-source/one-dropzone surfaces. Add focused contract coverage and validation diagnostics for invalid references.

## Acceptance Criteria

Generated FrontendSurface interaction manifests include compatibility data. Invalid compatibility references fail surface validation. Existing roster generated contracts remain compatible before the roster-specific ref split. frontend-contracts/check and focused FrontendSurface contract tests pass.

