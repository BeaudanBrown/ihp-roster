# Typed Interaction Surface Specification

This living spec defines the implementation contract for typed disposable
interaction surfaces. This is the durable contract for the seam shared by
`Application.Helper.FrontendContract.Surface`, `Application.Helper.LiveUpdate`, Haskell
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
- **Form toggle widgets** are server-rendered controls governed by the global
  generated Toggle contract. The checkbox owns presentation only; a form-local
  hidden transport owns the explicit submitted value or omission. The generic
  adapter synchronizes that transport before submission and may control one
  related native fieldset. Feature JavaScript must not translate toggle meaning,
  resolve transport by global id, or duplicate break-control behavior.

Views should not handwrite raw interaction `data-bepis-*` attributes, ref names,
disposable layer mounts, intent forms, HTMX intent attributes, or target ids once
helpers exist. Feature views should call typed Haskell helpers derived from
closed `FrontendSurface` contracts.

## Generated Interaction Registry And DOM Refs

The durable browser contract is a minimal generated interaction registry plus
role-specific DOM refs. `FrontendSurface` declarations own all static semantics,
but browser output retains only production-consumed source refs, dropzone refs,
activation refs, session definitions/effects, compatible refs, and modifier
variants. Intent forms, field presence, layers, conflict policies, and dynamic
keys remain concrete mount-local HTML rendered by `SurfaceImpl` and view helpers.
The browser registry does not duplicate action catalogs, DTO aliases, complete
static schemas, or server-only Surface metadata.

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
`data-bepis-activation-intent`, and `data-bepis-activation-trigger` are deleted
from the production interaction runtime and helpers. Current behavior derives
from generated registry entries and role-specific refs only; guardrails prevent
reintroducing the old semantic marker protocol.

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
2. Haskell contracts derive a scope-free minimal interaction registry from the
   same type-level `FrontendSurface` definition. It enumerates only source,
   dropzone, activation, session/effect, compatibility, and modifier data used
   by the generic runtime, without constructing a fake scope. `SurfaceImpl`
   owns concrete layers, conflict policies, HTMX form actions, targets, sync
   selectors, hidden values, and any fragment refs whose URLs depend on the
   mounted scope. Existing surfaces can use empty interaction metadata.
3. Haskell helpers render surface mounts, server layers, disposable layers,
   generated source/dropzone/activation refs with dynamic opaque keys, and
   generated HTMX intent forms. Helpers are the only production feature-facing
   API for interaction attrs; raw semantic marker helpers are deleted.
4. Haskell-generated TypeScript exposes explicit-reachability live payloads,
   exact mounts, generated DOM vocabulary, a fragment registry for live code,
   and an interaction registry for interaction code. Browser-facing contracts
   come from the unified `Application.Helper.FrontendContract` DSL registry,
   not external DTO codecs, hand-authored TypeScript, or `Aeson.Value`
   declarations.
5. Generic TypeScript discovers mounted contracts, manages disposable sessions,
   emits normalized intents, validates fields against DOM-owned generated form metadata,
   fills the matching generated form in the same mount, and dispatches the
   generated custom event.
6. IHP parses and validates params strictly, enforces authorization/scope,
   mutates server state, and returns authoritative HTMX fragments/OOB swaps.

## Modifier-Selected Intent Variants

Pointer interactions may declare semantic modifier variants when the same source
and target can commit different business intents. The modifier is semantic, such
as `copy`, rather than a raw browser key. Haskell-owned surface metadata declares
which semantic variants exist, which intent each variant submits, and which
preview/effect styling applies while that variant is active.

The generic runtime maps physical keys to semantic modifiers using platform-aware
bindings. The initial semantic modifier is `copy`: Windows/Linux use Ctrl and
macOS uses Option/Alt. Feature code should refer to the semantic `copy` variant,
not to `ctrlKey` or `altKey` directly. This keeps platform conventions local to
the generic runtime and generated contract while keeping server actions named by
business meaning.

Only one semantic modifier variant is active at a time. If no modifier is held,
or if the held modifier state is unassigned/unsupported for the current source
ref, the runtime falls back to the default intent. Multi-modifier chords are not
part of the current contract; holding more than one recognized physical modifier
also falls back to the default intent unless a future typed contract explicitly
adds chords.

Modifier variants should submit distinct semantic intents rather than sending raw
modifier fields into one controller branch. For example, roster drag/drop uses
`move-roster-shift-to-slot` as the default intent and a separate copy/duplicate
intent for the `copy` variant. Controllers still validate all submitted fields
and target tokens server-side; the modifier selection only chooses which
server-owned HTMX intent form is submitted.

Variant preview is also Haskell-owned metadata. A variant may override effect
styling, such as using a duplicate drag shadow class for the `copy` variant while
reusing the same drag session and compatible dropzone refs. Generic TypeScript
may select the declared variant effects, but it must not invent feature-specific
business rules or persistence URLs.

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
activation ref from the event target, looks up the generated registry entry for
that ref in the current mounted surface instance, and emits a committed intent;
server submission still happens only through the matching generated intent form.
Activation keys should be unique within a concrete mount for the ref kind unless
multiple rendered controls intentionally alias the same logical action.

