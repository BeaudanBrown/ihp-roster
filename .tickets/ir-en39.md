---
id: ir-en39
status: closed
deps: []
links: []
created: 2026-06-30T07:26:22Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jm68
tags: [architecture, bepis-actions, agent-loop]
---
# Expand Bepis wrapper API and strict convention gate


## Notes

**2026-06-30T07:29:18Z**

Added wrapper variants for form/preference/json mutation/integration/export actions, current-venue/support/roster-week mutation specs, and a strict conventions mode requiring every controller to declare Bepis policy and every action to use a Bepis wrapper. typecheck and node syntax checks passed; strict gate currently exposes expected rollout violations before controller migration.
