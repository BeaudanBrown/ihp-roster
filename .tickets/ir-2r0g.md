---
id: ir-2r0g
status: open
deps: [ir-ibrg]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, timesheets]
---
# Implement MYOB period selection and provider period state

Adapt shared period selection to MYOB, which does not expose Xero-style payroll calendars or pay runs for the target flow.

## Design

Define how MYOB periods are derived from Bepis venue/payroll settings and remote timesheet queries. Represent provider capabilities so the shared UI can show Xero pay-run/calendar information when available and MYOB local/remote timesheet state when not. Include same-week-start/day-boundary checks where relevant.

## Acceptance Criteria

Payroll period selection works for MYOB without pretending pay runs exist. The UI explains which period is being submitted, how it was derived, and whether remote MYOB timesheet state exists. Tests cover period derivation and provider capability rendering.

