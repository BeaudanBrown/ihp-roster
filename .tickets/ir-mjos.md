---
id: ir-mjos
status: closed
deps: [ir-omzt, ir-9gkd, ir-szt9]
links: []
created: 2026-05-08T04:22:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, backend]
---
# Implement Xero timesheet preparation orchestrator

Create the application service that drives the one-click/modal preparation flow.

## Design

Add/complete `Application/Xero/Timesheets/Prepare.hs` as the cohesive service for the guided modal. The orchestrator refreshes/validates connection, triggers reconnect when token refresh requires it, syncs payroll reference data when requested/needed, validates the selected period/calendar from the preparation run, derives managed pay-item requirements, detects pay items requiring approval/creation, computes staff auto-match proposals, accepts manual staff dropdown choices, applies approved decisions, fetches pay runs/timesheets for the selected period, runs readiness, and creates preview only when clear.

The orchestrator should implement a single-button guided flow. It auto-runs connection/reference/period/readiness checks, auto-applies safe deterministic defaults where there is no user choice, and pauses only for required user decisions: approve proposed staff matches, choose a manual Xero employee, mark staff not paid through Xero persistently, skip only currently unmapped staff for this run, approve pay item creation/account code where needed, or confirm submission after preview.

Do not auto-select a global payroll calendar. The selected period from the panel/preparation run is authoritative for calendar/window. Xero employee `payrollCalendarId` decides selected-calendar inclusion/exclusion.

## Acceptance Criteria

Controller actions call a cohesive prepare service rather than duplicating sync/mapping/pay-item logic. The service returns typed modal states such as needs reconnect, preparing, needs decision, blocked, ready for preview, previewed, submitted, and failed. It can advance from Prepare to preview with no extra clicks when there are no user decisions, pauses with actionable decision rows when decisions are needed, and never reaches preview while selected-period, staff, pay-item, duplicate, or posted-pay-run blockers remain. Existing separate services remain reusable underneath.

## Notes

**2026-05-19T05:34:22Z**

Implemented typed Xero preparation modal state in the preparation view, backed by status-to-state mapping and focused Hspec coverage. Typecheck passes; focused Hspec compile succeeds but runtime is blocked by missing local postgres socket.
