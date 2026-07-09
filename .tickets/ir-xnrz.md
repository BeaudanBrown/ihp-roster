---
id: ir-xnrz
status: open
deps: []
links: []
created: 2026-07-09T02:39:00Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, schema]
---
# Harden active roster-timesheet link uniqueness

Make roster-slot-to-timesheet uniqueness active-entry aware.

## Design

Update Application/Schema.sql and migration so source_roster_slot_id uniqueness applies only to non-deleted timesheet_entries. Preserve venue-integrity trigger and historical deleted rows.

## Acceptance Criteria

Schema and migration use a partial unique index on source_roster_slot_id where source_roster_slot_id is not null and deleted_at is null. Generated types and schema tests are updated. Existing linked automation tests still pass.

