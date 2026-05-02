---
id: ir-z87w
status: open
deps: [ir-shsr]
links: []
created: 2026-05-02T01:12:19Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:xero, area:payroll, area:pilot, venue:rooks]
---
# Support staff-level Xero custom pay item overrides

## Design

Allow imported/synced Xero earnings-rate pay items to be selected as staff-level overrides. The Rooks owner-pay case uses one custom Xero pay item for owner staff and collapses all owner generated timesheet lines to that pay item. Dropdown labels should show the human-readable Xero pay item name first, then account code metadata.

Workstream: `docs/workstreams/rooks-pilot.md`

## Acceptance Criteria

Xero pay item dropdowns put name before account code; venue can assign a custom synced Xero earnings rate as a staff-level override; override wins for all generated Xero timesheet lines for that staff member; ordinary staff continue using managed pay item mappings; readiness/preview/submission surfaces show the override clearly.
