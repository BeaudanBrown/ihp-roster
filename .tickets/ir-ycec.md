---
id: ir-ycec
status: open
deps: [ir-xopg, ir-4hu6]
links: []
created: 2026-07-02T04:06:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, tests]
---
# Add FrontendSurface guardrails and compile-failure checks

Add tests and static guardrails for the type-level `FrontendSurface` architecture, including negative compile tests for `SurfaceImpl` completeness.

## Design

- Add Nix-owned focused compile-failure fixtures, e.g. missing fragment renderer, missing intent/action handler, missing URL/target builder.
- Generator validation/Hspec should cover:
  - duplicate/conflicting shared declarations;
  - naming policy and exact-name allowlist;
  - invalid cross references and wrong reference kinds;
  - unsupported wire types;
  - stale generated output;
  - no old author-facing contract paths in migrated surfaces;
  - stale generated output for both new and hybrid legacy sections.
- Guard migrated surfaces against:
  - `FrontendCodec`/schema group authoring for surface contracts;
  - `TypedLiveSurfaceDefinition` feature-facing authoring;
  - `Web.LiveSurfaceRegistry` catalog entries after migration;
  - `Application.Helper.SurfaceProjection` usage in lab/Timesheets/Roster;
  - raw `data-bepis-*` protocol attrs where helpers should generate them.
- Compile-time errors are preferred for local spec/runtime completeness. Global registry invariants may be generator validation errors if diagnostics are clearer.

## Acceptance Criteria

- Missing required `SurfaceImpl` handlers fail the focused compile-failure check with stable diagnostics.
- Duplicate/conflicting normalized declarations fail generation with clear errors.
- Invalid references to fragments/actions/sessions/layers/DTOs fail generator or compile checks.
- Migrated surfaces are guarded against old frontend contract/live-surface/projection paths while legacy surfaces may continue using old paths until separately migrated.
- Frontend TypeScript exhaustiveness and generated contract drift remain covered by canonical frontend checks.
