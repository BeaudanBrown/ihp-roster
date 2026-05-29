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
tags: [agent-loop, roster, verification]
---
# Verify roster live resync and projection/direct parity after migration

Run and extend roster verification after the migration.

## Design

Exercise passive invalidations, reconnect/resync defaults, direct vs projection backend rendering, manager/staff visibility, and mobile horizontal behavior.

## Acceptance Criteria

Relevant roster Hspec suites and E2E pass; any new edge-case coverage is committed; no stale actor-refresh helper path remains except documented intentional cases.

