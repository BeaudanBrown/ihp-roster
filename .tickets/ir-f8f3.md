---
id: ir-f8f3
status: closed
deps: []
links: []
created: 2026-05-29T00:50:41Z
type: feature
priority: 2
assignee: beaudan
tags: [area:xero, area:payroll, ui]
---
# Split Xero timesheet submission into wizard modal

Break Xero draft-timesheet preparation into forward-only staff, pay item approval, summary, and final submission steps with loading/failure UX.

## Design

Use the existing preparation run/read model and derive the step from unresolved decisions/proposed pay items/preview state. Actual Xero pay item and timesheet requests happen only during final submission. Remove stale skip-this-time references.

## Acceptance Criteria

Owner/super-admin can complete a forward-only modal: resolve staff, approve pay items/account code, review employee-level summary, submit with in-modal loading; success closes modal and shows toast; failures stay open with details; skip-this-time references removed; focused Xero checks pass.


## Notes

**2026-05-29T00:51:29Z**

Decided against run-scoped skip-this-time support; removed living workstream reference and will avoid reintroducing it in the wizard.

**2026-05-29T01:01:41Z**

Implemented forward-only Xero preparation wizard: staff step, pay-item approval/account-code step, summary/confirmation step, in-modal submitting spinner, success toast with dialog close, failure dialog, stale skip references removed. Verified typecheck, focused Xero Hspec, and xero-timesheet-preparation E2E.
