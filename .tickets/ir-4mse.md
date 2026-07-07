---
id: ir-4mse
status: closed
deps: [ir-qq35]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-elys
tags: [docs, frontend-contracts, htmx]
---
# Document FrontendSurface action contract pattern

Record the reusable generated action pattern for future surface migrations.

## Design

Update FrontendContract/Surface docs and Web/View agent guidance with the route-construction split: DSL owns browser-visible request semantics and submitted fields; Haskell runtime handlers own IHP paths; generated TS validates action metadata. Include the Admin Roster Groups example and explicit guidance for what does not belong in `SurfaceAction`.

Document:

- standard action option usage;
- `CustomHtmx` requirements and review expectations;
- actor-local refresh/invalidation as the successful mutation path;
- validation/direct response exceptions;
- form/button/link/HTMX-only helper modes;
- non-JS semantics caveat;
- app-wide migration checklist.

## Acceptance Criteria

- Docs explain how to add a generated surface action end-to-end.
- Docs explain when not to use this system: OOB response extras, shell/container attrs, lazy fragment loads, global non-surface controls, and pure view-state GETs unless intentionally modeled.
- Future migrations have a clear checklist and verification commands.
