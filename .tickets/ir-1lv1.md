---
id: ir-1lv1
status: closed
deps: [ir-pr5o]
links: []
created: 2026-04-29T05:15:30Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-3asf
tags: [area:live-fragments, source:plans-62]
---
# Add live fragment fanout and profiling hooks

Add performance-oriented hooks for projection-backed live fragments: cache warm/broadcast helpers, active-scope helpers by scope kind, mounted-fragment filtering or instrumentation, and profiling counters where useful.

## Acceptance Criteria

High-churn surfaces have a clear path to avoid over-broadcasting, and profiling can show cache and subscription behavior without changing user-visible flows.


## Notes

**2026-04-29T05:21:15Z**

Implemented broadcast fanout result metrics, active-scope matching helper, and opt-in projection broadcast warming. Mounted-fragment filtering remains a protocol-level follow-up because the server does not yet receive mounted fragment metadata from clients.