Generic pointer session refs may start local disposable sessions from mouse,
pen, or touch pointer events. Surface specs should use shared aliases such as
`DragSessionDefinition`, `DragSourceRefFor`, `DragDropzoneRefFor`, and
`DragDropIntent` when declaring ordinary drag/drop behavior, so multi-source
surfaces stay explicit without re-declaring pointer fields and session effects.
A helper-rendered source ref declares only the static generated source ref plus
an opaque source key; the generated registry maps that source ref to the session
kind, compatible dropzone refs, eventual intent, submitted source/target field
names, and effect metadata. Generated or
helper-owned DOM attributes may disable/read-only a source, set a movement
threshold, or set a timeout. The runtime keeps one active session at a time,
captures the pointer when possible, emits `start`/`preview`/`commit`/`cancel`
phases, hit-tests with `elementFromPoint`, and clears disposable layers in the
same concrete mount on cancel, timeout, HTMX cleanup, explicit stop, or commit.
Preview phases are local only; the server DOM remains authoritative until a
committed intent submits through a generated intent form.

Pointer-session effects are Haskell-owned interaction metadata, not
frontend-only configuration. Surface declarations select a closed
`InteractionEffect`; arbitrary marker effects, selectors, and callbacks are not
an escape hatch. Reflection lowers each selection to closed semantic IR carrying
its lifecycle, required layer, source, options, and canonical CSS-class markers.
Unknown effects fail to compile, while missing declarations or incomplete IR fail
checked validation. TypeScript rendering is structural over that IR and cannot
silently omit an effect or invent a fallback layer. TypeScript resolves the
mounted surface, looks up
`FrontendSurfaceInteractionRegistry[surface].sessionKinds`, and constructs a
generic effect runner for the active session kind. If no registry entry, session
kind, or effects are present, the runner is a no-op and intent submission remains
unchanged. Runtime code may switch only on the generated closed effect union and
must use exhaustive `assertNever` handling for new variants.

Effects have two lifecycles:

- **Session-global effects** activate once when the movement threshold is met,
  update on every pointer movement while the session is active, and perform
  idempotent cleanup on every terminal path: commit, cancel, Escape,
  `pointercancel`, timeout, external HTMX cleanup, or runtime stop. Global
  effects may create or update disposable UI only inside a declared disposable
  layer in the same concrete mount.
- **Contextual target effects** are driven by generic hit-testing and the current
  ref target. They enter/update/leave as the pointer moves across matching
  dropzone ref elements, must clean the previous target before highlighting a new one,
  and must clean any active target on session end. Targets provide only generated
  ref data and configured CSS classes; targets do not inject arbitrary effect
  behavior.

The initial generated effect union is intentionally small. `clone-shadow` is a
session-global effect that measures the configured source ref element, renders an
inert same-size proxy shape in the configured disposable layer, disables pointer
events, and preserves the original pointer grab offset while following the
pointer. It deliberately does not try to screenshot or reconstruct arbitrary DOM;
visual styling comes from the configured generic CSS class. `dropzone-highlight`
is a contextual effect that uses the generic dropzone ref hit-test, applies
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
2. verify that every emitted field has matching generated intent-field metadata
   and a hidden/input field in the DOM-owned form;
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
`data-bepis-surface="..."` and `data-bepis-surface-config="..."`; the config
contains the mount key. The `FrontendSurface` runtime renders the server-owned
`action`, `hx-post`/`hx-patch`/etc., `hx-trigger`, `hx-target`, `hx-swap`,
optional `hx-sync`/`hx-disabled-elt`, and declared form inputs marked through
the generated intent, intent-field, and field-presence DOM vocabulary.

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

A roster cell exposes a generated activation/source ref in the server layer. The surface
capability declares a `SelectionOverlay` disposable layer and `SelectCell`
intent with fields such as `cellId` and `mode`. TypeScript creates a selection
highlight locally, supports keyboard/touch activation, and on commit fills the
`SelectCell` form in the same mount. The server validates the cell id and venue
scope, then returns authoritative selection state or next-step fragments.

### Drop

A draggable card and target slot are rendered with generated source/dropzone refs. The capability
declares a `DragPreview` disposable layer and `MoveAssignment` intent with
fields such as `assignmentId`, `targetSlotId`, and `position`. TypeScript may
render a ghost and insertion guide in disposable layers while dragging. On drop,
it submits the generated form. The server validates assignment ownership, target
scope, ordering, conflicts, and permissions before returning OOB fragments.

The roster drop implementation uses distinct generated refs for each semantic
source/target pair. Existing shift launchers are `shift-drag-source` sources;
staff-panel rows are `staff-drag-source` sources. Empty row-grid create
launchers expose one full-span `shift-slot-dropzone` shared by shift-move and
staff-create drags, while day-column `+ Add shift` cards retain explicit
`staff-create-dropzone` targets. Whole open day columns are
`day-column-dropzone` shift-move targets; the roster toolbar exposes
`delete-shift-dropzone` for shift deletion confirmation; existing editable shift
cards are `existing-shift-dropzone` staff-assignment targets. Compatible
shift-modifying targets share one disposable green border/shading affordance;
the class is applied to the semantic target owner rather than nested visual
cells.
The browser submits opaque `sourceItemKey` and `targetDropzoneKey` tokens through
the generated move/copy/staff-drop forms. Controllers parse those tokens,
validate venue/roster-week scope, draft/open-day status, empty target slots,
active staff, and roster-group eligibility, then return authoritative roster
fragments, dialogs, and toast feedback.

### Resize

A timeline item exposes generated source refs for typed edge handles. The capability declares a
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
