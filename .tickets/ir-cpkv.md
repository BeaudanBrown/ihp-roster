---
id: ir-cpkv
status: open
deps: []
links: [ir-z9cg, ir-gdop, ir-wdi9, ir-tq31, ir-4spc, ir-tjqq]
created: 2026-07-07T07:24:38Z
type: epic
priority: 3
assignee: Beaudan Brown
tags: [frontend-contracts, frontend-surface, htmx, rollout]
---
# App-wide FrontendSurface request-action rollout

Follow-up backlog for migrating remaining surface-owned HTMX request initiators after the generated action infrastructure and Admin Roster Groups proof slice.

## Design

Migrate category by category. Keep response extras/OOB, shell/container behavior, lazy loads, global dialogs, and pure view-state GETs out of SurfaceAction unless a surface intentionally owns the control. Successful migrated mutations must use actor-local/passive invalidation instead of authoritative business OOB HTML.

## Acceptance Criteria

Remaining surface-owned request initiators are migrated to generated FrontendSurface action helpers or explicitly classified as non-surface/global/container/lazy/response behavior.

