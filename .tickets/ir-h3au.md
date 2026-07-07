---
id: ir-h3au
status: open
deps: [ir-4dtf]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, verification, frontend-surface]
---
# Verify roster live resync actor invalidation and parity after migration

Run and extend roster verification after the semantic actor-local invalidation migration.

## Design

Exercise actor-local invalidation, duplicate mounts, passive invalidations, websocket echo suppression, reconnect/resync defaults, direct vs projection backend rendering, manager/staff visibility, interaction conflicts, and mobile horizontal behavior.

## Acceptance Criteria

Relevant roster Hspec suites and E2E pass. New coverage proves actor-local duplicate-mount refresh and passive websocket behavior. No stale roster successful actor business-OOB helper path remains except documented intentional non-migrated/validation/extras cases.
