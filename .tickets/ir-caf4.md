---
id: ir-caf4
status: open
deps: []
links: [ir-15fg, ir-u4mc, ir-d6kt, ir-2ds0, ir-5rhn, ir-7gm0, ir-c6cu, ir-lz0x, ir-3vc6]
created: 2026-04-29T04:41:30Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:schema, source:plans-60]
---
# V1 schema hardening

Repo-local epic migrated from `docs/archive/plans/60-v1-schema-hardening.md`. Current future-work routing lives in `docs/workstreams/schema-hardening.md`. Hardens schema invariants for snapshots, tenant integrity, roster/availability, checks, uniqueness, statuses, lineage, indexes, and statistics.

## Design

source_plan: docs/archive/plans/60-v1-schema-hardening.md
workstream: docs/workstreams/schema-hardening.md
status: planned
notes: plan file is currently untracked local work; keep ticket as migration anchor without rewriting that plan

## Acceptance Criteria

V1 schema constraints make payroll, tenant, roster, public holiday, export, and lifecycle invariants enforceable without breaking IHP schema parsing.
