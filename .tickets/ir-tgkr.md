---
id: ir-tgkr
status: open
deps: [ir-axdb]
links: []
created: 2026-04-30T00:09:48Z
type: task
priority: 1
assignee: beaudan
parent: ir-shsr
tags: [area:xero, area:payroll, readiness]
---
# Tighten Admin Xero readiness checklist

Update the existing Admin Xero readiness checklist so it blocks draft-timesheet readiness unless all active staff/payroll mappings and managed pay item requirements are verified. The checklist should include earnings/pay item mapping readiness, managed pay item account code, payroll calendar selection, successful reference sync, and actionable counts for incomplete items.

## Design

Current code touches:

- `Application.Helper.XeroAdminTypes.XeroReadyChecklist`
- `Web.Controller.Admin.Xero.buildXeroReadyChecklist`
- `Web.View.Admin.Xero.renderXeroReadyChecklist`

Add explicit checklist fields for verified earnings/pay bucket mappings and
active managed pay item requirements. Keep checklist rendering concise, but make
counts visible enough that a manager can tell what remains.

## Acceptance Criteria

- Checklist is false when any active requirement is `proposed`, `stale`,
  `rate_changed`, or otherwise not `matched`/`created`.
- Checklist is false when local bucket mappings needed for Xero submission are
  not verified.
- Existing connection/sync/staff/calendar/account-code checks keep working.
- Hspec coverage proves incomplete pay item requirements and earnings mappings
  block readiness.
