---
id: ir-7dqy
status: open
deps: [ir-nlv5, ir-yoho]
links: []
created: 2026-06-15T23:44:59Z
type: feature
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:roster, launch]
---
# Surface trial staff on roster page and staff panel

Expose trial staff in the roster workflow and render their staff-panel role as TRIAL without adding a new column.

## Design

Add a roster-page/staff-panel affordance that opens the create-trial-staff flow. Ensure active, non-archived trial staff are available in roster assignment options and staff panel scopes alongside linked rosterable staff. In staff-panel role resolution, trial staff short-circuit to TRIAL; linked staff continue using venue membership role labels. Preserve existing staff edit modal behavior for trial rows.

## Acceptance Criteria

Trial staff appear in the roster staff panel after creation. Their role cell reads TRIAL. Trial staff can be assigned to roster slots. Linked staff role display remains worker/manager/venue admin/venue owner as before. Focused roster tests cover panel role/visibility and assignment eligibility.

