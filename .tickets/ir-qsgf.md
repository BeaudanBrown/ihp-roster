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

Cover application prepare states, decision application, explicit selected periods, posted pay-run blockers, existing-timesheet blockers, pay-item approval, manual staff dropdown mapping, not-paid persistence, run-scoped skip, and at least one HTMX modal path. Reuse strict Xero mock instead of ad hoc stubs.

## Acceptance Criteria

Focused Xero Hspec passes and an E2E spec exercises the modal resolution path from panel launch through preview readiness. Mobile/dialog fit is covered when modal layout changes are substantial.

