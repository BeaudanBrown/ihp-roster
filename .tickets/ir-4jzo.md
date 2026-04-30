---
id: ir-4jzo
status: open
deps: [ir-f09l]
links: []
created: 2026-04-30T03:05:46Z
type: task
priority: 1
assignee: beaudan
parent: ir-lgy7
---
# Add Xero timesheet preview tests and fixtures

Add focused Hspec coverage for the preview builder: weekly and fortnightly periods, exact selected payroll-calendar period, one payload per employee/period, grouping by EarningsRateID, zero-filled missing days, source entry ids, pay_config_snapshot_id metadata, and stable JSON shape suitable for POST /Timesheets singleton-array submission.

