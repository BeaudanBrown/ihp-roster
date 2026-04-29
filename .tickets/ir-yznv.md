---
id: ir-yznv
status: open
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

Phase 3 from plans/62-live-fragment-system-refactor.md: merge same-scope surfaces, introduce app-live-fragments-refresh, make focus-protection flushing policy-driven, add reconnect backoff, and emit useful debug/performance events.

## Acceptance Criteria

Same-scope surfaces merge fragments/request decorators/owners; generic actor refresh event works while the roster alias remains; protected fragments flush without roster-specific selectors; reconnect retries use jittered backoff; diagnostics cover subscription/resync/dedupe/defer events.

