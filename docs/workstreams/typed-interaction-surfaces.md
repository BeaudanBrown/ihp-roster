# Typed Interaction Surfaces

Status: active

Tickets:

- `ir-jsyd` - parent epic
- `ir-4uuy` - document the typed interaction contract
- `ir-fq28` - add Haskell interaction capability types
- `ir-95e7` - generate TypeScript contracts for interaction capabilities
- `ir-w50d` - render typed interaction surfaces, layers, and HTMX intent forms
- `ir-ojl5` - implement the generic TypeScript intent bus/form bridge
- `ir-gyit` - prove a low-risk click/select prototype
- `ir-mlle` - implement pointer/touch disposable session primitives
- `ir-ptnv` - coordinate disposable sessions with live fragments
- `ir-mwrz` - prototype timeline drop intent
- `ir-z2ej` - prototype timeline edge resize intent

Related workstreams and docs:

- `docs/workstreams/live-surface-architecture.md`
- `docs/workstreams/strict-live-surface-overhaul.md`
- `docs/workstreams/live-update-runtime-simplification.md`
- `Application/Helper/Interaction.SPEC.md` (living contract)
- `Application/Helper/LiveUpdate.SPEC.md`
- `Application/Helper/LiveSurface.COOKBOOK.md`
- `frontend/AGENTS.md`
- `static/AGENTS.md`

## Goal

The durable implementation contract now lives in
`Application/Helper/Interaction.SPEC.md`; keep this workstream as the active
planning/ticket index until the stream exits.

Extend the typed live-surface architecture with optional typed interaction
capabilities. Haskell should remain the source of truth for surface families,
scopes, concrete mounts, live fragments, disposable UI layers, intent types,
intent field schemas, HTMX form contracts, and live-fragment conflict policy.
TypeScript should consume generated contracts and provide generic runtime
behavior; it must not invent canonical surface, fragment, layer, or intent
strings.

The target authoring model is:

- feature modules define closed Haskell types for live fragments, disposable
  layers, intents, and intent fields;
- existing `TypedLiveSurfaceDefinition` values remain the base for server-owned
  fragments;
- interaction capability attaches to the same typed surface origin and may be
  empty for non-interactive surfaces;
- Haskell helpers render valid surface mounts, server layers, disposable layers,
  typed item/slot/handle attributes, and HTMX intent forms;
- generated TypeScript contracts describe the browser boundary;
- generic TypeScript runtimes manage disposable sessions, dispatch normalized
  intents, fill generated forms, and coordinate live updates without owning
  business state.

## Vocabulary And Hierarchy

| Level | Term | Source of truth | Meaning |
| ---: | --- | --- | --- |
| 1 | Surface family | Haskell | Reusable UI surface type independent of a page. |
| 2 | Surface scope | Haskell | Authorized logical data slice such as one roster week. |
| 3 | Surface instance / mount | Haskell render helper | One concrete occurrence of a surface on a page; includes a mount key so the same scope can appear more than once. |
| 4 | Server layer | Haskell render helper | Authoritative server-rendered DOM under the mount. |
| 5 | Live fragment type | Haskell | Closed feature-local enum for refreshable server DOM. |
| 6 | Live fragment ref | Haskell | Target id, GET URL, protection policy, and containment path derived from the fragment contract. |
| 7 | Disposable layer type | Haskell | Typed client-owned ephemeral UI region such as drag preview, selection, context menu, or measurement overlay. |
| 8 | Disposable session | TypeScript runtime constrained by generated contracts | Temporary frontend interaction state such as click-select, drag, resize, draw-range, menu, or keyboard command. |
| 9 | Intent type | Haskell | Typed user action that may submit to the server. |
| 10 | Intent field schema | Haskell | Allowed string fields for a committed intent. |
| 11 | Intent form contract | Haskell render helper | HTMX method/route/trigger/target/swap and hidden fields for one intent. |
| 12 | Conflict policy | Haskell, consumed by TypeScript | Whether a live fragment update during an active disposable session may apply, must defer, or cancels the session. |

Conceptual structure:

```text
SurfaceFamily
└── SurfaceScope
    └── SurfaceInstance / Mount
        ├── ServerLayer
        │   └── LiveFragments
        │       ├── FragmentRef
        │       ├── TargetId
        │       ├── RefetchUrl
        │       └── ContainmentPath
        ├── DisposableLayers
        │   └── DisposableSessions
        │       ├── SessionKind
        │       ├── Anchors
        │       └── ConflictPolicy with LiveFragments
        └── IntentForms
            ├── IntentType
            ├── FieldSchema
            ├── HTMX route/method
            ├── HTMX target/swap
            └── Trigger event
```

## Intended Contract

### Haskell-owned contracts

Haskell owns all canonical names and relationships. Feature code should not
handwrite free-text `data-bepis-*` values, intent field names, target ids, or
HTMX intent forms. Instead, typed helpers derive markup from feature-local
closed ADTs and typed contracts.

