---
id: ir-2mlj
status: open
deps: [ir-rs8u]
links: []
created: 2026-05-21T07:00:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-uir5
tags: [agent-loop, area:architecture, area:performance, area:live-fragments]
---
# Design typed resource-versioned read cache API

Design a small typed cache API for granular read loaders using LiveResource-style dependencies and versioned keys.

## Design

Compare three dependency-version sources: existing LiveUpdateScope versions, a mapping from LiveResource to broader scopes, and new resource-level version counters. Define a candidate API shape for cached loaders that takes a typed input, computes tenant-safe cache keys, declares dependency resources, reads dependency versions, loads on miss, and records hit/miss/load/eviction metrics. Specify how multiple dependency versions combine into a key. Specify stampede behavior, TTL/size cleanup, test isolation, Typeable/serialization constraints, and whether values remain process-local. Include explicit rejected alternatives: TTL-only correctness, arbitrary string-key caches, rendered HTML caches, and caching auth decisions without viewer identity.

## Acceptance Criteria

A design note or ticket note describes the API shape, key structure, invalidation/version strategy, dependency declaration rules, metrics, and concurrency/test behavior. It identifies implementation prerequisites and open decisions. It includes examples for fetchCurrentVenueRosterShiftTypes, fetchCurrentVenueRosterGroups, and ordered roster week slot definitions, plus explains why staff option states/conflicts/wage prediction need richer dependency modeling before caching.


## Notes

**2026-07-02T12:45:35Z**

Design should target a fresh resource-versioned read-cache API only. Do not depend on Application.Helper.SurfaceProjection or old projection-cache authoring; those paths were removed in ir-s7la.
