---
id: ir-tsvi
status: closed
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


## Notes

**2026-04-30T03:26:14Z**

Started create-only draft timesheet submission after preview builder/persistence commit e312572. Scope: rerun readiness/duplicate checks, create local run/submission rows, singleton POST /Timesheets only, persist request/response/idempotency/source-entry state; no update/correction support.

**2026-04-30T03:30:50Z**

Implemented create-only draft submission service: refreshes Xero access, fetches remote timesheets for duplicate detection, reruns readiness, persists run/submission/source-entry records, generates durable run-scoped idempotency keys, posts singleton /Timesheets array bodies, records response/error state, and blocks duplicate creates. Added strict OpenAPI mock coverage for success persistence and duplicate blocking. Verified with typecheck and hspec-test --match Xero --match Schema.
