# Type-Level FrontendSurface Contracts

Status: active

Tickets:

- Epic: `ir-9ogo` - Type-level FrontendSurface contract generator
- `ir-ennr` - Build type-level FrontendSurface lab
- `ir-4hu6` - Prove typed SurfaceImpl completeness
- `ir-xopg` - Generate surface TypeScript and DTO contracts from GHC API
- `ir-8w6w` - Define and enforce FrontendSurface naming policy
- `ir-aleo` - Migrate Timesheets to FrontendSurface spec
- `ir-ypt5` - Migrate Roster to FrontendSurface spec

## Intent

Replace the current frontend contract pipeline with a smaller, surface-centered
architecture where all static Haskell-to-TypeScript protocol facts are declared
as fully type-level `FrontendSurface` specs. The app is rendered as static page
skeletons containing mounted surfaces. A surface is any server-declared frontend
behavior boundary: it may render visible UI, handle HTMX actions, emit typed data
payloads, participate in live updates, manage interaction sessions, or simply
provide a typed browser contract.

The source of truth becomes a closed type-level registry:

```haskell
type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     ]
```

The GHC API generator extracts that registry, normalizes helper aliases/type
families to a primitive normal form, validates references, and emits generated
TypeScript/JSON contracts. Runtime Haskell implementations supply only dynamic
behavior such as URLs, authorization, rendering, versions, actions, and concrete
scope values.

## Core Decisions

- Specs are fully type-level. Do not infer contracts from arbitrary Haskell
  value expressions.
- The canonical DSL syntax is a flat top-level normal form:

  ```haskell
  Surface SurfaceMarker '[ primitive, primitive, primitive ]
  ```

  Individual primitives may have nested option lists.
- Use marker types and global naming conventions instead of raw strings where
  possible.
- `RegisteredFrontendSurfaces` is the exported contract boundary. A later GHC
  API scan may verify that no surface spec was forgotten, but generation starts
  from this explicit registry.
- Helpers such as `DragAndDrop` are sugar only. They expand to primitive normal
  form before extraction and do not change the core architecture.
- `SurfaceImpl spec` provides the runtime bridge and should prove required
  handlers are present through typed builders/handler records.
- DTOs should be generated from the type-level DSL and GHC API extraction rather
  than maintained through separate author-facing `FrontendCodec` instances.
- The generated output does not need to preserve current TypeScript names or wire
  shapes. Prefer the clean shape that best fits the new architecture.
- The first implementation target is a surface laboratory page that covers every
  primitive and uses none of the old frontend contract machinery.

## Primitive Normal Form

The GHC API extractor should only need to understand these primitives after
normalization:

```haskell
Surface name capabilities
Scope name fields
Fragment name paramsAndOptions
HtmxAction name fieldsAndOptions
Intent name fieldsAndOptions
Field name type
OptionalField name type
Session name
DisposableLayer name
InteractionEffect kind fields
ConflictPolicy sessionSelector fragmentSelector resolution
LoadPolicy kind
OverlayLane name
ClientEvent name detail
DomToken name
Dto name fields
```

### Primitive Responsibilities

- `Surface` defines a self-contained frontend behavior boundary and contributes
  a surface-family name.
- `Scope` defines the runtime identity shape for mounted instances.
- `Fragment` defines a renderable/replaceable UI unit and its parameter shape.
- `HtmxAction` defines raw HTMX action metadata and submitted fields.
- `Intent` defines a semantic server-owned action, usually backed by HTMX.
- `Field` and `OptionalField` define JSON/parameter fields.
- `Session` defines a temporary frontend activity, such as drag or resize.
- `DisposableLayer` defines client-owned temporary UI layers.
- `InteractionEffect` defines generic runtime effects during a session.
- `ConflictPolicy` defines how active sessions and server updates interact.
- `LoadPolicy` defines eager/lazy fragment loading behavior.
- `OverlayLane` defines overlay destinations such as dialog, picker, or toast.
- `ClientEvent` defines typed browser event contracts and optional details.
- `DomToken` defines generated DOM protocol attributes/tokens.
- `Dto` defines named JSON payload/config/event-detail shapes not already
  inferred from another primitive.

A flat top-level capability list is only syntax. The normalized graph still
validates cross references, such as actions targeting fragments, effects using
layers, policies referencing sessions/fragments, and intents being backed by
known actions.

