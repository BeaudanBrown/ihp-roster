---
id: ir-qd8e
status: in_progress
deps: [ir-ix0n, ir-lxkv]
links: []
created: 2026-05-15T02:27:13Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:tests, area:architecture]
---
# Add reusable live surface contract tests

Create a test harness every live surface can use to prove its config, fragments, routes, authorization, and mounted DOM agree.

## Design

Given a surface fixture, verify config JSON round-trips, default fragment refs are stable, fragment endpoints render the declared target id, unauthorized users are rejected, and the full page mounts the expected surface metadata. Keep browser tests only for behavior that needs a browser.

## Acceptance Criteria

At least two migrated surfaces use the harness, including one projection-backed surface and one simple surface; the harness catches target-id or authorization drift without requiring Playwright.


## Notes

**2026-05-15T02:43:30Z**

Added reusable live surface contract assertions and support coverage. Remaining before close: apply the helper to a migrated projection-backed surface after the leave/timesheet migration.
