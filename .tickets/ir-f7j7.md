---
id: ir-f7j7
status: closed
deps: []
links: []
created: 2026-04-30T06:56:44Z
type: task
priority: 1
assignee: beaudan
parent: ir-hw2v
tags: [area:admin, area:payroll]
---
# Convert pay-relevant admin edits to append-only version actions

Change admin/pay config edit flows so pay-relevant changes create new version rows instead of mutating historical facts.

## Design

Shift type display fields may remain editable only when they are not historical/export labels; pay mapping changes create shift_type_pay_versions. Staff default award level and employment basis changes create staff_pay_versions. Accepted new award/rate imports create new active rate/application versions. Avoid creating pay versions for non-pay changes such as sort order.

## Acceptance Criteria

Admin tests cover creating new versions for pay-relevant edits, old approved entries continue referencing old versions, and non-pay edits do not create pay versions.


## Notes

**2026-04-30T07:28:58Z**

Converted pay-relevant staff and shift type admin edits to create append-only staff_pay_versions/shift_type_pay_versions; non-pay shift type sort changes no longer create pay versions. Existing approved rows retain their pinned version ids.
