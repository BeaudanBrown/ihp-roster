---
id: ir-u4mc
status: open
deps: []
links: [ir-d6kt, ir-caf4, ir-j3eq, ir-tfed]
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:data-retention, area:schema, source:plans-55]
---
# Record retention and soft deletion guardrails

Repo-local epic migrated from `docs/archive/plans/55-record-retention-soft-deletion.md`. Current future-work routing lives in `docs/workstreams/record-retention.md`. Makes protected business records soft-deleted/deactivated and blocks unsafe hard deletes before paid venue data is treated as production.

## Design

source_plan: docs/archive/plans/55-record-retention-soft-deletion.md
workstream: docs/workstreams/record-retention.md
status: planned

## Acceptance Criteria

Protected records use the chosen retention pattern, destructive controller paths are migrated, DB guardrails exist, and export/Xero readiness respects retained history.
