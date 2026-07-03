---
id: ir-aa95
status: open
deps: []
links: []
created: 2026-07-03T06:55:43Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, live-updates, codegen]
---
# Generate FrontendSurface live resources and subscription authorization

Eliminate the remaining hand-written live-update registry, authorization, resource-planning, and mount parsing glue by deriving it from RegisteredFrontendSurfaces.

## Design

RegisteredFrontendSurfaces remains the single root. Surface specs declare scope authorization and explicit live-resource dependencies with Resource, DependsOn, FromScope, FromFragment, Authorize, NoAuth, and ResyncOnly. The GHC API pipeline validates declarations and generates Haskell/TypeScript plumbing. The generated planner enumerates active subscribed scopes, parses generated scope payloads, enumerates candidate mounted fragments, constructs each candidate fragment's concrete dependency resource values from FromScope/FromFragment, intersects with touched generated resources, coalesces/normalizes selected fragments, and broadcasts surface-native invalidations. Dependencies are explicit in V1; no inference, fanout primitive, mount-state predicate DSL, second resource registry, or permanent custom dependency hooks. Temporary bridges/custom hooks are allowed only during implementation and must be removed before epic close.

## Acceptance Criteria

RegisteredFrontendSurfaces is the only live surface/resource root. No separate resource registry exists. No central hard-coded LiveUpdateScope authorization/planning case list remains. Current live resources are represented by type-level Resource declarations discovered from registered surface specs. Current live fragments explicitly declare DependsOn or ResyncOnly. Current mutations emit generated typed resource values rather than legacy-only constructors. Subscription authorization is generated from Scope auth policies and unknown/malformed scopes deny by default. Browser runtime uses generated full mount/subscription config parsers with no app-specific surface-name exceptions. Per-feature wire-fragment string-switch helpers are removed/replaced by generic/generated conversion. No CustomDependency/custom hook remains at epic close. Temporary LiveResource bridge is removed before epic close. Docs and guardrails lock the final model.


## Notes

**2026-07-03T07:54:39Z**

Reordered implementation after ir-ai98 so current resource declarations migrate before replacing the planner: ir-zsrm now precedes ir-4oed, and cleanup waits on the generated planner.
