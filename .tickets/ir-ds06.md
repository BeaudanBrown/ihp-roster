---
id: ir-ds06
status: open
deps: [ir-ypt5]
links: []
created: 2026-07-02T04:06:34Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, docs]
---
# Document FrontendSurface authoring workflow

Update living subsystem docs for type-level `FrontendSurface` authoring, `SurfaceImpl` runtime implementation, generated TypeScript consumption, and migration/removal rules.

## Design

Update implementation docs after facts land:

- `Application/Helper/Frontend/README.md`
- `Application/Helper/LiveUpdate.SPEC.md`
- `Application/Helper/Interaction.SPEC.md`
- `Application/Helper/LiveSurface.COOKBOOK.md`
- `frontend/AGENTS.md`
- `static/AGENTS.md`
- relevant Timesheets/Roster docs if behavior changed

Docs must explain:

- `RegisteredFrontendSurfaces` as the root source of truth and the derived `SurfaceImpl` runtime registry;
- primitive DSL and helper expansion;
- shared declaration merge/validation;
- naming policy;
- `SurfaceContractIR` extraction/generation pipeline;
- `SurfaceImpl` responsibilities and the decision that controllers remain mutation entrypoints for this epic;
- direct rendering first/no `SurfaceProjection` policy for migrated surfaces;
- closest-mount request decoration, mount-local fragment resolution, and unified live invalidation/refetch for successful actor and passive updates;
- typed mount state and swappable backends;
- generated TS consumption rules;
- hybrid migration boundaries and removal/guardrails for old authoring paths.

## Acceptance Criteria

- Docs describe the new implemented workflow well enough for a fresh agent to add a surface without asking for architecture decisions.
- Docs identify which old modules/paths are replaced or forbidden for migrated surfaces.
- `bash ./bin/in-env ./bin/doc-drift-check` passes.
