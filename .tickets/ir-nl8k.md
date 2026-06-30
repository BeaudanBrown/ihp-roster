---
id: ir-nl8k
status: closed
deps: [ir-63go, ir-8zip]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [haskell, mutation, realtime, audit]
---
# Add typed Bepis mutation spec and migrate one roster mutation

Introduce typed mutation policy/effect structure and prove it on one roster mutation.

## Design

Define BepisAuditPolicy, BepisRealtimePolicy, BepisScopePolicy, and BepisMutationSpec. Extend bepisMutationAction to require a spec. Migrate one low-risk RosterWeeks mutation, capturing audit/realtime/scope intent. Keep initial implementation thin, but prepare for future MutationResult types that structurally carry audit events and realtime invalidations.

## Acceptance Criteria

One RosterWeeks mutation uses a Bepis mutation spec. Architecture facts show mutatesData/auditPolicy/realtimePolicy/scopePolicy from typed-wrapper/spec source rather than naming. Tests verify the action still behaves correctly.