The first implementation may use a sibling wrapper around
`TypedLiveSurfaceDefinition`, for example a typed interaction capability that
contains disposable layers, intent contracts, and conflict policies. Existing
surfaces should be representable with empty disposable layers, empty intents,
and default non-interactive policy.

### Generated TypeScript

Generated TypeScript should stay narrow and browser-boundary focused:

- surface family/kind values;
- surface scope and mount metadata needed by generic runtime;
- live fragment keys and wire refs already used by live updates;
- disposable layer names;
- session kinds;
- intent names;
- intent field object shapes;
- conflict-policy DTOs.

Do not generate broad database models or make TypeScript authoritative for
business state. `frontend-contracts-check` and `frontend-check` must catch drift.

### Surface portability

A surface family and scope can be moved across pages or mounted multiple times.
A concrete mount key must participate in derived DOM ids, HTMX targets, and form
ids so duplicate mounts do not collide. Intent forms must target within their
own surface instance instead of global hardcoded ids.

### Disposable UI ownership

Disposable UI is not a live fragment and is not authoritative. It may be
created, moved, or cleared by generic TypeScript in a declared disposable layer.
It must be safe to discard on cancel, timeout, HTMX response, live-swap conflict,
or page cleanup.

Examples include drag ghosts, resize previews, selection rectangles, context
menus, command palettes, measurement guides, and drawing previews. Drag/drop is
only one session type; the system should remain general.

### Intent submission

The generic intent bridge submits only committed intents by default. Start and
preview phases are local unless a future typed form explicitly opts in.

On commit, TypeScript finds the matching generated HTMX form inside the same
surface mount, validates that emitted string fields match the generated field
schema/hidden inputs, fills the inputs, and dispatches the form's generated
custom trigger. The bridge must not construct URLs, call `fetch` for
persistence, or mutate business DOM.

Use standard HTMX primitives first:

- generated forms;
- `hx-trigger` with custom events such as `bepis:intent-submit from:this`;
- lifecycle events for cleanup;
- `hx-sync`/`hx-disabled-elt` where useful for request concurrency and disabled
  controls;
- OOB swaps for authoritative actor responses, toasts, and dialog cleanup.

Do not start with HTMX extensions or custom elements. Revisit extensions only
after repeated lifecycle behavior is stable enough to consolidate.

### Live-fragment coordination

Interactive surfaces should prefer a stable outer mount with server-owned live
fragments under a server layer and disposable UI in sibling disposable layers.
Live updates may apply behind active disposable UI when the selected fragment
cannot invalidate the active session.

Conflict policy is typed and conservative at first:

- non-conflicting fragments may apply immediately;
- fragments touching active anchors, active targets, intent forms, disposable
  layer mounts, or the whole surface shell should defer or cancel according to
  policy;
- actor HTMX responses for the committed intent win, clear disposable UI, and
  replace authoritative DOM;
- passive deferred swaps must not be blocked indefinitely; timeout should cancel
  stale sessions and apply/refetch the server state.

## Non-Goals

- Do not replace HTMX or server-rendered HTML with a client framework.
- Do not move business authority or validation into TypeScript.
- Do not build persistence URLs in JavaScript.
- Do not create feature-specific JavaScript adapters for generic live-update or
  interaction behavior.
- Do not migrate the live-update wire protocol to compact fragment keys as part
  of this stream.
- Do not generate broad database/domain models for the browser.

## Implementation Order

1. Document the contract and update local agent docs (`ir-4uuy`).
2. Add Haskell interaction capability types with empty capabilities for existing
   live surfaces (`ir-fq28`).
3. Generate TypeScript contracts from those Haskell declarations (`ir-95e7`).
4. Add typed Haskell render helpers and guardrails (`ir-w50d`).
5. Implement the generic TypeScript intent bus and HTMX form bridge (`ir-ojl5`).
6. Prove the golden path on a low-risk click/select prototype (`ir-gyit`).
7. Add reusable pointer/touch disposable session primitives (`ir-mlle`).
8. Coordinate active disposable sessions with live-fragment swaps (`ir-ptnv`).
9. Prototype roster/timeline drop (`ir-mwrz`).
10. Prototype roster/timeline resize (`ir-z2ej`).

## Verification

Use focused checks as each slice lands:

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LiveSurface"
bash ./bin/in-env hspec-test --match "LiveUpdate"
```

Add Hspec/golden-style coverage for helper-rendered attrs/forms and guard tests
that reject raw interaction attrs/forms outside approved helper modules. Use
frontend unit/DOM tests for the generic runtime. Use focused Playwright only
when browser/HTMX/live behavior is the contract.

## Exit Criteria

- Existing live surfaces can declare empty interaction capabilities.
- At least one surface declares typed disposable layers and typed intents.
- TypeScript consumes generated interaction contracts.
- Haskell helpers render all interaction markup used by the prototype.
- The generic bridge submits committed intents through generated HTMX forms.
- The low-risk prototype proves portability, typed fields, server authority, and
  no JS-built persistence URL.
- Follow-up drag/drop and resize prototypes use the same typed model.
