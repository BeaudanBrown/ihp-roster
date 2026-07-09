---
id: ir-x3ce
status: closed
deps: [ir-126q]
links: []
created: 2026-07-09T01:05:26Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, verification]
---
# Final parameterized FrontendSurface migration sweep

Verify epic completion means all applicable registered surfaces are migrated.

## Design

Re-run the inventory from the first ticket. Confirm every registered surface fragment family is migrated, intentionally non-applicable with rationale, or represented by a new user-approved child ticket created after a pause/ask decision. Run final verification and add a closeout note to the epic before closing.

## Acceptance Criteria

No applicable surface remains unmigrated without explicit user-approved follow-up. Epic acceptance criteria are satisfied. Final typecheck, Hspec/frontend checks, and any focused E2E checks pass. Worktree is clean after final implementation commit.


## Notes

**2026-07-09T01:55:32Z**

Final sweep completed. Re-ran the original inventory with clarified applicability:
- Migrated applicable homogeneous repeated fragments: leave section count/list, timesheet day sections, roster day sections, roster rows, SurfaceLab panels.
- Non-applicable with rationale: Profile/Staff sections, Admin Xero tabs, Admin list-management surfaces, Support panels, Billing single fragment, Admin container/static fragments.
- Fixed final verification drift found by full Hspec: updated GHC raw fixtures for current timesheets/roster action/fragment/dom-token shapes; updated LiveUpdate tests to use valid parameterized leave section fragment keys; aligned Admin Venue Settings mounted fragment key with the reflected contract fragment kind; allowed AppShell runtime as contract infrastructure in guardrails.

Verification:
- bash ./bin/in-env typecheck
- bash ./bin/in-env hspec-test
- bash ./bin/in-env frontend-check
- bash ./bin/in-env ./bin/doc-drift-check (run in cleanup ticket)
