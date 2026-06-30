---
id: ir-m1tm
status: closed
deps: []
links: []
created: 2026-06-30T07:48:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-flq7
tags: [architecture, bepis-actions, agent-loop]
---
# Tighten Bepis response and convention checks


## Notes

**2026-06-30T07:52:55Z**

Convention query now treats response intent from typed Bepis action wrapper contracts as the golden-path response metadata instead of warning on direct IHP helper calls inside wrapped actions. Strict conventions now report 175/175 typed response-metadata handlers, zero convention rows, and zero errors. Optional requireExplicitResponseWrappers remains available for actions that need extra response-level spans.
