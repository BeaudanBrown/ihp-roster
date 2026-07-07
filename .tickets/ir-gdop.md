---
id: ir-gdop
status: open
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [timesheets, frontend-contracts, htmx]
---
# Migrate Timesheets request actions

Classify timesheet week navigation, entry dialog launchers/submits, approve/unapprove mutations, and history shell attrs. Migrate surface-owned request initiators to generated action contracts; keep hx-history-elt and response OOB extras out of SurfaceAction.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.

