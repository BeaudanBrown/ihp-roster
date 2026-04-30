---
id: ir-5rhn
status: closed
deps: []
links: [ir-2ds0, ir-caf4, ir-7gm0]
created: 2026-04-30T06:29:18Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:security, area:validation, source:audit-2026-04-30]
---
# Input handling and injection hardening

Coordinate the input-handling security review follow-up from 2026-04-30. Scope covers server-side required-field validation, safe request parsing, CSV/spreadsheet injection prevention, URL encoding, text normalization and length constraints, documentation, and regression tests.

## Design

Use `plans/66-input-handling-and-injection-hardening.md` as the coordination plan. Use IHP form/validation helpers and QueryBuilder as the baseline. Do not introduce ad hoc raw SQL in controllers. Treat HTML required attributes, hidden fields, and select options as client hints only; every user-controllable boundary needs server-side validation or authorization.

## Acceptance Criteria

All audit findings have dedicated tests, documentation is updated, and the app rejects malformed/missing/cross-venue/oversized/suspicious inputs without 500s or unsafe exported content.
