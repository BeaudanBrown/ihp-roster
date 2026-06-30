---
id: ir-3uct
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
# Add architecture gate test coverage


## Notes

**2026-06-30T07:59:10Z**

Added scripts/architecture/gate.mjs as a deterministic golden-path gate over generated facts. It checks every controller has Bepis policy, every handler has typed wrapper metadata, wrappers are in the typed contract registry, every handler has typed response metadata, and mutation wrappers reference known BepisMutationSpec values. architecture-check-fresh now runs this gate plus strict conventions. node --check and check-fresh passed.
