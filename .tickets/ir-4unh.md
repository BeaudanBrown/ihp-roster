---
id: ir-4unh
status: closed
deps: [ir-9sqg]
links: []
created: 2026-04-29T04:41:29Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sryt
tags: [area:performance, area:profiling, coordinator:coordinator-b64]
---
# Expose projection-cache metrics for development

Report hit/miss/warm/invalidation facts in a dev-visible way.

## Notes

**2026-04-30T23:58:52Z**

Projection-cache hit/miss/load/warm/eviction deltas are emitted through profiling span detail and verified in profile-app/load artifacts.
