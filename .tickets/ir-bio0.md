---
id: ir-bio0
status: closed
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


## Notes

**2026-05-29T02:28:13Z**

Final docs reconciled with implemented CSS architecture in static/css/README.md, static/AGENTS.md, and Web/View/AGENTS.md. Current app-owned CSS inventory: 4,162 lines across 41 files; largest files are timesheets.css 358, roster/staff-panel.css 295, layout.css 279, roster/week-overview.css 250, roster/shift-card.css 229; no app-owned file exceeds the 1,000-line budget. css-inventory reports raw colours outside token/palette/bridge: none; Layout/Makefile sync: clean; remaining global-selector/stale lists are warning-only, with app-week-toolbar-roster/timesheets generated dynamically by Application.Helper.View.WeekToolbar. Final verification: bash ./bin/in-env ./bin/style-audit passed; bash ./bin/in-env typecheck passed; bash ./bin/in-env ./bin/css-inventory passed; bash ./bin/in-env e2e e2e/styling-regression.spec.ts passed (7/7); bash ./bin/in-env e2e e2e/roster-mobile.spec.ts passed (27/27); bash ./bin/in-env e2e e2e/mobile-experience.spec.ts passed (24/24). Epic acceptance reviewed: roster/component CSS decomposed, palette centralized, horizontal/dense/action primitives documented and used, stale CSS pruned, and style-audit guardrails enforce the architecture. No new follow-up ticket is required for this epic.
