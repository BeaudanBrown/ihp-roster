---
id: ir-bio0
status: open
deps: [ir-5gtw]
links: []
created: 2026-05-29T00:51:31Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, docs, verification]
---
# CSS overhaul final verification and documentation closeout

Reconcile documentation with the implemented CSS architecture, record final verification, and close the refactor loop.

## Design

Update static/css/README.md, static/AGENTS.md, Web/View/AGENTS.md, and any local feature docs impacted by actual class/module names. Summarize final file map, shared primitives, palette/token ownership, and examples for where to add future roster/timesheet/leave/admin styles. Add tk notes with final CSS line counts and any known follow-up tickets. Run the agreed verification sweep.

## Acceptance Criteria

Docs match the implemented files and class names. No large stale plan remains as the only source of truth. Final app-owned CSS line counts are recorded. Verification sweep is run or attempted with notes: bash ./bin/in-env ./bin/style-audit, bash ./bin/in-env typecheck, bash ./bin/in-env e2e e2e/styling-regression.spec.ts, bash ./bin/in-env e2e e2e/roster-mobile.spec.ts, bash ./bin/in-env e2e e2e/mobile-experience.spec.ts. Epic acceptance is reviewed and remaining follow-up tickets, if any, are linked.

