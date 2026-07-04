# Typed Interaction Surface Specification

This living spec defines the implementation contract for typed disposable
interaction surfaces. This is the durable contract for the seam shared by
`Application.Helper.FrontendSurface`, `Application.Helper.LiveUpdate`, Haskell
view helpers, generated TypeScript contracts, and the generic browser runtime.

## Scope And Source Of Truth

Server-rendered HTML remains authoritative. Interaction capability is optional
metadata attached to the same typed surface origin. Migrated surfaces declare it
in the type-level `FrontendSurface` spec and implement runtime form/fragment
metadata through `SurfaceImpl`. Existing surfaces should be representable with
empty disposable-layer, intent, field-schema, and conflict-policy definitions.

Haskell owns the canonical definitions for:

- surface family, surface scope, and concrete mount metadata;
- live fragment types, refs, target ids, refetch URLs, protection policy, and
  containment paths;
- server layers, disposable layer types, generated role-specific interaction
  refs, dynamic opaque key fields, and DOM ids;
- intent types, intent field schemas, and strict form contracts;
- HTMX method/route/trigger/target/swap attributes, including concurrency aids
  such as `hx-sync` or `hx-disabled-elt` where needed;
- live-fragment/disposable-session conflict policy.

TypeScript consumes generated browser-boundary contracts and stays generic. It
must not invent canonical `data-bepis-*` names, UI region capability values,
fragment keys, layer names, intent names, field names, target ids, mutation
URLs, or business rules.

## Vocabulary And Hierarchy

| Level | Term | Owner | Meaning |
| ---: | --- | --- | --- |
| 1 | Surface family | Haskell | Reusable UI surface type independent of a page, e.g. a roster timeline. |
| 2 | Surface scope | Haskell | Authorized logical data slice, e.g. one venue/week. A scope is not a route name. |
| 3 | Concrete mount | Haskell render helper | One occurrence of a family/scope on a page. It has a mount key used in derived ids, targets, and form ids. |
| 4 | Server layer | Haskell render helper | Authoritative server-rendered DOM inside the mount. Generic TypeScript must not mutate business DOM here. |
| 5 | Live fragment type | Haskell | Closed feature-local enum for one refreshable server DOM fragment. |
| 6 | Live fragment ref | Haskell | Target id, GET URL, protection policy, and containment path derived from the fragment contract. |
| 7 | Containment path | Haskell/server-only | DOM ownership path used to normalize overlapping fragment swaps. |
| 8 | Disposable layer | Haskell | Declared client-owned region for temporary UI, such as previews, selection rectangles, menus, or overlays. |
| 9 | Disposable session | Generic TypeScript constrained by generated contracts | Temporary local interaction state such as click-select, drag, resize, menu, or command mode. |
| 10 | Intent type | Haskell | Typed committed user action that may submit to the server. |
| 11 | Intent field schema | Haskell | Allowed string fields for a committed intent, including required/optional/default behavior. |
| 12 | Intent form contract | Haskell render helper | Generated HTMX form metadata and hidden inputs for one intent. |
| 13 | Conflict policy | Haskell, consumed by TypeScript | Whether a live fragment update during an active disposable session applies, defers, or cancels. |
| 14 | Generated TypeScript contract | Haskell-generated | Narrow DTOs/unions for the browser boundary. |
| 15 | Generic runtime | TypeScript | Surface discovery, disposable session management, intent dispatch, form filling, and live coordination. |

Conceptual structure:

```text
SurfaceFamily
└── SurfaceScope
    └── ConcreteMount(mountKey)
        ├── ServerLayer
        │   └── LiveFragments(type -> ref -> target/url/protection/path)
        ├── DisposableLayers
        │   └── DisposableSessions(local state + anchors + conflict policy)
        └── IntentForms(intent type + field schema + generated HTMX contract)
```

## DOM Ownership Boundaries

- **Server-owned DOM** is rendered by Haskell and swapped through HTMX/live
  fragments. TypeScript may read generated interaction refs from it but must not
  persistently mutate business structure, ids, field names, or server data.
- **Live fragments** are server-owned DOM targets with typed refetch URLs and
  containment metadata. Fragment GET endpoints return exactly the target node.
- **Disposable UI** is temporary client-owned DOM inside declared disposable
  layers. It must be safe to clear on cancel, timeout, page cleanup,
  conflicting live swap, or actor HTMX response.
- **Local widget DOM** such as a drag ghost, resize guide, selection rectangle,
  menu, command overlay, or measurement tooltip is disposable UI unless it is
  rendered back by the server as an authoritative fragment.
- **Intent forms** are hidden or visible Haskell-rendered HTMX forms for
  committed intents. They are server-owned contracts; TypeScript only fills
  validated generated inputs and dispatches the generated trigger. Mount JSON is
  not a mutation transport contract and must not replace DOM-owned HTMX forms.

