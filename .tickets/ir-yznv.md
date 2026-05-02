---
id: ir-yznv
status: closed
deps: [ir-t3nk]
links: []
created: 2026-04-29T04:45:39Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5uzu
tags: [area:live-fragments, source:plans-62]
---
# Generalize live-fragment client runtime behavior

Phase 3 from docs/archive/plans/62-live-fragment-system-refactor.md: merge same-scope surfaces, introduce app-live-fragments-refresh, make focus-protection flushing policy-driven, add reconnect backoff, and emit useful debug/performance events.

## Acceptance Criteria

Same-scope surfaces merge fragments/request decorators/owners; generic actor refresh event works while the roster alias remains; protected fragments flush without roster-specific selectors; reconnect retries use jittered backoff; diagnostics cover subscription/resync/dedupe/defer events.


## Notes

**2026-04-29T04:57:58Z**

Implemented generic runtime slice: same-scope surface aggregation, generic app-live-fragments-refresh trigger with roster alias, policy-driven deferred flush on focus/input/change, jittered reconnect backoff, and debug events. Verified with typecheck, RosterWeeks/LiveUpdate Hspec, and live-update adapter E2E.
