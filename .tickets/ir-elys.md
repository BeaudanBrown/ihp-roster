---
id: ir-elys
status: closed
deps: []
links: []
created: 2026-07-07T03:24:11Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [frontend-contracts, frontend-surface, htmx]
---
# Generated FrontendSurface HTMX request contracts and rollout

Make surface-owned HTMX request initiators generated, reusable, auditable, and ready for app-wide migration while preserving the consistent FrontendSurface live-update model.

## Design

Use the existing type-level `Action name fields options` primitive as the semantic anchor, but narrow its responsibility to browser request initiation: action name, submitted fields, standard HTMX request attributes, generated metadata, and explicit custom HTMX escape hatches. Successful business refreshes for migrated `FrontendSurface` mutations must continue to flow through actor-local/passive invalidation (`setActorLiveFragmentsRefresh` plus resource invalidation where applicable), not through authoritative actor business-fragment HTML or OOB swaps.

The DSL/IR owns closed, generated browser-visible action metadata. Haskell runtime handlers own IHP route/path construction and any dynamic field values. TypeScript consumes generated manifests/validators at browser boundaries. `CustomHtmx` is allowed only as an explicit, reasoned, generated/auditable lane for unusual or fast-iteration HTMX not yet covered by core options.

The first production proof slice is Admin Roster Groups: declare its in-surface request actions, render them through reusable helpers, and remove any remaining successful actor business OOB response expectations for that surface. The epic should then leave a concrete inventory and rollout plan for migrating the remaining app HTMX request initiators by surface/category without trying to misclassify response extras, shell/container behavior, lazy fragment loads, or pure view-state GETs as `SurfaceAction`.

## Acceptance Criteria

- Surface action contracts can express standard HTMX request metadata, submitted fields, generated DOM metadata, and explicit `CustomHtmx` entries with reasons.
- Generated TypeScript exposes structured per-surface action manifests and validation/parsing helpers.
- Haskell runtime helpers render declared actions for forms, submit buttons, links, and HTMX-only controls while keeping IHP route construction term-level.
- Admin Roster Groups uses generated/reusable FrontendSurface action helpers for all migrated in-surface request initiators.
- Successful Admin Roster Groups mutations do not return authoritative business fragment HTML/OOB swaps; they use the consistent actor-local refresh/invalidation path, with validation failures and non-authoritative extras remaining explicit exceptions.
- Tests/guardrails prove generated action metadata is active and catch stale handwritten migrated action metadata or undeclared custom HTMX.
- Docs explain the pattern, what does not belong in `SurfaceAction`, and a ticketable app-wide rollout inventory.
- Verification for touched slices passes: `typecheck`, focused Hspec, `frontend-contracts`, `frontend-check`, and `frontend-build` as appropriate.
