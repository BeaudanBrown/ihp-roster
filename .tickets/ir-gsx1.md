---
id: ir-gsx1
status: closed
deps: []
links: []
created: 2026-05-02T01:12:15Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:timesheets, area:ux, area:pilot, venue:rooks]
---
# Improve timesheet list editing, filtering, and comments

## Design

Refine the timesheet viewing/editing workflow for the pilot. Manager timesheet view gets a staff filter. Timesheet cards open the edit dialog directly instead of relying on a small edit button. Staff can edit only their own staff-facing timesheet comment in the edit dialog. Managers/admins can view the staff comment and edit one manager-only internal note field.

## Acceptance Criteria

Manager timesheet page can filter by staff; clicking a timesheet card opens the edit dialog; staff comment is editable only by the owning staff member; manager-only note is visible/editable only to managers and above; staff comment edits after approval do not create a special post-approval state.


## Notes

**2026-05-02T01:45:38Z**

2026-05-02: Completed in commit e02c847. Added manager staff filtering that preserves timesheet week/day URLs, clickable edit-card links, staff-owned comment editing, manager-only notes, audit snapshots for both fields, and tests covering filter rendering and comment-only edits on approved entries without approval reset.
