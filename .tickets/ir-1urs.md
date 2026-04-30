---
id: ir-1urs
status: open
deps: [ir-f09l]
links: []
created: 2026-04-30T03:05:46Z
type: task
priority: 1
assignee: beaudan
parent: ir-lgy7
---
# Persist preview runs for Xero timesheet submission

Create the application service that stores preview output in xero_submission_runs.preview_payload_json with readiness_snapshot_json and duplicate-check metadata. It should not call POST /Timesheets and should leave actual submission for ir-ujwc. Reuse the same preview builder output the future submission action will send.

