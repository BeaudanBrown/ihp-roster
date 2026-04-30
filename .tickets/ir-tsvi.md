---
id: ir-tsvi
status: open
deps: [ir-1urs]
links: []
created: 2026-04-30T03:05:46Z
type: task
priority: 1
assignee: beaudan
parent: ir-ujwc
---
# Implement Xero draft timesheet submission service

Implement the service for ir-ujwc: rerun readiness, run remote duplicate detection, create/update xero_submission_runs and xero_timesheet_submissions, generate durable idempotency keys, call Xero createTimesheet with singleton array bodies, persist request/response JSON, Xero TimesheetID/status, source entry links, attempt counts, errors, submitted/completed timestamps, and per-employee partial failures. Do not implement update/correction support.

