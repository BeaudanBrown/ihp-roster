---
id: ir-99gy
status: closed
deps: [ir-xkxz]
links: []
created: 2026-06-25T11:57:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, interaction]
---
# Split static interaction schema from runtime capability

Refactor interaction capability so shared static concepts can be generated without requiring a concrete scope, while runtime rendering still owns mount-specific URLs and targets.

## Design

Introduce a static interaction schema for surface interaction concepts: disposable layer names, session kind names, intent names, intent field schemas, marker semantics, and conflict policy defaults. Keep or adapt the existing scope -> InteractionCapability path for runtime form actions, HTMX targets, fragment refs, sync selectors, and other request-specific values. Update roster drag/drop to use the split model with no behavior regression.

## Acceptance Criteria

All interaction layers/sessions/intents/fields for roster are enumerable without a fake scope; runtime helpers still render valid scoped forms and fragment targets; roster drag/drop markup and controller tests continue to pass; docs/comments explain static schema versus runtime mount instance.


## Notes

**2026-06-25T13:15:15Z**

Split interaction contracts into scope-free static schema and scoped runtime capability. Added InteractionStaticSchema and InteractionIntentSchema for server layers, disposable layers, session kinds, intent names/fields, and conflict policy without constructing a scope; TypedLiveSurfaceDefinition now carries typedSurfaceInteractionSchema separately from typedSurfaceInteraction. Roster exposes rosterInteractionStaticSchema and builds runtime HTMX forms from the mounted scope while reusing the static schema for layers/sessions/conflicts. Rendering now reads static schema for mount layers/conflicts and runtime capability for scoped forms/targets. Added InteractionSpec coverage for static test and roster schemas being enumerable without fake scope, and documented the static-vs-runtime split. Verified typecheck, frontend-contracts-check, frontend-check, focused Interaction Hspec, and focused roster interaction controller examples. Note: full RosterWeeksController focused run still hits the existing expectation for hx-swap="none settle:0ms" in the layout preference test; it is unrelated to this split and the targeted roster interaction examples pass.
