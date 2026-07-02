---
id: ir-uir5
status: open
deps: []
links: [ir-jooi, ir-umv7, ir-xyzw]
created: 2026-05-21T07:00:19Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, area:performance, area:live-fragments, area:architecture]
---
# Evaluate resource-versioned granular read caching

Research and prototype whether projection-backed surfaces should evolve toward typed component-level read caches keyed by explicit inputs plus LiveResource/version dependencies.

## Design

Keep the current projection system intact while evaluating a more granular caching model. The target idea is a typed read-cache helper where cache keys include loader name, tenant-safe typed inputs, and dependency versions derived from LiveResource-style dependencies, with TTL/size limits for cleanup. Reuse touched-resource and depends-on concepts as the dependency language, but do not blindly reuse fragment dependsOn declarations: cache loader dependencies must be data-correct and may be stricter than UI fragment dependencies. Prefer versioned keys over TTL-only or dependency-scanning eviction. Start process-local; Redis/Postgres pub-sub are future deployment options, not part of this first evaluation. Avoid caching rendered HTML and avoid caching authorization/capability decisions unless the viewer identity/scope is explicit. Candidate pilots include venue shift types, venue roster groups, or ordered roster week slot definitions. Complex derived data such as staff option states, conflicts, and wage prediction are analysis targets, not first pilots.

## Acceptance Criteria

The work produces a documented recommendation plus one low-risk prototype or proof that a prototype should not proceed. The recommendation compares current projection snapshots, granular cached loaders, resource-level versions, current live-scope versions, and Redis/Postgres deployment options. Any prototype is typed, tenant-safe, version-invalidated, instrumented enough to compare hit/miss/load behavior, and covered by stale-data regression tests. Current roster/timesheet/leave projection behavior remains unchanged unless a later explicit ticket authorizes decomposition.


## Notes

**2026-07-02T12:45:35Z**

SurfaceProjection has been removed as part of ir-s7la. Keep this epic only as future resource-versioned read-cache research; any prototype must be explicit, feature-owned, viewer-aware, and behind a read-model/SurfaceImpl seam rather than using the old generic surface projection cache.
