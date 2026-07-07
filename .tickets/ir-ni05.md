---
id: ir-ni05
status: closed
deps: []
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, frontend-surface, htmx, design]
---
# Design FrontendSurface action request metadata IR and DSL

Add contract-level request metadata for generated HTMX action manifests without reintroducing actor business-fragment swaps.

## Design

Extend the current Surface `Action` representation so each action can carry submitted fields plus closed request-oriented metadata such as method, trigger, include, push-url, confirm, sync, indicator, select, and swap/target only as request/validation/extras behavior where appropriate. Keep successful business refresh semantics outside the action contract: migrated successful mutations refresh through actor-local/passive invalidation, not authoritative actor response HTML.

Add an explicit `CustomHtmx` option/lane with marker/reason metadata for unusual HTMX attributes not yet covered by core options. Validate action names, field names, option references, target/fragment/dom-token references where used, and undeclared/custom option usage.

## Acceptance Criteria

- Surface contract IR can represent standard HTMX request metadata, submitted fields, and explicit custom HTMX entries with reasons.
- The design distinguishes request initiation from successful business refresh/invalidation.
- Invalid references or undeclared custom HTMX fail validation.
- Existing surfaces compile unchanged or migrate through clear defaults.
- Lab/tests cover representative standard options and at least one custom HTMX fixture.
