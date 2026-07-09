---
id: ir-x3ce
status: open
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

