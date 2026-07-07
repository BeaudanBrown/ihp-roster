---
id: ir-78cn
status: closed
deps: [ir-kuyy, ir-7j0h, ir-5v0t]
links: []
created: 2026-05-29T03:16:11Z
type: epic
priority: 3
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, cleanup, verification, docs, frontend-surface]
---
# Finalize app-wide FrontendSurface actor invalidation pattern

Remove obsolete compatibility paths, add guardrails, and verify the app-wide migrated `FrontendSurface` success response model after feature migrations.

## Design

This closeout phase inventories remaining OOB/direct hx-target paths, confirms intentional exceptions, updates docs/tests, removes obsolete helper paths, and runs broad verification. Guardrails should distinguish allowed extras/validation-local OOB from prohibited authoritative business OOB on successful migrated `FrontendSurface` mutations.

## Acceptance Criteria

No migrated `FrontendSurface` successful actor response emits authoritative business `hx-swap-oob` HTML. Remaining direct/OOB paths are classified as validation-local, extras-only, pure fragment GET/refetch, non-FrontendSurface, or separately ticketed legacy exceptions. Guardrails catch regressions. Canonical verification passes or unrelated failures are documented. The epic closeout note confirms duplicate-mount actor-local refresh and passive websocket invalidation coverage.

## Notes

**2026-07-07T05:25:57Z**

Final app-wide pattern complete. Cleanup inventory, obsolete helper removal, guardrail tests, and final verification are closed. Migrated FrontendSurface success responses now consistently use actor-local semantic invalidation plus non-authoritative extras; authoritative business HTML is served by fragment GET/refetch endpoints.
