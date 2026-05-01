---
id: ir-hm3w
status: closed
deps: [ir-9sqg]
links: []
created: 2026-04-30T23:32:04Z
type: task
priority: 1
assignee: beaudan
parent: ir-sryt
tags: [area:performance, area:profiling]
---
# Make disabled profiling path cheap and production-safe

Reduce overhead and exposure risk when profiling code is included in normal app builds and especially production deployments.

## Design

Cache the profiling-enabled flag or make span helpers check for an active profile before reading clocks/cache stats. Avoid constructing span details when no profile exists. Keep production profiling opt-in, sampled if enabled, and avoid exposing detailed span names/cache facts to untrusted clients unless explicitly requested for diagnostics.

## Acceptance Criteria

With IHP_ROSTER_PROFILING unset, profileActionSpan avoids monotonic clock reads and cache-stat snapshots; production defaults emit no profiling headers; any production-enabled mode has documented sampling/detail controls; focused tests cover enabled and disabled behavior.


## Notes

**2026-04-30T23:58:59Z**

Disabled profiling now has no response headers and span helpers avoid monotonic clock reads when no RequestProfile is active. Production policy documented as default-off/isolated diagnostics only.
