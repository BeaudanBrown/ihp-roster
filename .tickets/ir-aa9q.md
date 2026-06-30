---
id: ir-aa9q
status: closed
deps: [ir-orax]
links: []
created: 2026-06-30T04:48:17Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-zqp3
tags: [spike, ihp, realtime, live-updates]
---
# Spike IHP Auto Refresh table tracking reuse for Bepis live surfaces

Investigate whether IHP Auto Refresh internals can reduce Bepis live-surface dependency duplication.

## Design

Review IHP.AutoRefresh, withTableReadTracker, trackTableRead, PGListener notification triggers, and public/stable API boundaries. Prototype or document whether Bepis live fragments can use IHP table-read tracking to infer broad table dependencies while retaining Bepis domain scopes and authorized fragment refetch. Do not adopt IHP document.body morphing for complex roster surfaces without explicit decision.

## Acceptance Criteria

A short ADR/workstream note states what can be reused, what should not be reused, and why. If feasible, a tiny prototype or pseudocode shows bepisLiveFragment/trackedLiveFragment collecting table dependencies. If not feasible, reasons are documented.

