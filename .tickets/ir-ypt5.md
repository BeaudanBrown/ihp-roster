---
id: ir-ypt5
status: in_progress
deps: [ir-aleo, ir-pixx]
links: []
created: 2026-07-02T02:47:03Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, roster]
---
# Migrate Roster to FrontendSurface spec

Migrate the complex roster surface after Timesheets, proving the new architecture on live fragments, lazy loading, interactions, drag/drop helper expansion, disposable layers, effects, conflict policies, and duplicate mounts.

## Design

- Model roster scope as reusable shared scope included by the Roster surface:

  ```haskell
  Scope RosterWeek '[ Field VenueId WireUUID, Field RosterGroupId WireUUID, Field WeekOffset WireInt ]
  ```

- Represent roster fragments in type-level specs, including parameterized fragment shapes without sample IDs:
  - `RosterContent`
  - `RosterGridToolbar`
  - `RosterGridFrame`
  - `RosterDayColumns`
  - `RosterDayRail`
  - `RosterWageRail`
  - `RosterSlotsGrid`
  - `RosterStaffPanel`
  - `RosterDaySection '[ Field RosterDayId WireUUID ]`
  - `RosterRow '[ Field RosterDayId WireUUID, Field RowIndex WireInt ]`
- Represent containment with typed fragment relationships instead of raw target-id paths, e.g. content contains grid frame, grid frame contains day sections/rows, day section contains rows. Runtime maps concrete params to concrete target ids.
- Declare lazy staff panel as a fragment option with typed lazy policy. Preserve useful semantics (lazy trigger, placeholder kind, transition, accessible label) but old internal protocol shape may change.
- Use drag/drop helper sugar after lab proves helper expansion. Helper must normalize into primitives: session, disposable layer, effects, intent/action fields, and conflict policies.
- Solve fragment-specific conflict policies before closing Roster. V1 policies should support `AnyFragment`, fragment kind selectors, and fragment subtree selectors; concrete param predicates may wait unless Roster proves they are necessary.
- Role-dependent visibility, authorization, direct DB/read-model fetching, version/freshness, and rendering live in `SurfaceImpl`.
- Do not use `Application.Helper.SurfaceProjection`; local read-model helpers are allowed as ordinary feature code.
- Duplicate mounts must be safe. Mount key is required; all generated ids/forms/layers/fragments are mount-local and TypeScript resolves from closest surface mount. Stable semantic classes/data/test attrs should replace CSS or tests that depend on exact global ids.

## Acceptance Criteria

- Roster generated contracts and runtime mount come from the new `FrontendSurface` architecture.
- Roster direct `SurfaceImpl` handlers cover fragments, URLs, targets, renders, authorization, version, live-resource dependencies, HTMX actions, layout/move intents, drag session, drag-preview layer, clone-shadow/dropzone-highlight effects, lazy staff panel, and conflict policies.
- Successful Roster actor mutations emit touched resources/surface invalidations; actor HTTP responses carry extras such as toasts/dialog cleanup or validation-local errors. Fragment GET routes use new surface helpers and direct rendering.
- No Roster path uses old `TypedLiveSurfaceDefinition`, `Web.LiveSurfaceRegistry` registration, `FrontendCodec` surface DTO/schema authoring, or `Application.Helper.SurfaceProjection`.
- Tests cover typed containment normalization, parameterized fragments without sample IDs, lazy staff panel, live invalidation, drag/drop intent, fragment-specific conflict policy, and duplicate mounts.

## Notes

**2026-07-02T10:32:11Z**

First Roster FrontendSurface slice landed: added type-level RosterSurface with roster-week scope, live fragments, parameterized day/row fragments, and containment options; registered/generated TS contracts; added Web.RosterWeeks.FrontendSurface SurfaceImpl bridge with mounted fragment metadata, legacy LiveSurfaceConfig adapter, wire-fragment conversion, and resource dependencies; roster shell now emits data-bepis-surface-config side-by-side with legacy data-live-update-surface. Stopped before native interaction modeling/cutover decision point.

**2026-07-02T10:46:44Z**

Interaction DSL slice: added reusable FrontendSurface interaction sugar for drag/drop and layout-mode intents, then composed it into RosterSurface. Roster now declares sessions, disposable layer, effects, htmx actions, intents, and conflict policy through FrontendSurface; SurfaceImpl now exposes typed action/intent metadata for roster layout mode and move-shift intents. Next decision point is how to project FrontendSurface interaction effects/policies into the existing generated TypeScript interaction runtime shape, including whether to add timeout/options to FrontendSurface conflict policies before replacing Roster's old InteractionStaticSchema authoring.

**2026-07-02T10:56:50Z**

Mirrored the existing generated InteractionStaticSchema shape from FrontendSurface Roster contracts: Interaction DTO generation now derives roster sessions/layers/intents/effects/conflict policy from registered FrontendSurface IR instead of Web.RosterWeeks.LiveSurface.rosterInteractionStaticSchema. Roster output remains wire-compatible with existing TS runtime, including clone-shadow/dropzone-highlight effect payloads and 5000ms defer timeout. Next decision point: replace runtime mount/render helpers that still consume old InteractionCapability with FrontendSurface-derived interaction capability/forms, then remove Roster's old interaction schema authoring.

**2026-07-02T11:10:43Z**

Temporary adapter slice landed locally: Roster's legacy InteractionStaticSchema/InteractionCapability are now projected from the Roster FrontendSurface IR and SurfaceImpl intents, preserving the current Application.Helper.Interaction renderer/runtime shape. This intentionally leaves a temporary adapter in Web.RosterWeeks.LiveSurface for mount shell/forms/conflict-policy projection. Follow-up cleanup ticket ir-pixx tracks replacing that adapter with native FrontendSurface interaction render helpers before ir-ypt5 can close.