Views should not handwrite raw interaction `data-bepis-*` attributes, ref names,
disposable layer mounts, intent forms, HTMX intent attributes, or target ids once
helpers exist. Feature views should call typed Haskell helpers derived from
closed `FrontendSurface` contracts.

## Generated Interaction Manifest And DOM Refs

The durable browser contract is a generated interaction manifest plus minimal
role-specific DOM refs. `FrontendSurface` declarations own the static semantics:
source refs, dropzone refs, activation refs, sessions, intents, intent fields,
compatible source/dropzone/session/intent combinations, effects, layers, and
conflict policies. `SurfaceImpl` and view helpers render the concrete mount-local
HTML: ids, HTMX forms, hidden values, dynamic opaque keys, and the generated ref
attributes.

Generated role-specific DOM refs are intentionally small and readable. The exact
attribute names are backend-owned constants in generated/shared contracts, not
feature-local string literals. The initial roles are:

- `data-bepis-source-ref` with `data-bepis-source-key` for elements that can
  start a pointer session;
- `data-bepis-dropzone-ref` with `data-bepis-dropzone-key` for candidate pointer
  targets;
- `data-bepis-activation-ref` for controls that emit a committed activation
  intent;
- generated form/field refs for DOM-owned HTMX intent forms.

`*-ref` values are generated static names derived from the surface type-level
spec. `*-key` values are dynamic, server-rendered, opaque browser-boundary
strings submitted back through generated intent fields. The browser may compare
and forward keys but must not parse them for business meaning; controllers parse
and validate all keys against venue/scope/domain state.

Legacy semantic marker attributes such as `data-bepis-marker`,
`data-bepis-item`, `data-bepis-dropzone`, `data-bepis-pointer-session`,
`data-bepis-session-kind`, `data-bepis-session-intent`,
`data-bepis-activation-intent`, and `data-bepis-activation-trigger` are
transitional only. They may exist during a dual-runtime migration, but the final
runtime must derive behavior from generated manifest entries and role-specific
refs. The epic that introduces the manifest must delete or guard old semantic
marker authoring before close.

## Surface Portability And Duplicate Mounts

A surface family/scope may move across pages or appear more than once on the
same page. Every concrete mount has a stable mount key. The mount key must
participate in generated DOM ids, live-fragment target ids, server layer ids,
disposable layer ids, intent form ids, HTMX targets, and any runtime lookup key
that could otherwise collide.

Generic TypeScript must resolve markers, forms, disposable layers, and fragment
refs inside the same concrete mount. It must not use global hardcoded target ids
or infer a singleton surface for a scope.

## Golden Path

1. Feature code declares closed Haskell types for disposable layers, intents,
   intent fields, and any interaction-specific markers.
2. Haskell contracts attach a scope-free generated interaction manifest to the
   same type-level `FrontendSurface` definition. The static manifest enumerates
   layer names, session names, intent names, field schemas, source refs,
   dropzone refs, activation refs, ref compatibility, effects, and default
   conflict policy without constructing a fake scope. `SurfaceImpl` owns
   concrete HTMX form actions, targets, sync selectors, hidden values, and any
   fragment refs whose URLs depend on the mounted scope. Existing surfaces can
   use empty static interaction metadata.
3. Haskell helpers render surface mounts, server layers, disposable layers,
   generated source/dropzone/activation refs with dynamic opaque keys, and
   generated HTMX intent forms. Helpers are the only production feature-facing
   API for interaction attrs; raw semantic marker helpers are temporary internal
   migration aids only.
4. Haskell-generated TypeScript exposes narrow browser DTOs/unions for live
   update payloads, registered surface families, static interaction schemas,
   layers, session kinds, intents, fields, live fragments, and conflict policy.
   Browser-facing interaction DTOs live in
   `Application.Helper.Frontend.Dto.Interaction` and are registered by
   `Application.Helper.Frontend.InteractionSchema`; static schema constants are
   encoded through those DTO codecs, not hand-authored TypeScript or `Aeson.Value`
   declarations.
5. Generic TypeScript discovers mounted contracts, manages disposable sessions,
   emits normalized intents, validates fields against the generated schema,
   fills the matching generated form in the same mount, and dispatches the
   generated custom event.
6. IHP parses and validates params strictly, enforces authorization/scope,
   mutates server state, and returns authoritative HTMX fragments/OOB swaps.

## Intent Phases And Submission

The default intent lifecycle is local until commit:

- **start**: establish anchors and session metadata; no server mutation;
- **preview/update**: move disposable UI or local widget DOM only;
- **cancel**: clear disposable UI and abandon local state;
- **commit**: submit exactly one typed intent through a generated HTMX form.

Commit-only submission is the default. Start/preview server submissions require
a future explicit typed form contract and should not be invented by runtime code.

