---
id: ir-8w6w
status: in_progress
deps: []
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces]
---
# Define and enforce FrontendSurface naming policy

Implement global derived naming rules for marker types used in type-level `FrontendSurface` specs. This blocks lab authoring because normal authoring uses marker types rather than raw protocol strings.

## Design

- Derive names from marker type names with robust word splitting and acronym handling:
  - `URLBuilder -> url_builder` / `url-builder` / `urlBuilder` by context, never `u_r_l_builder`.
  - `HTMXAction -> htmx_action` / `htmx-action`.
  - `XeroOAuthCallback -> xero_oauth_callback` / `xero-oauth-callback`.
- Strip suffixes contextually:
  - surface: `Surface`
  - scope: `Scope`
  - fragment: `Fragment`
  - intent: `Intent`
  - action: `Action`
  - session: `Session`
  - layer: `Layer`
  - field: `Field`
- Do not automatically strip feature prefixes initially; repeated names must be intentional and collision-checked.
- Contextual output conventions:
  - surfaces/scopes/fragments: lower kebab for browser protocol, lower snake when an existing wire kind needs snake-style JSON tags;
  - intents/actions/sessions/layers: lower kebab;
  - JSON fields: lower camel;
  - DOM attrs/tokens: `data-bepis-` plus lower kebab where attributes are generated;
  - event names: generated namespace plus lower kebab.
- Exact-name escape hatch is type-level, rare, allowlisted, and visible in extractor diagnostics. Do not use value-level escape hatches.
- Current protocol names may change during migration where cleaner. No compatibility requirement for old internal browser protocol names unless a ticket explicitly requests it.

## Acceptance Criteria

- Focused tests cover acronym handling, suffix stripping, JSON field derivation, DOM/event derivation, collision diagnostics, and exact-name allowlist behavior.
- Lab specs can use marker types for every primitive without raw protocol strings.
- Duplicate generated names fail with clear diagnostics in the relevant namespace.

## Notes

**2026-07-02T05:19:56Z**

Implemented initial FrontendSurface naming policy foundation in Application.Helper.FrontendSurface.Naming with acronym-aware word splitting, contextual suffix stripping, JSON/DOM/event/wire derivation helpers, exact-name allowlist checks, collision diagnostics, and focused Hspec coverage. Existing LiveSurface descriptor default naming now reuses the shared naming helpers.
