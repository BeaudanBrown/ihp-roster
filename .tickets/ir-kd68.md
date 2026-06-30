---
id: ir-kd68
status: closed
deps: []
links: []
created: 2026-06-30T09:54:22Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-si7h
tags: [architecture, bepis-actions, agent-loop]
---
# Design and implement Bepis mutation pipeline core

Introduce a composable mutation pipeline model matching live-surface descriptor ergonomics.

## Design

Add a small BepisMutation type with phantom capability states or evidence fields. Pipeline components should cover scope, audit, realtime/live resources, and response. Avoid a broad custom framework; keep it as IO-friendly app-owned composition inside IHP actions.

## Acceptance Criteria

Core types compile, are documented, and can represent no-op, current-user, current-venue, audited, realtime, and response-producing mutations without parallel BepisMutationSpec metadata.

