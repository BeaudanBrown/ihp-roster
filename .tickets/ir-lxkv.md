---
id: ir-lxkv
status: open
deps: [ir-ix0n]
links: []
created: 2026-05-15T02:27:04Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:auth, area:architecture]
---
# Move live authorization into surface contracts

Make websocket subscription authorization and HTTP fragment authorization call the same surface-owned rule instead of parallel hand-written checks.

## Design

Represent each surface authorization requirement in the typed surface definition. Add helpers for fragment controller actions that validate the surface key and viewer before rendering. Keep current venue, roster-group, admin, profile, and support semantics unchanged.

## Acceptance Criteria

A migrated surface has one declared authorization rule used by both subscription handling and fragment GET rendering; unauthorized fragment requests are covered by focused Hspec; no restricted HTML can be fetched only because a fragment URL is known.

