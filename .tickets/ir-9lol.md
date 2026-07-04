---
id: ir-9lol
status: open
deps: [ir-2rnj]
links: []
created: 2026-07-04T04:34:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lnxp
tags: [agent-loop, surfaces, interaction, runtime, cleanup]
---
# Generalize FrontendSurface interaction shell rendering

Move roster's handwritten interaction shell/layer/form/conflict-policy rendering into reusable FrontendSurface runtime helpers and migrate roster to them.

## Design

Add generic helpers in Application.Helper.FrontendSurface.Runtime or a focused submodule to render interaction shell attrs, server layer, disposable layers, intent forms/fields, and conflict policy JSON from SurfaceImpl plus reflected/generated IR. Replace renderRosterFrontendSurfaceInteractionShell and related roster-specific boilerplate with the generic helper in the same ticket. Preserve DOM-owned HTMX forms, mount-local ids, hx-target/swap/sync metadata, generated field presence attrs, and conflict behavior.

## Acceptance Criteria

Roster no longer has feature-local interaction shell/layer/form/policy boilerplate beyond passing feature-specific content/config into generic helpers. Existing roster pointer/activation behavior and tests still pass. New generic helper is documented and covered. typecheck, frontend-check, focused roster Hspec, and roster pointer e2e pass if DOM changed.

