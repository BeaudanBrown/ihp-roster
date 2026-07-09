---
id: ir-3arn
status: open
deps: [ir-bftt]
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3txn
tags: [agent-loop, payroll, tests]
---
# Add award effective-date regression tests

Cover first-full-pay-period award-rate behavior.

## Design

Add focused Hspec/SQL golden coverage for a week crossing 1 July that began before 1 July, a week starting on 1 July, and relevant ordinary/penalty/time-allowance paths where fixtures support them.

## Acceptance Criteria

Regression tests fail under per-worked-day operative-date behavior and pass with week-start effective-date behavior. Tests document the Fair Work first-full-pay-period rule and the V1 roster/timesheet week proxy.

