---
id: ir-h5nr
status: open
deps: [ir-zsrm]
links: []
created: 2026-07-03T06:55:44Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, cleanup, live-updates]
---
# Remove temporary resource bridge and custom hooks

Mandatory cleanup of temporary resource bridge, legacy-only resource constructors, and any custom dependency hooks introduced during implementation.

## Design

After all current resources/fragments are generated-backed, migrate mutation code to generated typed touchResource helpers and delete temporary bridge/custom-hook paths. If a dependency cannot be represented declaratively, stop and ask for clarification instead of preserving a final custom dependency.

## Acceptance Criteria

No temporary bridge markers remain. No CustomDependency/custom dependency hook remains. No legacy-only current live resource constructors remain. Old registry/planner compatibility paths are deleted. Guardrail scans prove bridge/custom code cannot silently return.

