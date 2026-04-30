---
id: ir-1urs
status: closed
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


## Notes

**2026-04-30T03:24:38Z**

Started persistence slice; persistence helper and coverage were implemented alongside preview tests and now need final verification.

**2026-04-30T03:25:07Z**

Persisted preview runs through createPersistedXeroTimesheetPreview: stores preview_payload_json, readiness_snapshot_json, and xero_duplicate_check_json on xero_submission_runs without POSTing to Xero. Verified with typecheck and hspec-test --match Xero --match Schema.
