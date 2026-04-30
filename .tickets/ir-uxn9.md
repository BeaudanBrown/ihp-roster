---
id: ir-uxn9
status: open
deps: []
links: []
created: 2026-04-30T04:45:48Z
type: feature
priority: 1
assignee: beaudan
parent: ir-ujwc
tags: [area:xero, area:payroll, ui]
---
# Add Xero timesheet preview and submit UI on Xero page

Add the first manager-facing Xero draft-timesheet UI inside the existing Xero admin page. Scope: venue owners only; show the latest preview/submission run only; preview has one row per employee; allow create-only DRAFT submission when readiness passes; show per-employee submission statuses and errors; include a retry affordance for failed rows but do not build full retry workflow polish. No separate page and no historical run list in this slice.

## Acceptance Criteria

The existing Xero page exposes the draft-timesheet preview/submission panel only to venue owners (and support/super-admin only if already allowed through venue-owner-equivalent access). The preview table shows one row per Xero employee with period, total units, line/earnings summary, source-entry count, and readiness/blocker state. The panel uses the selected verified Xero payroll calendar period. Generating preview persists xero_submission_runs.preview_payload_json/readiness_snapshot_json/xero_duplicate_check_json. Submitting calls the existing create-only submission service, does not approve timesheets or create pay runs, and shows latest run/submission status and errors. The UI shows only the latest run for now; no historical list. Focused controller/view tests cover owner visibility, non-owner gating, preview persistence, submit action wiring, and error display.

