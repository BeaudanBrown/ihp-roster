---
id: ir-9ykn
status: open
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

