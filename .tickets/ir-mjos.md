---
id: ir-mjos
status: open
deps: [ir-omzt, ir-9gkd]
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

Add Application/Xero/Timesheets/Prepare.hs. The orchestrator refreshes/validates connection, triggers reconnect when token refresh requires it, syncs payroll reference data, auto-selects single calendar/account-code options, derives managed pay-item requirements, detects pay items requiring approval/creation, computes staff auto-match proposals, accepts manual staff dropdown choices, applies approved decisions, fetches pay runs/timesheets for the selected period, runs readiness, and creates preview only when clear.

## Acceptance Criteria

Controller actions call a cohesive prepare service rather than duplicating sync/mapping/pay-item logic. The service returns typed modal states such as needs reconnect, preparing, needs approval, blocked, ready for preview, previewed, and failed. Existing separate services remain reusable underneath.

