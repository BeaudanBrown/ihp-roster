---
id: ir-shsr
status: open
deps: [ir-adtf, ir-axdb]
links: []
created: 2026-04-29T04:41:30Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-176p
tags: [area:xero, area:payroll, source:plans-57]
---
# Build staff and earnings-rate mapping readiness UI

Expose mapping/readiness state for staff, employees, pay items, and payroll calendars.

## Design

This ticket now includes the readiness checklist tightening needed before draft
timesheet preview work starts. The current checklist is not enough: it checks
connection, sync, staff mappings, pay item account code, and payroll calendar,
but it must also account for verified local bucket mappings and active managed
pay item requirements.

Relevant detailed plan: `plans/63-xero-timesheet-submission.md`.

## Acceptance Criteria

- Admin Xero readiness shows actionable counts for incomplete staff mappings,
  local bucket mappings, managed pay item requirements, account code, payroll
  calendar, and latest sync.
- Active pay item requirements must be `matched` or `created` before the venue
  is considered timesheet-ready.
- Verified earnings-rate mappings must exist for the local buckets that can be
  included in the selected payroll period.
- The same blocker shape can be reused by the future preview and submission
  pages.
