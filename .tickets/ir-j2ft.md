---
id: ir-j2ft
status: open
deps: [ir-ni05]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, haskell, htmx]
---
# Add generic Haskell FrontendSurface action route/render helper

Render HTMX attrs from generated surface action metadata plus term-level route instances.

## Design

Add a reusable helper in Application.Helper.FrontendContract.Surface.Runtime. The helper combines typed action metadata from the surface contract with a Haskell route/path instance for fields -> Text. The DSL/IR owns method/target/swap; route instances own pathTo/appendQueryParams. Emit normal hx-* attributes plus generated data-bepis surface action metadata for runtime validation/debugging.

## Acceptance Criteria

A generic helper can render hx-get/post/etc, hx-target, hx-swap, and action metadata for a declared surface action. Route construction is supplied by typed Haskell instances/functions rather than the type-level DSL.

