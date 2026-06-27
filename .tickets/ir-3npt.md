---
id: ir-3npt
status: closed
deps: [ir-r98d]
links: []
created: 2026-06-27T09:16:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lcpr
tags: [agent-loop, live-surface]
---
# Migrate regular non-projection surfaces to registered descriptors

Move admin Xero, leave requests, profile content, and profile leave requests toward descriptor-shaped registrations where feasible.

## Acceptance Criteria

These surfaces are registered through the canonical abstraction or documented as temporarily allowlisted with blockers; manifest derivation is descriptor-backed where possible.


## Notes

**2026-06-27T09:42:50Z**

Regular non-roster/timesheet surfaces now participate in the registered surface catalog. Manifest coverage for admin Xero, leave requests, profile, and profile leave requests is asserted from typed registrations; previous manual manifest descriptors were removed in the prior catalog chunk. Verification passed: typecheck, frontend-contracts-check, focused Live surface registry Hspec.
