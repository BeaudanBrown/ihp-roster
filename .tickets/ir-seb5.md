---
id: ir-seb5
status: open
deps: [ir-gvfb, ir-7zq6, ir-4vza]
links: []
created: 2026-07-10T05:30:28Z
type: task
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:test, area:docs, area:staff, area:leave]
---
# Add regression coverage and docs for surface-owned mutation responses

Add durable tests and docs for the staff/unavailability mutation response pattern so future changes do not regress to loose HTMX swaps or business OOB success fragments.

## Design

Add/adjust Hspec for valid generated swap values, staff modal StaffSurface mount/config, actor-local invalidation success responses, validation-local responses, and no business OOB on migrated success paths. Add E2E coverage for roster quick-view unavailability reset, staff modal unavailability submit, staff modal profile save, and staff modal preferences save. Update local docs with the generalized pattern and the rule that future staff modal work must happen inside StaffSurface.

## Acceptance Criteria

Tests cover the originally reported regressions. Docs explain 'success invalidates; validation rerenders' and make StaffSurface modal ownership explicit. Ticket notes list the focused verification commands used.

