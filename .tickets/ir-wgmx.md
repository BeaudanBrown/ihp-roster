---
id: ir-wgmx
status: closed
deps: [ir-auvz, ir-5m9m, ir-1dhl]
links: []
created: 2026-05-16T01:26:11Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:controllers]
---
# Remove raw feature broadcasts and actor refresh wiring

Replace feature-level raw LiveFragmentRef broadcasts and hand-built actor refresh payloads with typed broadcast and mutation helpers.

## Design

Scan Web/ and feature Application/ modules for broadcastLiveInvalidation, liveFragmentsRefreshTriggerPayload, raw LiveFragmentRef lists, and untyped ref builders. Convert each caller to broadcast typed fragments or perform a typed live-surface mutation. Keep LiveBus raw broadcasts internal.

## Acceptance Criteria

No feature controller/helper broadcasts raw LiveFragmentRef values. Actor HTMX responses and passive invalidations derive from the same typed changed-fragment declaration. Tests cover source-client exclusion, dedupe/coalescing, and actor refresh payloads.


## Notes

**2026-05-16T02:19:41Z**

Removed feature-facing raw broadcasts, raw fragment refs, and hand-built actor refresh payloads from Web/ and feature Application/ modules; guard scan is clean.
