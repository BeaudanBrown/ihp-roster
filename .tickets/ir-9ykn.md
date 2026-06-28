---
id: ir-9ykn
status: in_progress
deps: []
links: []
created: 2026-06-28T12:23:42Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-r3wv
tags: [agent-loop, frontend, dev]
---
# Add hot frontend contract generation to dev lifecycle

Add a contract watcher with atomic writes and manage it alongside frontend-watch.

## Acceptance Criteria

dev-start starts frontend-contracts-watch; dev-status/dev-stop report/manage it; frontend-contracts and frontend-contracts-check keep public behavior; frontend-check passes.


## Notes

**2026-06-28T12:31:24Z**

Implemented frontend-contracts-watch, atomic frontend-contracts writes, and dev lifecycle watcher management. frontend-contracts/frontend-check currently blocked by pre-existing missing OpenTelemetry Haskell modules in Application/Helper/Telemetry.hs; frontend TS tests, tsc, drift-check, and script syntax checks pass.