## Naming Policy

Use marker type names and derive protocol strings globally:

- surface, scope, and fragment names: lower snake case;
- intent, action, session, and layer names: lower kebab case;
- JSON field names: lower camel case;
- DOM attributes: `data-bepis-` plus lower kebab case;
- event names: namespace plus lower kebab case.

Example marker types:

```haskell
data Timesheets
data TimesheetWeek
data TimesheetDaySection
data WeekOffset
data MoveRosterShiftToSlot
```

Representative derived names:

```text
Timesheets              -> timesheets
TimesheetWeek           -> timesheet_week
TimesheetDaySection     -> timesheet_day_section
WeekOffset              -> weekOffset
MoveRosterShiftToSlot   -> move-roster-shift-to-slot
```

An exact-name escape hatch may exist for legacy or external protocols, but it
should be rare and not part of normal app-owned surface authoring.

## Runtime Bridge

The type-level spec declares what exists. Runtime implementation supplies how it
works for a concrete mounted instance:

- URL builders for fragments/actions;
- fragment renderers;
- authorization checks;
- projection/version functions;
- action/mutation handlers;
- concrete scope and mount values.

A page should inject a surface by mounting an implementation and scope into a
container:

```haskell
renderSurface @TimesheetsSurface timesheetsImpl timesheetScope
```

Nested surfaces are allowed at render time. A parent surface can render a child
surface mount inside its HTML. Spec-level child dependencies are deferred until a
real need appears.

## TypeScript And JSON Generation

The GHC API generator reads `RegisteredFrontendSurfaces`, expands helper aliases
to primitive normal form, validates the closure, builds an internal contract IR,
and renders TypeScript. Generated output should include, as required by reachable
primitives:

- surface-family unions;
- scope DTO unions;
- fragment-key DTO unions;
- intent/action/session/layer/field closed vocabularies;
- DTO type declarations;
- runtime guards, `parseX`, and `encodeX` helpers;
- DOM/event constants;
- manifests/config constants;
- JSON parser/encoder support paths on the Haskell side through type-level
  reflection initially.

Current author-facing `FrontendCodec` instances and manual schema-group
registries should be removed for migrated surfaces once the new generator proves
replacement coverage.

## Surface Lab Acceptance

The first slice must add a dummy/test surface page using every primitive:

- at least one scope;
- eager and lazy fragments;
- required and optional fields;
- HTMX action;
- semantic intent;
- client event;
- DOM token;
- overlay lane;
- interaction session;
- disposable layer;
- interaction effect;
- conflict policy;
- explicit DTO payload.

The lab must not use the old frontend contract machinery. It exists to prove the
DSL, GHC API extraction, generated TypeScript, Haskell runtime bridge, mounting,
and primitive closure semantics before migrating production pages.

## Migration Plan

1. Build the surface lab and generator foundation.
2. Prove typed `SurfaceImpl spec` completeness for required handlers.
3. Generate TypeScript/DTO contracts from the GHC API registry.
4. Migrate Timesheets as the first real surface.
5. Migrate Roster as the complex proof: live fragments, lazy loading,
   interactions, drag/drop helper expansion, disposable layers, effects, and
   conflict policies.
6. Delete old contract-generation paths as each migrated surface no longer needs
   them, with final removal only after Roster proves replacement coverage.

## Living Docs To Update As Work Lands

- `Application/Helper/Frontend/README.md` - replace codec-first authoring rules
  with type-level surface authoring rules when implemented.
- `Application/Helper/LiveUpdate.SPEC.md` - update live-fragment/surface contract
  source-of-truth rules.
- `Application/Helper/Interaction.SPEC.md` - update interaction intent/layer
  source-of-truth rules.
- `Application/Helper/LiveSurface.COOKBOOK.md` - replace current surface-adding
  workflow with `FrontendSurface` specs and `SurfaceImpl` mounting.
- `frontend/AGENTS.md` and `static/AGENTS.md` - update generated contract and
  frontend runtime consumption rules.

## Deferred Questions

These are intentionally deferred until the lab proves the core:

- external/browser-native protocols such as WebAuthn;
- full test matrix and CI gate composition;
- spec-level child-surface dependencies beyond render-time nesting;
- generated Haskell source vs type-level reflection if runtime ergonomics demand
  stronger generated ADTs later.
