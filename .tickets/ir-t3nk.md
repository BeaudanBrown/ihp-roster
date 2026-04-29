---
id: ir-t3nk
status: closed
deps: [ir-v7aj]
links: []
created: 2026-04-29T04:45:35Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5uzu
tags: [area:live-fragments, source:plans-62]
---
# Migrate live-update protocol to server scope keys

Phase 2 from plans/62-live-fragment-system-refactor.md: include authoritative server scopeKey in websocket subscribed and invalidated messages, update JavaScript to trust that key, and keep client rebuilding only as a migration fallback.

## Acceptance Criteria

LiveUpdatesSubscribed and LiveUpdatesInvalidated carry scopeKey; the client matches subscriptions by server-emitted scopeKey; fallback remains for legacy/config-only cases; protocol tests cover the round trip.


## Notes

**2026-04-29T04:53:35Z**

Implemented protocol migration: websocket subscribed/invalidate payloads now include authoritative server scopeKey and the client matches messages by scopeKey with buildScopeKey retained as fallback. Verified with typecheck, LiveUpdate Hspec, and live-update adapter E2E.
