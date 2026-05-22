---
id: ir-it5h
status: open
deps: []
links: []
created: 2026-05-22T06:01:53Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [agent-loop, area:live-fragments, area:roster, area:architecture]
---
# Harden live fragment containment and roster panel boundaries

Make live-fragment refresh batches non-overlapping by construction, fix the roster staff-panel role flicker, and split roster main content from side panels so future fragment decomposition has a simple repeatable contract.

## Design

Extend the existing TypedLiveSurfaceDefinition pipeline rather than creating a parallel invalidation system. Keep LiveResource as the semantic data-change vocabulary, typedSurfaceDependsOn as stale-fragment selection, and typedSurfaceFragmentRef as the browser refetch/swap contract. Add server-only containment metadata to surface fragment refs, normalize selected fragments before actor/passive transport, and apply it to roster. Preserve current browser JSON, HTMX routes, authorization rules, and server-rendered HTML source-of-truth.

## Acceptance Criteria

Slot mutations no longer emit overlapping parent/child fragment refresh refs. Manager staff panel roles never flash membership ids/UUIDs. RosterProjectionContent no longer renders the roster staff-panel fragment. Roster main content and staff panel can refresh together as sibling fragments. Existing passive live updates and actor refreshes still use the typed surface pipeline. Focused Hspec and relevant Playwright live-fragment checks pass or any failures are documented as pre-existing.

