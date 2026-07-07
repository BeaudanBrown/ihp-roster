---
id: ir-vw5m
status: open
deps: []
links: []
created: 2026-07-07T03:24:30Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, lazy-loading, frontend-surface, cleanup]
---
# Unify FrontendSurface lazy fragment rendering

Replace the split/stale lazy-loading paths with one FrontendSurface lazy fragment system that is primitive-aligned, uses canonical UI-region attrs, preserves loaded-fragment layout geometry during loading, and is applied consistently to current lazy fragments.

## Design

Use existing FrontendSurface fragment options as the source of truth for lazy/eager defaults. Introduce or evolve a canonical lazy fragment render config that separates root/slot attributes from placeholder chrome. The lazy root must keep the loaded fragment target id, GET URL, HTMX swap behavior, and final layout classes where supplied. Haskell-rendered lazy roots must emit generated UI-region attrs consumed by the generic TypeScript lazy error/retry lifecycle. Retire the unused Application.Helper.View.LazySurface helper after equivalent functionality is folded into the FrontendSurface runtime path. Do not add new core primitives unless implementation proves existing Lazy/Trigger/Placeholder/Eager options cannot express the needed defaults.

## Acceptance Criteria

Roster staff panel placeholder renders in the same right-side slot as the loaded staff panel. Current lazy fragments use one canonical Haskell render helper/config path. Haskell lazy roots emit canonical UI-region attrs, not stale data-bepis-surface-lazy* attrs. Existing Lazy, Trigger, and Placeholder primitive options drive defaults where feasible. No production call sites depend on Application.Helper.View.LazySurface; stale helper is deleted. Guardrails/tests catch stale lazy attrs and old helper reintroduction. Focused frontend/Haskell checks pass or unrelated failures are documented.

