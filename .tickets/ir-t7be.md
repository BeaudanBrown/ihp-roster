---
id: ir-t7be
status: open
deps: []
links: []
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, coordinator:coordinator-wii, area:roster, area:bootstrap]
---
# Roster groups and centralized venue bootstrap defaults

Repo-local implementation epic migrated from coordinator-wii and `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`. Current future-work routing lives in `docs/workstreams/roster-groups.md`. Moves scheduling toward venue-owned roster groups and one idempotent minimum roster bootstrap path.

## Design

coordinator_epic: coordinator-wii
project_id: ihp-roster
source_plan: docs/archive/plans/49-roster-groups-and-venue-bootstrap.md
workstream: docs/workstreams/roster-groups.md
status: planned
base_branch: roster
work_branch: roster
repo_tracker: .tickets
settled_direction:
  - roster groups are the scheduling boundary inside a venue
  - venue bootstrap creates/repairs minimum roster defaults idempotently
  - staff applicability to roster groups is explicit
  - group-aware UI/admin/live-update work follows the model and bootstrap foundation

## Acceptance Criteria

Venues can own multiple roster groups, shared bootstrap guarantees default groups/slots, staff eligibility is group-aware, and roster UI/admin/live-update scopes include roster group where needed.
