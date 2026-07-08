---
id: ir-6oq4
status: open
deps: []
links: []
created: 2026-07-08T00:02:52Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-x6pe
tags: [frontend-contracts, overlay, haskell]
---
# Rename shared HTMX action option IR

Rename the shared action metadata IR currently named SurfaceActionOptionIR to a neutral name such as HtmxActionOptionIR, and update surface actions, overlay actions, TypeScript rendering, adapters, runtime helpers, and tests.

## Design

Keep the OverlayAction lane narrow and non-Xero for this hardening epic. Do not broaden it into arbitrary global HTMX. Preserve Haskell route construction and existing dialog response behavior unless the ticket explicitly migrates a callsite.

## Acceptance Criteria

Focused typecheck/tests pass; affected generated TypeScript is regenerated; docs/guardrails are updated where relevant.

