---
id: ir-qbmu
status: open
deps: []
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, css, style-audit, roster]
---
# Fix roster timeline CSS style-audit hard failure

Remove the raw color-like fallback reported by style-audit in static/css/features/roster/timeline.css.

## Design

Replace or remove the rgba fallback in the roster timeline box-shadow declaration. Prefer an existing token or remove the fallback if --app-shadow-sm is guaranteed. Do not broaden CSS architecture.

## Acceptance Criteria

bash ./bin/in-env ./bin/style-audit passes with no hard failures and no new raw color/style audit violations.

