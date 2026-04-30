---
id: ir-tp2e
status: open
deps: [ir-shsr]
links: []
created: 2026-04-30T00:09:34Z
type: feature
priority: 1
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, schema]
---
# Add Xero timesheet submission persistence

Add dedicated Xero submission tables instead of using export_jobs for external side effects. Persist submission runs, per-employee timesheet submissions, source timesheet entry links, generated request payloads, Xero response payloads, idempotency keys, Xero TimesheetID, status, actor, period, retry/error state, and audit metadata.

## Design

Follow the local submission state section in
`plans/63-xero-timesheet-submission.md`.

Expected tables:

- `xero_submission_runs`
- `xero_timesheet_submissions`
- `xero_timesheet_submission_entries`

Keep request and response payload JSONB. Store source `timesheet_entry_id`
links separately so source edits can mark submitted runs stale.

## Acceptance Criteria

- Schema includes dedicated Xero submission/run/source-entry state.
- Generated types include the new tables.
- Status values are constrained enough for IHP schema parsing.
- There is a unique guard against duplicate active local submissions for the
  same connection, employee, and pay period.
- Tests cover schema shape and deletion/retention expectations.
