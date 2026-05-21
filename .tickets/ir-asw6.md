---
id: ir-asw6
status: open
deps: []
links: [ir-qqgf]
created: 2026-05-21T03:34:52Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, roster, ui]
---
# Roster shift type badges and day-column clarity

Make the roster day-column view easier to scan by start time while keeping draft and live roster cards visually consistent. Add persistent shift-type colour tokens for badge accents, fix standard day-row day-boundary borders, and make shift type mandatory for staffed live shifts regardless of end-time configuration.

## Design

Decisions: shift type appears as a compact badge in day-column cards. Draft/editable badges remain interactive select controls; live/read-only badges use the same shape without interactive affordance. Assigned badges show the full shift type name plus a small colour marker/accent. Unassigned badges show 'Type'; staffed shifts missing a type show 'Type required' with warning/dashed styling. Use a fixed palette of 10 distinct colour keys plus a reusable default colour. Active shift types within a venue should have unique non-default colour keys where possible; active shift types beyond the first 10 use the reusable default. Uniqueness applies only to active shift types. When an inactive shift type is reactivated and its stored colour collides with an active type, reassign the first available palette key or default. Store colour keys on shift_types now so later admin configurability can build on the same field, but do not add manual colour editing in this slice. Standard day-row shift type cells stay in the existing cell format, with only a subtle internal colour accent if practical. Conflict/issue highlighting remains visually dominant over type colour.

## Acceptance Criteria

Day-column draft and live cards use a shared badge treatment for shift type, remain readable with and without end times, and scan top-to-bottom by start time. Shift type colour keys are persisted, assigned automatically from the 10-key palette/default rule, and reassigned on activation when needed. Publishing a roster requires shift type on every staffed shift regardless of end-times setting. Standard day-row day boundaries render clearly across the grid. Relevant controller/helper specs and focused UI/screenshot/e2e checks cover the new behaviour. Local roster docs/spec mention the implemented contract.


## Notes

**2026-05-21T04:11:33Z**

All implementation children under this epic are now closed. Epic acceptance appears documented/covered by child tickets; final verification attempted with doc-drift-check but failed on unrelated AGENTS.md nav text mismatch (expected leave vs current unavailability). Linked follow-up ir-qqgf remains open for future manual colour configuration.
