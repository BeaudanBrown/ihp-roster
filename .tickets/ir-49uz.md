---
id: ir-49uz
status: closed
deps: [ir-wyet, ir-824k]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 2
assignee: beaudan
parent: ir-bao4
tags: [area:e2e, area:mobile]
---
# Add responsive week-control regression coverage

Add tests/screenshots covering shared week controls and mobile ordering for roster and timesheets.

## Design

Prefer Playwright layout assertions using stable data attributes from the shared helper, plus existing Hspec markup assertions for HTMX URLs and query preservation.

## Acceptance Criteria

E2E verifies desktop one-row behavior is preserved and phone ordering matches roster/timesheet requirements; Hspec verifies canonical week/reset URLs remain encoded and feature filters are preserved.

