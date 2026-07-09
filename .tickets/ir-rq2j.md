---
id: ir-rq2j
status: open
deps: [ir-k0wt]
links: []
created: 2026-07-09T02:39:00Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, ui]
---
# Render expected timesheet cards

Render expected roster shifts as visually distinct timesheet cards.

## Design

Add translucent/ghost expected cards to the existing timesheet day sections. Show exact roster start/end, staff, shift type, and an expected label. Include a finalise/materialise action affordance without presenting the card as approved or unapproved concrete payroll data.

## Acceptance Criteria

Timesheet UI clearly distinguishes expected cards from concrete approved/unapproved entries. Staff and manager views render expected cards in the correct day sections with finalise controls. Styling is responsive and covered by focused render tests or screenshots where practical.

