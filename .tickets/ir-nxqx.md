---
id: ir-nxqx
status: open
deps: [ir-ix0n]
links: []
created: 2026-05-15T02:27:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:performance]
---
# Coalesce live invalidations and support batched refetch

Reduce fanout cost when many invalidations or fragments hit the same live surface in a short window.

## Design

Add server-side coalescing by scope and fragment merge key, with a policy for collapsing many small fragments into a larger fragment when the surface defines one. Explore an optional batch refetch endpoint returning OOB fragments for multiple refs on the same surface.

## Acceptance Criteria

Repeated invalidations for the same scope are deduped before broadcast where safe, hot-row bursts can collapse to a day/content fragment by surface policy, and profiling exposes broadcast count, fragment count, coalesced count, and refetch count.