Where TypeScript must branch on a generated closed union such as live-fragment
protection, session kind, or intent name, it must use an exhaustive switch with
`assertNever` so adding a Haskell constructor fails `frontend-check` until the
new case is handled. Prefer data-driven generic behavior when no branch is
needed.

Generic activation refs may promote ordinary click/change controls into the
intent path without feature-specific TypeScript. A helper-rendered activation ref
has a generated ref name, an activation trigger (`click`, `change`,
`keydown-enter`, or `keydown-space`), and optionally one value field whose value
is read from the event target/control. The browser runtime resolves the closest
activation ref from the event target, looks up the generated manifest entry for
that ref in the current mounted surface instance, and emits a committed intent;
server submission still happens only through the matching generated intent form.
Activation keys should be unique within a concrete mount for the ref kind unless
multiple rendered controls intentionally alias the same logical action.

Generic pointer session refs may start local disposable sessions from mouse,
pen, or touch pointer events. A helper-rendered source ref declares only the
static generated source ref plus an opaque source key; the generated manifest
maps that source ref to the session kind, compatible dropzone refs, eventual
intent, submitted source/target field names, and effect metadata. Generated or
helper-owned DOM attributes may disable/read-only a source, set a movement
threshold, or set a timeout. The runtime keeps one active session at a time,
captures the pointer when possible, emits `start`/`preview`/`commit`/`cancel`
phases, hit-tests with `elementFromPoint`, and clears disposable layers in the
same concrete mount on cancel, timeout, HTMX cleanup, explicit stop, or commit.
Preview phases are local only; the server DOM remains authoritative until a
committed intent submits through a generated intent form.

Pointer-session effects are Haskell-owned static interaction-schema metadata,
not frontend-only configuration. A `SessionKindDefinition` may declare a bounded
set of generated effect DTOs. TypeScript resolves the mounted surface family,
looks up `InteractionStaticSchemas.<family>.sessionKinds`, and constructs a
generic effect runner for the active session kind. If no schema, session kind, or
effects are present, the runner is a no-op and intent submission remains
unchanged. Runtime code may switch only on the generated closed effect unions and
must use exhaustive `assertNever` handling for new variants.

Effects have two lifecycles:

- **Session-global effects** activate once when the movement threshold is met,
  update on every pointer movement while the session is active, and perform
  idempotent cleanup on every terminal path: commit, cancel, Escape,
  `pointercancel`, timeout, external HTMX cleanup, or runtime stop. Global
  effects may create or update disposable UI only inside a declared disposable
  layer in the same concrete mount.
- **Contextual target effects** are driven by generic hit-testing and the current
  marker target. They enter/update/leave as the pointer moves across matching
  marker elements, must clean the previous target before highlighting a new one,
  and must clean any active target on session end. Targets provide only typed
  marker data and configured CSS classes; targets do not inject arbitrary effect
  behavior.

The initial generated effect union is intentionally small. `clone-shadow` is a
session-global effect that measures the configured source marker, renders an
inert same-size proxy shape in the configured disposable layer, disables pointer
events, and preserves the original pointer grab offset while following the
pointer. It deliberately does not try to screenshot or reconstruct arbitrary DOM;
visual styling comes from the configured generic CSS class. `dropzone-highlight`
is a contextual effect that uses the generic dropzone marker hit-test, applies
the configured CSS class to the active dropzone, removes it from the previous
target on switch/leave, and cleans up at session end. These effects are examples
of the generic lifecycle; they do not authorize a runtime to mutate server-owned
business DOM, construct persistence URLs, or invent new session/layer names.

Live-fragment coordination uses the same generic session boundary. Pointer
sessions publish mount/session start and end events. The live-update runtime
tracks active sessions by concrete mount and consults helper-rendered conflict
policies before refetching passive fragments. A matching policy may apply,
defer, or cancel; without a narrower policy, a passive refresh targeting the
same concrete mount defers and latest-per-target invalidation wins. Deferred
fragments are refetched immediately after session end. A bounded timeout is only
a fallback watchdog for lost terminal events or stuck sessions, so queued updates
converge to the latest server state instead of applying stale stored HTML.

On commit the generic bridge must:

1. find the generated intent form for the intent type inside the same concrete
   mount;
2. verify that every emitted field is declared in the generated schema and has a
   matching hidden/input field;
3. verify required fields are present and encoded as strings accepted by the
   schema;
4. refuse unknown fields or missing required fields before dispatch;
5. fill only the generated fields; and
6. dispatch the generated HTMX custom event, e.g. `bepis:intent-submit`, from
   the form.

The bridge must not construct mutation URLs, call `fetch` for persistence,
change HTMX routes/targets/swaps, or mutate server-owned business DOM.

