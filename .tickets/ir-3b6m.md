---
id: ir-3b6m
status: closed
deps: []
links: []
created: 2026-07-03T11:15:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, live-updates, codegen]
---
# Remove live update registry adapter with surface-native subscriptions

Replace the remaining LiveUpdateScope/LiveFragmentKey ADT adapter with surface-native FrontendSurface subscription state derived from RegisteredFrontendSurfaces.

## Design

Active websocket subscriptions should store generated FrontendSurface scope payloads, scope keys, and exact mounted live fragments from the browser mount config. Authorization and validation are derived from reflected RegisteredFrontendSurfaces metadata. Invalidation planning iterates active subscriptions directly, evaluates generated DependsOn metadata against mounted fragments, and sends subscriber-local generated wire fragments. No old LiveUpdateScope/LiveFragmentKey constructor case lists, planningInputForScope adapter, or per-feature wire conversion should remain at close.

## Acceptance Criteria

Live update runtime uses surface-native subscription data end-to-end. Browser subscribe commands include mounted live fragments. LiveBus tracks active subscriptions and versions by generated scope key. Authorization/fragment validation/planning derive from FrontendSurface metadata. Producer-side active scope helpers no longer inspect legacy ADT constructors. Legacy LiveUpdateScope/LiveFragmentKey ADTs and registry adapter case lists are removed and guarded. Final verification and closeout note recorded.

