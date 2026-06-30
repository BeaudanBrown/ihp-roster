---
id: ir-si7h
status: open
deps: []
links: []
created: 2026-06-30T09:53:46Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, live-surfaces, agent-loop]
---
# Bepis component pipeline refactor

Move Bepis metadata from parallel descriptive specs toward typed component pipelines and generated contracts for actions, mutations, surfaces, permissions, audit, realtime, and responses.

## Design

Keep IHP as outer framework boundary. Generalize the existing live-surface descriptor pipeline pattern to mutations and related Bepis concepts. Prefer actual typed values/evidence and generated facts over string literals and drift checks. Migrate incrementally behind existing Bepis wrappers and architecture gates.

## Acceptance Criteria

Action names are derived from action values rather than string literals; Bepis contracts are emitted from typed Haskell values; at least one representative mutation uses a typed pipeline that produces scope/audit/realtime/response evidence; architecture facts prefer generated typed contract/evidence artifacts; strict gates continue to pass; durable docs describe the pattern and migration rules.