The standard Haskell helper output is intentionally ordinary HTML/HTMX. For a
mount key `primary`, a helper-rendered shell includes the live-update surface
metadata plus interaction metadata on the same owner, e.g.
`data-bepis-surface="..."`, `data-bepis-surface-config="..."`, and
`data-bepis-mount-key="primary"`. `renderInteractionIntentForm` renders the
server-owned `action`, `hx-post`/`hx-patch`/etc., `hx-trigger`, `hx-target`,
`hx-swap`, optional `hx-sync`/`hx-disabled-elt`, declared field inputs marked
with `data-bepis-intent-field`, and fixed hidden inputs marked with
`data-bepis-intent-hidden-field`.

Use standard HTMX first: generated forms, custom event `hx-trigger`, lifecycle
events for cleanup, `hx-sync`/`hx-disabled-elt` for request concurrency where
useful, and OOB swaps for authoritative actor responses, toasts, and dialog
cleanup. Generic UI region lifecycle events (`bepis:region-*`) belong only on
server-declared fragment roots and complement, but do not replace, typed
interaction session events. Do not start with HTMX extensions or custom
elements; revisit them only after repeated stable lifecycle behavior justifies
consolidation.

## Examples

### Click/select

A roster cell exposes a typed selectable marker in the server layer. The surface
capability declares a `SelectionOverlay` disposable layer and `SelectCell`
intent with fields such as `cellId` and `mode`. TypeScript creates a selection
highlight locally, supports keyboard/touch activation, and on commit fills the
`SelectCell` form in the same mount. The server validates the cell id and venue
scope, then returns authoritative selection state or next-step fragments.

### Drop

A draggable card and target slot are rendered with typed markers. The capability
declares a `DragPreview` disposable layer and `MoveAssignment` intent with
fields such as `assignmentId`, `targetSlotId`, and `position`. TypeScript may
render a ghost and insertion guide in disposable layers while dragging. On drop,
it submits the generated form. The server validates assignment ownership, target
scope, ordering, conflicts, and permissions before returning OOB fragments.

The roster drop implementation uses editable row-grid shift launchers as draggable
items and empty row-grid create launchers as dropzones. The browser submits
opaque `sourceItemKey` and `targetDropzoneKey` tokens through the generated
`move-roster-shift-to-slot` form; the controller parses those tokens, validates
venue/roster-week scope and empty target slots, and returns authoritative roster
fragments plus toast feedback.

### Resize

A timeline item exposes typed edge handles. The capability declares a
`ResizePreview` disposable layer and `ResizeAssignment` intent with fields such
as `assignmentId`, `edge`, `newStart`, and `newEnd`. Pointer movement updates
only a preview guide. Commit submits the form; server validation decides whether
the new interval is allowed and responds with authoritative fragments.

### Non-drag disposable UI

Selection rectangles, context menus, command palettes, measurement overlays, and
keyboard command hints use the same model. They live in declared disposable
layers, may collect local state, and either cancel locally or commit by filling a
generated intent form. A menu action must not construct its own URL; it submits a
typed intent such as `OpenAssignmentMenuAction` or `ApplyBulkCommand` through the
contracted form.

## Live-Fragment Coordination

Interactive surfaces should have a stable outer mount, a server layer for
authoritative fragments, and sibling disposable layers for temporary UI.

Conflict policy is typed and conservative:

- non-conflicting fragment swaps may apply behind active disposable UI;
- updates touching active anchors, active targets, intent forms, disposable
  layer mounts, or the whole surface shell apply, defer, or cancel according to
  the Haskell-owned policy;
- actor HTMX responses for the committed intent win, clear disposable UI, and
  replace authoritative DOM;
- passive deferred swaps flush as soon as the active session ends;
- fallback timeout should exist only to prevent stuck sessions from hiding
  passive updates forever, and should cancel stale sessions then apply/refetch
  server state;
- if policy is missing or ambiguous, prefer cancel/refetch over preserving stale
  local UI.

The conflict policy should be expressed in generated contracts in terms of the
surface mount, active session kind, active anchors/targets, disposable layer,
and affected live fragment refs. TypeScript implements the generic decision but
does not decide feature semantics.

## Validation And Server Authority

IHP remains responsible for all business validation. Intent fields are browser
boundary strings, not trusted domain values. Controllers/actions must parse,
require, authorize, and validate every submitted field, including venue/scope
membership, live surface scope, record ownership, ordering, time intervals, and
conflict checks. `fill` alone is not enough for required request-derived fields;
use explicit required-param checks and total parsers where needed.

## Verification Expectations

Documentation-only changes in this area should run:

```bash
bash ./bin/in-env ./bin/doc-drift-check
```

Implementation tickets should add focused Hspec coverage for Haskell contracts,
rendered attrs/forms, guardrails against raw interaction attrs/forms, and live
fragment policy. Generic runtime tickets should add frontend unit/DOM tests and
focused Playwright only when browser/HTMX/live behavior is part of the contract.
