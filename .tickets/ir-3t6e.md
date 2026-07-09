---
id: ir-3t6e
status: closed
deps: [ir-zoa9]
links: []
created: 2026-07-09T05:06:02Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, roster, controller, htmx]
---
# Implement server-side roster staff drop intents

Add server-side handling for staff drag/drop onto existing shifts and create targets.

## Design

Add roster controller action/intent handling for staff drop using opaque sourceItemKey and targetDropzoneKey tokens. Parse staff:<staff-id>, existing:<slot-id>, new:<day-id>:<slot-definition-id>:<row-index>, and any resolved create-card target token selected by the contract. Existing shift targets validate scope/editability/eligibility, update staffId through existing roster slot mutation/response helpers, and toast success. Create targets validate scope/editability/eligibility and render the new shift dialog with rosterShiftStaffId preselected while leaving start/end/shift type required.

## Acceptance Criteria

Staff drop onto an existing shift immediately replaces staff and refreshes authoritative roster fragments. Staff drop onto a create target opens the new shift dialog with staff preselected. Invalid, cross-venue, live-week, closed-day, and ineligible-staff cases are rejected server-side. Non-HTMX fallback is safe even if minimal.

