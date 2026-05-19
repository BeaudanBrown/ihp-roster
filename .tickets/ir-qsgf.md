---
id: ir-qsgf
status: open
deps: [ir-lhy5, ir-l0x7, ir-8usq]
links: []
created: 2026-05-08T04:22:46Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, tests]
---
# Cover guided Xero preparation with tests

Add focused Hspec and E2E coverage for the guided Xero preparation modal.

## Design

Cover application prepare states, decision application, explicit selected periods, selected-period calendar authority without `xero_payroll_calendar_selections`, Xero employee `payrollCalendarId` inclusion/exclusion, posted pay-run blockers, existing-timesheet blockers, pay-item approval, manual staff dropdown mapping, persistent not-paid decisions, run-scoped skip only for unmapped staff, and at least one HTMX modal path. Reuse strict Xero mock instead of ad hoc stubs.

## Acceptance Criteria

Focused Xero Hspec passes for backend readiness/orchestrator/preview/submission paths. Tests prove modal preparation can reach preview without global calendar selection, excludes different-calendar employees with warnings, blocks missing employee calendar data, blocks posted pay runs and duplicate remote timesheets, persists not-paid decisions, and rejects skip for already-mapped staff. An E2E spec exercises the single-button modal path from panel launch through decision resolution to preview, with explicit submit confirmation. Mobile/dialog fit is covered when modal layout changes are substantial.
