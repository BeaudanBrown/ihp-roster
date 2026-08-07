# FrontendSurface Authoring Guide


`Application.Helper.FrontendContract.Surface` owns the type-level surface contract system
for server-rendered interactive surfaces. New production surfaces should use this
path instead of authoring parallel DTO schema groups,
`Web.SurfaceInvalidation` entries, or a shared
projection cache.

## Source Of Truth

The root registry is the type-level list in
`Application.Helper.FrontendContract.Surface.Registry`:

```haskell
type RegisteredFrontendSurfaces =
    '[ TimesheetsSurface
     , RosterSurface
     , RosterDayTimelineSurface
     , LeaveRequestsSurface
     , BillingSurface
     , SupportSurface
     , ProfileSurface
     , StaffSurface
     , AdminPageSurface
     , AdminXeroPageSurface
     , AdminVenueSettingsSurface
     , AdminInvitesSurface
     , AdminExportsSurface
     , AdminShiftTypesSurface
     , AdminRosterGroupsSurface
     , AdminXeroSurface
     ]
```

A surface is added by defining a type-level spec with the primitives from
`Application.Helper.FrontendContract.Surface.DSL`, then adding it to this list.
`Application.Helper.FrontendContract.Surface.Reflect` recursively evaluates any
provided closed type-level DSL with typeclass instances without importing the
production registry. `Application.Helper.FrontendContract.Surface.Contracts`
binds that evaluator to `RegisteredFrontendSurfaces` and validates the reflected
value into the single checked `SurfaceContractIR`. Its `SurfaceIR` values are
embedded directly in the unified `FrontendContractIR`; no compact Surface copy
or conversion layer exists. Field, wire, schema, diagnostic, and HTMX values come
from `Application.Helper.FrontendContract.Core`, and both global and Surface
reflection use `Application.Helper.FrontendContract.Naming`. The same checked
model is the authority for runtime behavior, browser contracts in
`frontend/ts/generated/contracts.ts`, and semantic Surface architecture facts.

Contract generation does not inspect GHC compiler internals. Concrete type
synonyms and approved `Append`/`Concat` helpers reduce before reflection; every
supported DSL constructor has an explicit reflection instance. Add new DSL
vocabulary to the reflection and checked-IR path rather than introducing another
evaluator.

Feature specs normally live beside this directory as focused modules such as
`Timesheets.hs` and `Roster.hs`. Runtime feature behavior may live in the feature
area when it is tightly coupled to controllers/views, but it must implement the
same declared spec through `SurfaceImpl`.

Declaration-rich fixtures for reflection, validation, rendering, and
compile-failure coverage live under `Test/` and remain absent from
`RegisteredFrontendSurfaces`. Do not register test or diagnostic surfaces in the
production application merely to exercise DSL vocabulary.

## Composition Terminology

- **Surface**: an independently mounted, typed UI owner with a scope,
  subscription metadata, generated contract, and one-step `SurfaceImpl` runtime
  values.
- **Fragment** or **region**: a surface-owned server-rendered DOM target that can
  be refetched and swapped. The current DSL name is `Fragment`; documentation may
  use "region" when discussing DOM lifecycle.
- **Contained child surface**: a nested surface mount rendered inside a parent
  fragment/region and declared by that parent fragment through `ContainsSurface`.
- **Runtime reconciliation**: the browser lifecycle pass that treats the current
  DOM as the source of truth for mounted surface instances, initializes newly
  inserted mounts, and disposes removed mounts recursively so websocket
  subscriptions match mounted scopes.

A contained child surface is still an independent surface: it owns its own scope,
fragments, request decoration, focused-field protection, and invalidation
handling. Parent fragments may refresh broad HTML that includes child mounts, so
composition-safe runtime code must clean up removed child/grandchild mounts and
avoid duplicate subscriptions when the same instance remains mounted.

## Type-Level Spec Shape

Use nullary marker types plus promoted DSL primitives:

```haskell
data ExampleSurfaceName
data ExampleScope
data ExampleFragment
data VenueId
data WeekOffset

type ExampleSurface =
    Surface ExampleSurfaceName
        '[ Scope ExampleScope
            '[ Field VenueId 'WireUUID
             , Field WeekOffset 'WireInt
             ]
         , Fragment ExampleFragment '[] '[ 'Eager ]
         ]
```

Available primitives include:

- `Scope` for the authorized live data slice;
- `Fragment` for refreshable server-rendered DOM targets. Add the `Live`
  fragment option when the fragment participates in websocket invalidation;
- `Action` and `Intent` for Haskell-owned HTMX action/form metadata;
- `MountState` for server-side view state that is not part of the live
  subscription scope or emitted browser mount contract;
- `Session` plus session options such as `Layer` and `Effect` for typed
  interaction runtime coordination;
- generated source, dropzone, and activation refs for generic browser
  interactions;
- `BrowserRole`, `BrowserState`, and `LinkedHighlight` for mount-local,
  generated browser relationships and their closed activations/effects;
- `CompleteSetSort` for complete, server-rendered collections whose row DTO,
  allowed keys, comparator chains, direction policy, and defaults are closed in
  Haskell;
- `TabSet` for mount-local opaque tab keys and a declared default while the
  browser UI library remains the mechanical adapter;
- `ConflictPolicy` for session/fragment conflict behavior;
- `Event`, `DomToken`, and Surface DTO declarations for checked metadata.
  Plain `Dto` is server-only. `BrowserTypeDto`, `BrowserGuardDto`,
  `BrowserInboundDto`, `BrowserOutboundDto`, and `BrowserBidirectionalDto`
  explicitly select generated browser reachability and codec direction.
  `DomToken` is server-only; use `BrowserDomToken` only when production
  TypeScript also imports the semantic token. Guardrails require every emitted
  browser token to have a production consumer.

Wire fields use the closed browser wire universe: `WireText`, `WireInt`,
`WireBool`, `WireUUID`, `WireDay`, `WireClosed`, `WireList`, `WireOptional`,
`WireNullable`, and `WireRef`. `WireClosed value` must reference a registered
`ClosedScalar value`; it produces that exact Haskell type in generated builders
and parsers. Use the generated PostgreSQL enum type when persistence owns the
domain, never a shadow ADT. Roster template-card browser DTOs therefore carry
`WireClosed RosterTemplateScaleEnum`, not a handwritten `"day" | "week"`
projection. A non-persisted app domain may use its own finite ADT beside the
owning feature. Current request authorities include profile section, venue role,
employment basis, roster staff scope, leave section, feedback type, shift-type
colour, and export type. Open tagged reference selections such as Award/Xero pay
references and provider-owned Xero employee ids are explicitly classified and
must still obtain their field names from the nominal generated operation.
Do not serialize arbitrary domain models through surface fields; convert to a
narrow browser DTO or feature-specific render model first.

Shared declarations are type aliases, not a second registry. Compose helpers
with `Append`/`Concat`, for example the reusable drag/drop bundles in
`Application.Helper.FrontendContract.Surface.Interaction`. The generator expands helpers
and rejects conflicting normalized declarations with the same marker/name.

## Naming Policy

Generated names are derived from marker type names by
`Application.Helper.FrontendContract.Naming` using context-aware suffix stripping
and acronym handling. Prefer descriptive marker names and avoid exact-name
overrides unless the naming guardrails require them. Run the naming and surface
checks after adding markers.

## Generated Interaction Registry

`FrontendSurface` is also the source of truth for feature-specific
browser interaction names. `InteractionContract` keeps only generic runtime
shapes and generated DOM vocabulary. Reflection emits one minimal
`FrontendSurfaceInteractionRegistry` containing only production-consumed source,
dropzone, activation, and session runtime definitions. It does not emit the
server-only action catalog, intent/DTO aliases, contained-surface topology, or a
second static-schema copy. TypeScript consumes that registry to interpret
mounted surface instances; it must not invent feature-local interaction names,
depend on old global `Interaction*` roster enums, or infer business behavior
from ad-hoc DOM strings. Live-update code separately imports the minimal
`FrontendSurfaceFragmentRegistry`, so either bundle can tree-shake the other
feature lane.

Feature views still own ordinary HTML layout. They attach minimal role-specific
refs through generated Haskell helpers:

- `data-bepis-source-ref` plus `data-bepis-source-key` for pointer/session
  sources;
- `data-bepis-dropzone-ref` plus `data-bepis-dropzone-key` for compatible
  targets;
- `data-bepis-activation-ref` for controls that immediately emit an intent;
- generated intent form/field attrs for DOM-owned HTMX forms.

Ref values are generated static names. Key values are dynamic opaque strings
rendered by the server and submitted back through generated intent fields; the
browser may forward them but must not parse them as domain authority.

For pointer drag/drop, prefer the shared aliases in
`Application.Helper.FrontendContract.Surface.Interaction` over hand-assembling
low-level primitives. `DragSessionDefinition`, `DragSourceRefFor`,
`DragDropzoneRefFor`, `DragDropIntent`, and
`DragDropInteractionWithRefsAndVariants` cover the common pattern: one drag
session, one or more named source refs, named compatible dropzone refs, opaque
`sourceItemKey`/`targetDropzoneKey` fields, optional modifier variants, and a
DOM-owned HTMX intent form. Use the `WithExtraFields` variants when a committed
drag may continue through a server-rendered form that needs additional typed
intent fields; do not append unregistered request parameters in the controller.
Multi-source surfaces should give each semantic
source and target a distinct generated ref, then list the compatible dropzone
refs on each source; the browser runtime uses that manifest data for hit-testing
and highlighting while controllers keep validating opaque keys server-side.

Effect declarations select the closed `InteractionEffect` kind. Clone-shadow
effects carry their required typed layer; modifier variants carry only closed
effects, not arbitrary nested options. Reflection lowers these declarations to
`Surface.SemanticIR`, whose constructors carry canonical effect classes, source,
and options. Checked-IR validation rejects missing layer declarations,
non-canonical values, duplicate effects, and effects placed outside sessions or
modifier variants. The TypeScript renderer serializes those constructors without
name-based dispatch, omission, or fallback layers.

Concrete HTMX forms remain DOM-owned and server-rendered. Opaque typed action
and intent values plus their runtime render helpers own declared field bundles,
methods, hidden inputs, targets, swaps, sync selectors, disabled selectors, and
trigger events. Mount JSON must not become a custom mutation transport contract.
The generic browser runtime only validates generated semantics and matching DOM
forms, fills declared intent fields, and dispatches the generated HTMX trigger.

## Generated Linked Highlights

`LinkedHighlight` declares a Surface-owned relationship without exposing feature
selectors or browser business logic. Its source/member roles, optional pin role,
and ordered-member state are `BrowserRole`/`BrowserState` markers reflected to
`data-bepis-<surface>-<role-or-state>` names. Activations are closed to hover,
focus, keyboard, and optional pin; effects are closed to matching source,
matching member, and ordered member bounds. Checked-IR validation rejects
undeclared role/state references and generated-name collisions.

Views attach opaque membership and ordering keys with
`Application.Helper.FrontendContract.Surface.LinkedHighlight`. The generic
`frontend/ts/linked-highlight/runtime.ts` adapter imports only the generated
`FrontendSurfaceLinkedHighlightRegistry`, scopes every lookup to the nearest
surface mount, and applies browser-local transient classes:
`is-linked-highlight-source`, `is-linked-highlight-member`,
`is-linked-highlight-member-first`, and `is-linked-highlight-member-last`.
It may compare opaque keys for equality but must not parse them into domain
fields. Server-rendered HTML remains authoritative across HTMX reconciliation;
the runtime removes stale effects and resets pin accessibility state when a
source disappears.

Roster currently declares staff-to-shift highlighting on the roster surface and
shift-group highlighting independently on the roster and contained day-timeline
surfaces. Their views consume generated Haskell role helpers; raw staff/slot IDs,
feature selector attributes, and feature-specific highlight runtimes are not a
parallel contract.

## Browser-Reachable DTOs, Complete-Set Sorts, And Tab Sets

Surface DTOs are server-only unless their declaration explicitly selects a
browser reachability. The TypeScript generator emits only reachable DTOs and the
codec operations implied by their direction: type-only, guard, inbound parser,
outbound encoder, or both parser and encoder. Inbound parsers are exact: missing,
extra, or mistyped fields reject the whole payload. Haskell may serialize a
reachable DTO only through `Surface.Dto` marker-indexed helpers and a complete
`SurfaceFields` bundle; trying to render a plain `Dto` is a compile error.

`CompleteSetSort` is for presentation-only ordering when the server has rendered
the complete collection. It names generated root, row, and control roles; a
browser-reachable exact row DTO; an ordered inventory of keys; each key's ordered
comparator chain; text/integer/opaque value interpretation; selected-direction
versus always-ascending comparator direction; and initial key/direction. The
generic `frontend/ts/complete-set-sort/runtime.ts` adapter parses every row with
the generated DTO parser before mutation, scopes ownership to the nearest
Surface mount, applies stable deterministic ordering, and updates `aria-sort`.
It reports malformed rows and leaves their server order unchanged instead of
inventing defaults. Use marker-indexed helpers from `Surface.CompleteSetSort` to
render roots, rows, and controls; views and TypeScript must not repeat role
names, payload field names, sort keys, comparators, or defaults.

`TabSet` declares one generated tab role, a closed opaque key inventory, and a
default key. The generic `frontend/ts/surface-tab-set/runtime.ts` adapter listens
to the UI library's shown-tab event, remembers only valid keys per concrete
mount and declaration, restores that selection after HTMX replacement, and
falls back to the declared default when the remembered key is absent. It does
not own pane markup, Bootstrap activation mechanics, or business state. Render
tab keys with `Surface.TabSet`; do not add feature-specific parsers or storage
attributes.

Roster staff-panel sorting and tabs are the first production consumers. Their
curated Haskell view boundary is
`Application.Helper.FrontendContract.Surface.Roster.StaffPanel`. The declared
row payload contains an opaque row key, name, role, assigned-shift count, and
ideal-shift count. The old per-field attributes, global sort enum, and
roster-specific TypeScript runtimes are deleted and guarded against return.

## Surface-Owned Closed Browser States And Roster Chrome

`BrowserClosedState` pairs a generated Surface state attribute with a non-empty,
checked value inventory. TypeScript receives the attribute constant, named value
object, exact union, and guard. Haskell rendering uses
`surfaceBrowserClosedStateLiteral`, which rejects values not declared by that
state at compile time. Use native properties or ARIA state when they already
express the semantic relationship; use a closed Surface state only when CSS and
the adapter need a shared app-specific state on a generated root.

Roster fullscreen and column editing are the first production consumers. The
curated `Surface.Roster.Chrome` boundary renders fullscreen root/toggle/label and
column editor/start/done roles plus initial collapsed/inactive states. The
browser adapters import every role, state attribute, value, and guard. Fullscreen
keeps icon classes, focus, and Escape handling browser-local. Column editing
keeps its delayed blur mechanical, stores timers per generated editor, and
cancels them when HTMX removes that editor. Neither runtime discovers behavior
through roster presentation classes or carries state from a replaced root.

## Generated Roster Image Export

The roster Surface declares image-export trigger/config/projection/row/cell
roles, a closed JPG format, an exact export-policy/copy record, and an exact cell
text record. `Surface.Roster.ImageExport` resolves the filename and serializes
all format dimensions, quality, labels, failure copy, and optional
export-specific cell values. The roster row-grid view attaches those helpers to
its current projection and emits the trigger; layouts without that projection
omit the trigger instead of exposing an unusable adapter action. No view exposes
cell kinds or conflict metadata to the browser.

The focused TypeScript adapter resolves one projection inside the trigger's
nearest Surface mount and parses every exact payload before cloning. It retains
only layout measurement, computed presentation styles, SVG/Canvas rendering,
JPG encoding, and browser download mechanics. It must not recover roster meaning
from feature classes, cell positions, group selectors, week labels, or raw
conflict annotations.

## Retained Roster Week Overview

The disabled roster week overview is retained behind generated panel/day/today/
detail-slot roles, exact panel/day payloads, and closed availability, closure,
and calendar-day states. `Surface.Roster.WeekOverview` builds date labels,
metric displays, summary copy, navigation URLs, and state values in Haskell.
Selection uses native `aria-pressed`; CSS and the adapter consume generated
state attributes rather than shared `is-*` classes.

The adapter validates one clicked day and its local slots before mutation. A
malformed day emits a structured diagnostic, leaves that element and
server-rendered details intact, and does not prevent valid siblings from being
used. The normal roster header still renders a static week label and does not
mount or fetch this retained capability.

## Generated HTMX Request Actions

`Action name fields options` describes surface-owned request initiators, not
successful business refresh behavior. Its `fields` list is the browser-submitted
payload/form boundary. Unrelated route params and venue/page context stay in
Haskell route builders such as `pathTo` and `appendQueryParams`; do not move IHP
routes into the type-level DSL. Declared action fields do not belong in
`FrontendSurfaceActionRoute`. Production callers import their feature-owned
`Surface.<Feature>.Action` facade, build the complete bundle with its generated
operation field builder, and pass that bundle to the generated operation
metadata function. The generic `frontendSurfaceAction` constructor remains an
implementation seam for private generated modules and focused fixtures, not a
feature-call-site API.

Use standard HTMX options for stable request metadata:

- `HtmxMethod` for `hx-get`, `hx-post`, `hx-put`, `hx-patch`, or `hx-delete`;
- typed selectors such as `HtmxId`, `HtmxClass`, `HtmxClosest`, and `HtmxFind`;
- typed triggers such as `HtmxClick`, `HtmxChange`, and `HtmxLoad`;
- typed swaps such as `HtmxInnerHTML`, `HtmxOuterHTML`, and `HtmxNoSwap`;
- typed synchronization such as
  `HtmxSyncOn (HtmxClosest (HtmxId Shell)) HtmxSyncReplace`;
- `HtmxRawSelector`, `HtmxRawTrigger`, `HtmxRawSwap`, or `HtmxRawSync` only
  when the closed recipes cannot express the value. Every raw node carries a
  non-empty reason and validation rejects an empty reason;
- `CustomHtmx Marker "reason"` only for extra HTMX attributes that a standard
  option does not describe. The reason remains in the checked Haskell IR for
  validation and architecture review; it does not force a browser action
  manifest to be generated.

Reflection renders common punctuation deterministically: an ID selector owns its
`#`, class selectors own `.`, traversal recipes own their separating space, and
sync recipes own their `:` strategy delimiter. Views must not add or strip this
punctuation.

Runtime views combine opaque `FrontendSurfaceAction` values with a
`FrontendSurfaceActionRoute` using the form, submit-button, link, or HTMX-only
render helper. These helpers render generated `data-bepis-surface-action`
metadata plus the declared HTMX attrs. Links serialize the complete typed bundle
into the request URL and replace stale same-named query values while preserving
unrelated route context. Forms and form-owned controls remove declared fields
from route URLs; named controls in the body own mutable values, while
`renderFrontendSurfaceActionFormWithHiddenFields` emits a complete fixed bundle.
They can also render standard `method`/`action`, `formaction`, or `href` attrs for
browser semantics, but that is not a complete no-JS UX unless the controller
returns full-page or redirect fallbacks.

Controllers parse the same declaration through the exact operation parser from
their feature-owned `Surface.<Feature>.Action` or `Surface.<Feature>.Intent`
facade. Production callers do not invoke the generic Action/Intent parsers
directly. Parsing ignores unrelated request parameters,
returns declaration-ordered `SurfaceFields`, and accumulates structured field
errors. Required fields reject absence, optional fields map absence or blank to
`Nothing`, and nullable fields require presence while mapping blank to
`Nothing`. Repeated form parameters are decoded through `WireList`. Attach
transport errors to normal model validation with
`attachSurfaceRequestFieldErrors`; do not recover required fields with
`paramOrDefault`. A route that also supports partial, ordinary URL filters may
use `surfaceActionParamsComplete` only to decide whether a complete Surface
envelope was submitted. Those partial filters remain route context; after a
Surface envelope is selected, always parse it strictly and report every error.

Successful migrated mutations must not return authoritative business fragment
HTML/OOB for the same surface. They should set `HX-Reswap: none`, emit
actor-local live-fragment refresh metadata through
`setActorLocalFragmentsRefresh` only for requester-local workflows where no
shared resource changed. Mutations reporting touched resources use
`setActorLiveResourcesRefresh`, so actor mount keys and passive subscription keys
are evaluated by the same planner over the same
`SurfaceResourceValue`s. A successful workflow that must also reset a
`ResyncOnly` actor fragment uses `setActorLiveResourcesRefreshIncluding` to
combine that explicit actor-only key with the resource-planned keys in one
refresh payload. Passive invalidation handles other tabs/viewers. OOB remains
valid for extras such as dialog clears, toasts, disposable-layer cleanup,
focus/scroll hints, and validation-local responses. Plain fragment GET/refetch
endpoints should return the target node itself, not OOB wrappers.

Admin Roster Groups is the reference migration: create/update/move/toggle
request initiators are declared in `Surface.Admin`, rendered from generated
helpers in `Web.View.Admin.RosterGroups`, and successful create/update/move
responses use actor-local invalidation instead of roster-group business OOB.

Legacy semantic marker attributes such as `data-bepis-marker`,
`data-bepis-pointer-session`, `data-bepis-session-kind`,
`data-bepis-session-intent`, `data-bepis-activation-intent`, and
`data-bepis-activation-trigger` are deleted from production helpers and the
browser runtime. Production feature views author generated refs through
`Application.Helper.FrontendContract.Surface.Interaction`; guardrails prevent
reintroducing the old semantic marker protocol.

## Marker-Indexed Runtime Values

Use `Application.Helper.FrontendContract.Surface.Values` instead of scanning the
reflected registry by protocol strings. `surfaceNameValue`, `surfaceScopeValue`,
`surfaceFragmentValue`, `surfaceResourceValue`, `surfaceSourceRefValue`,
`surfaceDropzoneRefValue`, `surfaceActivationRefValue`, and
`surfaceDomTokenValue` are indexed by both the owning `Surface` and marker.
Actions and intents are selected through generated operation functions exported
by their feature-owned `Action` and `Intent` facades. The generic metadata
constructors remain implementation seams used only by private generated modules
and focused fixtures. A marker owned by another surface is a compile error.

Build scope, mount-state, fragment, and action payloads with declaration-ordered
`SurfaceFields`, `surfaceField`, `surfaceOptionalField`, and
`surfaceNullableField`. The field marker, presence, wire type, and Haskell value
must match the owning declaration. `WireUUID` values are `UUID`, not unchecked
text; an absent `OptionalField` is omitted, while `NullableField` retains its
explicit null. Use `surfaceFieldNameFrom` to obtain an input name only after a
complete bundle exists, and use `surfaceFieldsJson` only at the JSON boundary.
Do not introduce phantom `Aeson.Value` carriers, open field-value lists, or
runtime fallbacks for required fields.

### Compile-time diagnostic contract

Marker-indexed ownership failures name the compact Surface owner marker and the
requested scope, fragment, resource, action, intent, ref, or token marker. They
must not render the expanded `Surface ...` primitive list. Bundle field-name
accessor failures identify the marker absent from the complete bundle; action or
intent ownership failures remain attached to the opaque constructor call.

`SurfaceFields` construction keeps the exact declared field list as its
contextual type. Its raw data constructors stay hidden: use the
`noSurfaceFields` and `(&:)` construction functions, which deliberately provide
no matching or unwrapping path. Do not replace that context with a separately
inferred generic provided-field list: the declaration must continue to infer
numeric values, `Nothing`, nested wires, and other valid inputs. These
declaration-directed builder checks report:

- the next missing field and remaining declared shape;
- an extra field's marker and presence, explicitly noting that it has no
  declared wire;
- expected and received markers for an ordering mismatch;
- expected and received presence for a presence mismatch; and
- the affected marker, declared presence/wire, and received Haskell type for a
  wire mismatch.

Diagnostic shapes use DSL spellings such as `required WireUUID`,
`optional WireText`, `required WireClosed RosterLayoutModeEnum`, and
`nullable WireRef SomeDto`. GHC may qualify marker names
or wrap lines, but the diagnostic category, affected marker, and expected
contract shape are a tested authoring interface. Keep the focused expectations
in `Config/nix/scripts/frontend/surface-compile-fail-check` in sync when this
contract intentionally changes.

Live identity crosses this boundary through
`Application.Helper.FrontendContract.Surface.Live` only.
`frontendSurfaceScope` and `frontendSurfaceFragmentKey` accept the complete
marker-indexed field list and return opaque transport identities;
`matchFrontendSurfaceScope` and `matchFrontendSurfaceFragmentKey` recover only
the declaration-ordered typed values. Feature-owned adapters live beside their
contracts, for example `Surface.Roster.Live` and `Surface.Timesheets.Live`.
Adding, removing, reordering, or retyping a declared identity field therefore
breaks every incomplete constructor or matcher at compile time. Feature code
must not import `LiveUpdate.Internal`, pattern-match transport constructors, or
recover feature meaning from raw Surface/fragment text or JSON fields.

Resource identity crosses the planner seam through
`Application.Helper.FrontendContract.Surface.Resource` only.
`frontendSurfaceResource` accepts the complete marker-indexed resource field
list and returns an opaque `SurfaceResourceValue`;
`matchFrontendSurfaceResource` recovers only declaration-ordered typed values.
Concrete values and the matchers needed by feature-owned domain expansion live
beside their contracts in modules such as `Surface.Roster.Resource` and
`Surface.Profile.Resource`. Adding, removing, reordering, or retyping a resource
field breaks incomplete constructors and matchers at compile time. Feature code
must not import `Surface.Resource.Internal`, construct resource names/JSON, or
recover resource fields by text.

### Generated toggle capability

`Application.Helper.FrontendContract.Toggle` is the focused global contract for
checkbox-style presentation backed by explicit form transport. It generates the
closed presentation/submission enums, value-or-omitted targets, exact
`ToggleConfig` parser, and root/input/label/transport/break-region DOM
attributes. Presentation state is deliberately separate from submitted target
state, so inverted controls such as **Hide approved** are represented without
browser-side business translation.

Feature views build Surface-owned scalar and repeated-field mappings through
`surfaceToggleScalarField` and `surfaceToggleListItemField`. Both require the
complete generated Action field bundle and the declaration's Haskell source
type; scalar/list misuse and wrong item wire types fail at compile time. Native
business forms outside a Surface Action may use `namedBooleanToggleField`, but
must not restate boolean wire values in the view.

`Application.Helper.View.ToggleButton` renders one unnamed checkbox plus one
named hidden transport inside the same form. The generated opaque key relates
the root, input, and transport without document-global id lookup. The generic
browser adapter parses the exact config, synchronizes the transport during
capture phase before any submit serialization, then applies immediate or
deferred submission policy. It also owns checked presentation, state labels,
ARIA switch state, and an optional native break `fieldset`; feature JavaScript
must not duplicate those mappings or rediscover picker internals. Responsive
layouts render each control once and move that one node with CSS rather than
emitting duplicate ids.

### Generated time-picker capability

`Application.Helper.FrontendContract.TimePicker` owns the reusable quarter-hour
picker's modal id and field, configuration, value, trigger, label, step-down,
step-up, options-grid, option, and clear roles. `TimePickerConfig` is an exact
inbound record of `rangeStart`, `rangeEnd`, `stepMinutes`, and `emptyLabel`;
`TimePickerOption` is an exact inbound record of `value` and `label`.
`Application.Helper.FrontendContract.TimePicker.Runtime` serializes both records
through declaration-indexed carrier fields, so missing or reordered Haskell
fields fail compilation and malformed browser records fail generated parsing.

`Application.Helper.View.TimePicker` remains semantic authority for overnight
range resolution, the quarter-hour step, default/empty/modal/accessibility copy,
canonical option values and display labels, and initial disabled/button state.
The generic browser adapter resolves only generated roles, parses every field
and option locally, and rearranges the existing validated server-rendered option
buttons for the active range. It supplies no fallback range, option, value,
label, or copy. A malformed field or option emits a structured diagnostic and
is skipped before its server HTML is mutated.

This capability deliberately ends at picker-internal behavior. The generated
Toggle capability remains the sole owner of explicit form mapping, synchronized
submission, and the native timesheet break fieldset. The picker reads ordinary
native disabled state and neither imports Toggle roles nor installs a break
handler.

### Generated ordered-range capability

`Application.Helper.FrontendContract.OrderedRange` owns the reusable two-endpoint
range's root, exact config/state, start, end, and availability roles. The config
carries the complete allowed integer range, step, workflow defaults, ordered
label inventory, and closed crossing policy. The state carries current start/end
values and native availability. Generated position-property constants are the
only Haskell/TypeScript agreement used for disposable track presentation.

`Application.Helper.FrontendContract.OrderedRange.Runtime` validates and
serializes both declaration-indexed records. The staff/profile shift-preference
view composes those attrs with ordinary named range inputs, native labels and
`output[for]` relationships, plus the existing generated Toggle control. The
ordered-range adapter validates that whole local subtree before installing
listeners or changing server HTML, keeps initialization state outside the DOM,
and looks up every dynamic label from the Haskell inventory. It implements the
generated `clamp-other-endpoint` policy mechanically in either direction and
uses native disabled state for availability styling.

The capability does not own request transport or business validation. Toggle
continues to synchronize the repeated availability field, the named range inputs
submit unchanged values, and `parseShiftPreferenceSelections` remains
server-authoritative for weekday, bounds, and endpoint ordering.

### Generated horizontal-scroll capability

`Application.Helper.FrontendContract.HorizontalScroll` owns reusable snap and
mouse drag-scroll roles plus exact snap/drag configuration. Haskell constructors
select nearest-item or equal-group snapping and provide the required local item,
CSS-property/scope, or drag-ignore relationship. Roster and Timesheets views
render only the focused runtime attrs; TypeScript imports the generated roles
and exact parsers.

The adapter initializes one controller per mounted scroller and disposes every
controller in an HTMX cleanup subtree. New user input invalidates stale snap
work. Pointer thresholds, debounce timing, click suppression, and transient
`is-horizontal-*` classes remain module-owned browser mechanics rather than
contract fields or persistent DOM state.

### Generated PWA installation capability

`Application.Helper.FrontendContract.PwaInstall` owns the public installation
page, install button, result, result-state, and installed-status roles. Its
closed accepted/dismissed/failed state relates browser outcomes to complete
Haskell-rendered result messages; no browser prompt or platform object crosses a
wire schema.

The adapter imports those generated roles and state guard while retaining native
`beforeinstallprompt`, `appinstalled`, display-mode, and Apple standalone
handling locally. Availability and installed/result visibility use native
`hidden`; status and live-region accessibility remain ordinary HTML/ARIA. The
adapter selects existing server-rendered copy and must not synthesize fallback
messages or persist an availability/installed state attribute.

### Generated passkey capability

`Application.Helper.FrontendContract.Passkey` owns the reusable passkey login,
registration, setup-prompt, action, device-name, status, recovery, and dismissal
roles. Its browser boundary includes one exact tagged configuration for login,
registration, or setup-prompt plus exact begin-option records, serialized
registration/authentication request records, tagged finish outcomes, and tagged
structured errors. Login and registration carry Haskell-built begin/finish URLs,
an optional success redirect, a local status relationship, and complete
status/loading copy. Setup prompts carry an opaque user key and the closed
first-passkey/additional-device mode. The focused Haskell runtime derives all
names and values from marker-indexed declarations; views render complete
controls and recovery copy through `Application.Helper.View.Passkey`.

`Application.Helper.FrontendContract.Wire.Passkey` is the Haskell carrier and
WebAuthn-library conversion seam. Controllers render and parse only those exact
schema-indexed values. The TypeScript adapter resolves every action, status,
device-name, and recovery relationship inside the nearest generated flow root,
parses successful and error server envelopes before invoking native credential
APIs or redirecting, and encodes serialized credentials through generated
encoders. It keeps initialization in `WeakSet` storage and reports malformed
configuration without changing authoritative HTML. Browser capability checks,
`navigator.credentials`, native credential/response objects, extension-result
semantics, local-storage hints, and base64url conversion remain adapter-local.
Setup-prompt dismissals also use the generated overlay close role and consume
its generated semantic dismissal event. The passkey adapter records the local
UX hint for close-control, Escape, and backdrop dismissal while the overlay
adapter alone owns dialog removal, body locking, and focus policy.

### Generated Xero candidate-filter capability

`Application.Helper.FrontendContract.XeroCandidateFilter` owns the root, search,
candidate, and filtered-empty roles plus one exact candidate configuration for
the imported pay-item dialog. Its runtime accepts only Haskell-selected text
fields, normalizes them once, hides the projection constructor, and serializes
that projection through a declaration-indexed record. Views cannot attach raw
feature text without crossing the boundary, while the generated exact parser
rejects absent, extra, or incorrectly typed configuration fields.

The Xero view chooses earnings-rate name and account code as projection inputs
while retaining checkbox names, remote earnings-rate ids, validation, and import
routes on the server. The adapter imports every role and the exact config parser,
validates a complete root before mutation, reports structured diagnostics, then
fuzzy-matches the opaque projection and changes only native `hidden` state. A
feature CSS rule keeps hidden candidate labels invisible
when Bootstrap's `d-flex !important` utility is present. Filtered-empty copy and
status/live-region semantics remain server-rendered.

### Generated overlay capability

`Application.Helper.FrontendContract.Overlay` owns the shared workflow-dialog
and toast lane mount ids, role attributes, the semantic dialog-dismissed event,
dialog auto-submit state, and exact submit/toast configuration schemas. Shared
Haskell overlay helpers render those roles and serialize loading-label/auto-hide
configuration through the focused runtime. Dialog and toast TypeScript parse the
generated exact records and keep one-time/original-markup state in
`WeakSet`/`WeakMap` storage rather than adding browser-only data attributes. The
dialog adapter emits the generated event before close-control, backdrop, or
Escape removal so composed capabilities can record semantic dismissal without
owning DOM removal, focus, or body locking.

This capability does not own mutation semantics. Dialog launchers and forms
continue to use their generated AppShell or Surface Action metadata, and picker
markup remains a separate overlay lane. Bootstrap modal classes/events and
module-owned toast transition classes stay inside the adapters; native disabled
state and ARIA dialog/control state remain native rather than being duplicated
as app DOM vocabulary.

HTMX workflows may opt into generated dialog-keyboard and focus-region roles.
The Overlay adapter then restores first-invalid/autofocus focus after replacement,
traps Tab in enabled content controls, and maps Enter/Escape to the existing
submit/dismissal semantics while preserving multiline Enter. This is opt-in and
does not change page-dialog fallbacks. Time stepping and numeric selection stay
inside the independently opted-in TimePicker capability.

## Generated Haskell Adapter Foundation

Mechanical feature adapters are generated from the same checked declarations;
they are not another Surface evaluator. A nominal adapter family has one typed
`AdapterFamilySurface` association to an existing Surface alias. The
kind-indexed `SurfaceAdapterHome` aliases register only `(family, declaration
marker)` for resources, scopes, fragments, actions, and intents. Declaration
order, presence, wire shape, protocol names, and Haskell source types still come
from checked IR and the canonical `haskellWireSource` projection. The production
family registry mirrors `RegisteredFrontendSurfaces`; feature-local
`Surface.<Feature>.HaskellAdapter` modules own those associations, and later
adapter kinds reuse them instead of adding parallel family registries.

`HaskellAdapter.Core` owns the one shared implementation of home/family
resolution, `Typeable` metadata, Haskell source types, import aliasing, locality,
collision checks, deterministic module rendering, and generated-file
bookkeeping. Focused renderers supply checked declarations and their
function-level source only; they do not switch on reflected feature names or
adapter-kind text. Completeness uses these kind-indexed identities:

- a resource uses its checked shared resource identity;
- a scope uses its runtime Surface identity;
- a fragment, action, or intent uses owning Surface plus declaration identity.

An action and intent may therefore share the same marker and reflected name.
Generated-name collisions are checked across each complete physical output
module (including scope and fragment declarations sharing `Generated.Live`),
not across kind-separated modules such as Action and Intent.

The private output/facade pairs are fixed as `.Generated.Resource` / `Resource`,
`.Generated.Live` / `Live`, `.Generated.Action` / `Action`, and
`.Generated.Intent` / `Intent`. Scope and fragment declarations deliberately
share the Live pair. The focused resource renderer uses the core and the
aggregate registry assigns exactly one canonical home to every unique checked
production resource identity.
Repeated dependency occurrences do not create extra homes. The shared
`time-picker-config` identity, for example, has its canonical home in the Roster
day-timeline family even though Timesheets also depends on it.

The focused Live renderer selects every checked Surface scope and every fragment
with `Live`; non-passive fragments that already own an actor-local semantic key
require a typed, non-empty, reason-bearing exception. Those exceptions cover the
Admin and Admin Xero parent-page content keys. Scope and fragment
`CheckedAdapterDeclaration` values come only from kind-specific `SurfaceIR` +
`ScopeIR`/`FragmentIR` normalizers. Their kinds survive home resolution and only
the closed `LiveScope` / `LiveFragment` payload reaches the shared
`.Generated.Live` renderer.

`RegisteredSurfaceScopeAdapterHomes` and
`RegisteredSurfaceFragmentAdapterHomes` assign exactly one typed production home
to every selected declaration. Once the first production family migrated, the
initial empty-home branch was removed: empty, partial, extra, or duplicate Live
homes now fail the mandatory all-kind generation run. Independent literal
goldens in `Test.LiveUpdateSpec` continue to pin production scope JSON,
fragment-key JSON, and canonical `surfaceScopeKey` values across the replacement;
generated-vs-generic equality is not their source of truth.

`HaskellAdapter.Request` is one checked implementation for Action and Intent
request adapters. Kind-indexed layouts and `ResolvedAdapter` retain nominal lane
identity through home resolution, so Action output cannot enter the Intent
renderer or vice versa. Each inventory registration owns both its typed home and
its generated/excluded operation decisions; no parallel Action/Intent home list
exists. The validated source-resolved adapter from inventory resolution is
prepared directly for deterministic rendering rather than resolved a second
time. The shared implementation emits a declaration-complete `SurfaceFields`
builder, marker-indexed metadata (`FrontendSurfaceAction` or
`FrontendSurfaceIntentForm`), and an exact parser delegating to
`parseSurfaceActionParams` or `parseSurfaceIntentParams`. Every exclusion
requires a non-empty reason.

The production inventory contains all 62 checked actions and all six checked
intents. Fifty-seven actions have Haskell adapter consumers; the five action
declarations backing the same-named interaction intents remain typed,
reason-bearing declaration exclusions. Exactly one inventory registration owns
each action across the Admin, LeaveRequests, Profile, Roster,
SelfServiceLeave, Support, and Timesheets families. Fifty-six provide
generated field-builder and render-metadata operations; the hidden
roster-week-start compatibility mutation is parser-only with typed exclusions
for its inactive rendering operations. Forty-two provide exact parsers and the
other 15 retain typed, operation-specific no-parser reasons. Production callers
use the seven curated `Action` facades: generic parser and metadata calls under
`Web/` are both zero, enforced by source guardrails.

All six intents have exactly one checked production registration across the
Roster and Roster day-timeline families. Each emits its inventoried builder, form metadata,
and exact parser into the single private `Surface.Roster.Generated.Intent`
module behind `Surface.Roster.Intent`. The former five generic form constructors
and five generic parser calls under `Web/` are zero, enforced by source
guardrails. The same-marker Action declaration exclusions remain typed and
reason-bearing.

Generated resource modules invoke `frontendSurfaceResource` and
`matchFrontendSurfaceResource`; generated Live modules invoke only their focused
scope/fragment constructors and matchers. Roster Action builders now construct
`ActionFields operation` from a generated kind-specific token and that
operation's exact local `ActionFieldSpecs`; no Roster caller signature or
generated implementation retains `RosterSurface`. Generated checked-IR evidence
supplies compact owner, marker, field-name, and HTMX metadata, while exact
parsers return the same nominal bundle. Other Actions and every Intent retain
`SurfaceActionFields surface action` or `SurfaceIntentFields surface intent`
until #347.

Raw field constructors stay hidden, no wrapper exposes an unwrap/re-indexing
path, and read-only `SurfaceFieldBundle` lookup/serialization works for both
seams. Resource, Live, and Action facades expose only operations with a semantic
consumer. Generated modules stay behind their matching curated facade. The sole
constructor exception is Roster `Generated.Action` importing the focused
request-runtime internal evidence seam; exact source guardrails permit that
generated module plus the compatibility runtime.

Private production `.Generated.Resource` and `.Generated.Live` modules are
registry-derived declaration-complete APIs: each checked declaration keeps its
constructor and matcher even when the executable graph needs only one side.
Within Surface, `weeder.toml` therefore roots exactly those two generated
module categories. IHP-generated Fetch statements and exact executable script
entries have separate project-level roots. Typed-home completeness, all-kind generation, generated drift, and source
import guardrails enforce that exception structurally. Generated Action/Intent,
curated facades, and handwritten modules remain under normal Weeder
reachability; symbol allowlists and blanket FrontendContract exclusions are not
permitted.

The mandatory adapter writer also emits one temporary Roster Action authority
proof. `AssertActionAuthority` compares the canonical complete Surface Action
sequence with generated operation owner/marker/ordered-field entries. The proof
typechecks with the complete staged managed set, is never published, and is
absent from `app-lib`.

The lightweight `HaskellAdapter.Association` module owns only
`SurfaceAdapterFamily` and `AdapterFamilySurface`. Production family modules and
private Live output import that seam, while reflection, registry validation, and
generator mechanics remain in `HaskellAdapter.Family` and
`HaskellAdapter.Core`. Focused feature compiles therefore do not transitively
load the generator implementation. Unsupported carriers stop generation with an
adapter-kind/Surface/declaration/field-specific diagnostic rather than falling
back to JSON, a generated carrier record, or a handwritten type. The generator
uses normal Haskell type-level reflection plus `Typeable` module/type metadata;
it does not parse source or compiler syntax trees.

The matched 12-core #346 production pilot is retained at
`Config/nix/baselines/production-build/issue-346-operation-local-roster.json`.
Roster `Generated.Action.hi` changed from 152,178,127 to 178,099 bytes and
`.dyn_hi` from 152,178,131 to 178,103 bytes (99.88% reductions and below the
16 MiB budget). The 15-module Roster `.hi`/`.dyn_hi` subtrees each fell 23.99%;
complete app interfaces fell 19.22%, app-lib self size 17.09%, peak RSS 36.45%,
and matched-core wall time fell 20.88%. Generated TypeScript remained
byte-identical, and the private proof was absent from the installed 502-module
library.

The Timesheets family was the representative migration checkpoint. Its
handwritten `Resource` module moved from 35 lines to a 9-line curated facade,
removing all three mechanical bodies and 26 net handwritten lines. Generation
added an 80-line private adapter module and a 14-line feature-local family
association. A single isolated cold focused compile of the facade with
`typecheck Application/Helper/FrontendContract/Surface/Timesheets/Resource.hs`
changed from 22 modules in 9.711 seconds to 25 modules in 9.772 seconds: three
expected modules and 0.061 seconds (+0.6%) in that sample. This checkpoint was
accepted before registering the remaining homes; it is a compile-impact record,
not a benchmark.

Timesheets was also the representative Live migration checkpoint. Its
handwritten `Live` module moved from 38 lines to a 29-line curated facade,
removing all four mechanical constructor bodies and field assembly while
retaining the domain-shaped scope matcher: nine net handwritten lines deleted.
Generation added one 90-line private `.Generated.Live` module; the final bulk
registration emits seven Live modules (1,020 generated lines) alongside the
unchanged seven Resource modules. A paired same-host isolated cold focused
compile of the historical and candidate facades with
`typecheck Application/Helper/FrontendContract/Surface/Timesheets/Live.hs`
changed from 41 modules in 27.023 seconds to 44 modules in 22.979 seconds: the
three expected modules (`Generated.Live`, the feature family module, and the
lightweight association), and -4.044 seconds (-15.0%) in that sample. The module
closure, net deletion, and absence of `Family`/`Core` from the production import
closure were accepted before bulk home registration. This is a checkpoint
record, not a benchmark; cold wall-clock samples on the host were noisy.

The compiled unregistered Live fixture remains at
`Test.Support.FrontendSurfaceAdapterFixture.Generated.Live` and covers
zero-field, parameterized, actor-only, matcher, and collision behavior without
entering the production registry. Production behavior coverage also exercises
zero-field and parameterized Timesheets adapters through the curated facade.

The Action/Intent foundation adds two private unregistered fixture modules:
a 62-line `.Generated.Action` and a 63-line `.Generated.Intent`, each behind its
matching eight-line curated fixture facade. They exercise one cross-kind
same-marker declaration through required, optional, nullable, nested-list,
builder, render-metadata, successful parser, missing, and malformed paths.
Separate fixtures reject same-lane collisions and Action/Intent output-lane
misuse. In isolated cold focused samples using a fresh build directory for each
facade, `typecheck Test/Support/FrontendSurfaceAdapterFixture/Action.hs` loaded
52 modules in 36.908 seconds and the matching `Intent.hs` target loaded 52
modules in 16.118 seconds. These noisy one-sample figures record pre-production
fixture/import impact for #186/#187; they are not benchmarks.

`generateSurfaceAdapterModules` composes Resource, Live, Action, and Intent lane
results, accumulates complete diagnostics, and rejects duplicate physical module
paths before the script writes or removes files. Every lane is mandatory and
complete; empty, partial, or duplicate Action or Intent registrations fail before
a managed module set is exposed. Failure-injection coverage proves a failed
Live, Action, or Intent lane leaves every other existing lane untouched. The
write workflow renders, formats, and typechecks the complete temporary set
before any managed stale deletion or write.

The current shared-file seam is intentionally narrow:
`HaskellAdapter.Core` owns checked conversion, source types, field rendering,
and locality; `HaskellAdapter.Request` owns Action/Intent inventory-to-source
rendering; `HaskellAdapter.Family` owns typed inventory reflection and validation;
and `HaskellAdapter.Generator` owns closed all-kind lane composition. Resource
and Live keep focused renderers because their constructor/matcher semantics and
eligibility differ materially. With every lane mandatory, no partial publication
state is exposed.

### Generator topology simplification (#335)

The selected design deepens the request-generator module at
`HaskellAdapter.Request`. A normal Action or Intent now adds one typed inventory
registration that owns its home and three operation decisions; it no longer
repeats the same family/declaration pair in a separate type-level home list.
Action and Intent still select distinct checked declarations, kind-indexed
layouts, output modules, nominal bundles, generic metadata constructors, and
exact parsers. Inventory validation now hands its already source-resolved
adapter directly to rendering instead of running home/family/source resolution a
second time.

Compared with the #332 checkpoint, the generator foundation moves from 10 files
/ 3,118 LOC to 8 files / 2,916 LOC. `Action`, `Intent`, and `RequestRenderer`
collapse into `Request`; duplicate production request-home inventories are
deleted. The 8 family association files / 156 LOC, 24 generated modules / 3,556
LOC, 24 curated facades / 634 LOC, and generated TypeScript 1 file / 1,671 LOC
are unchanged. Drift output is byte-identical. Profile Action and Roster Intent
focused closures remain exactly 20 and 21 `Application.*` modules respectively;
neither includes `HaskellAdapter.Core`, `Family`, `Registry`, `Request`, or
`Generator`. Existing lane-misuse compile failures, inventory diagnostics,
goldens, and atomic failure-injection tests remain the interface test surface.

Rejected alternatives:

- **One generated module per Surface/family:** fewer physical generated files,
  but Resource/Live declaration-complete reachability and request-operation
  reachability would share imports and Weeder policy. Curated facades would
  pull unrelated lanes into focused runtime closures, reducing depth and
  locality for ordinary feature callers.
- **Keep separate Action/Intent renderers over a shared kernel:** preserves the
  pre-change three-module request interface and duplicate projection path. The
  lane differences are configuration (layout, names, metadata type, parser),
  while kind indices already enforce the meaningful distinction.
- **Build-only generated Haskell:** removes checked-in artifacts but makes code
  generation an ordering prerequisite for normal typecheck/deployment and
  weakens reviewable byte drift. Deterministic checked-in output remains the
  simpler publication contract.
- **Generate the curated facades:** would either expose declaration-complete dead
  operations or require a second consumer inventory, while domain matchers and
  orchestration still need handwritten locality. The existing facades continue
  to earn their interface.

The #191 Profile/Staff checkpoint keeps production Action homes empty while
capturing the first migration boundary. Action/Intent builder, metadata, parser,
diagnostic, and operation-inventory contracts moved out of the former
1,578-line generator spec into the independently registered
`Test.FrontendSurfaceRequestAdapterSpec`; the shared core/composer spec is now
1,186 lines and the focused spec is 739 lines after adding production
characterization coverage. Literal expectations pin all six Profile/Staff
Action names and HTMX metadata. The same seam exercises required text, integer,
and day fields; optional text and boolean fields; optional UUID and text lists;
structured success; declaration-ordered missing/malformed diagnostics; and the
semantic details-versus-preferences selection. Nullable and nested-list shapes
remain compiled only through #185's unregistered fixture because production has
no such Action declaration.

The pre-migration Profile/Staff mechanical boundary is 37 source lines: four
field-bundle bodies occupy 25 lines (13 profile-detail fields, two preference
fields, and the two three-field leave bundles), six generic
`frontendSurfaceAction` expressions live in `Web/View/Profiles/Edit.hs` and
`Web/View/Staff/Edit.hs`, and six generic parser expressions live in
`Web/Staff/ProfileSurfaceRequest.hs` and `Web/Controller/LeaveRequests.hs`.
Domain projection, semantic submission selection, route context, and response
orchestration are deliberately excluded because they remain handwritten. Those
six parsers are part of the repository-wide 33-call Action baseline recorded by
#185.

A test-only checked rendering restricted to the six Profile/Staff declarations
estimates one 233-line private `.Generated.Action` module plus a 39-line curated
re-export facade: 272 added generated/facade lines across two modules. This did
not register partial production homes or materialize either production file. A
single same-host isolated cold compile with a fresh `TYPECHECK_BUILD_DIR` of
`typecheck Web/Staff/ProfileSurfaceRequest.hs` loaded 522 modules in 47.679
seconds. Its closure was 480 `Generated.*` model modules, 38 `Application.*`
modules, and four `Web.*` modules. The complete non-generated closure was:

- `Application.Helper.FrontendContract.{Core,DSL,Interaction,Naming}`;
- `Application.Helper.FrontendContract.Surface.{DSL,Admin,Billing,ContractIR,Diagnostics,Interaction,LeaveRequests,Profile,Reflect,Registry,Request,Roster,SemanticIR,Support,Timesheets,Values}`;
- `Application.Bepis.{Action,Architecture,Controller,Fact,Prelude,Response}`;
- `Application.Helper.{Audit,Conflict,Controller,ControllerAccess,ControllerContext,ControllerSupport,Htmx,Profiling,Telemetry,TimeRules,WeekBoundaries}` plus `Application.Helper.Controller.Input`;
- `Web.Types`, `Web.Routes`, `Web.Controller.Prelude`, and
  `Web.Staff.ProfileSurfaceRequest`.

No `HaskellAdapter` implementation, registry, generator, request renderer, or
future generated Action module appears in that baseline closure. The module and
wall-clock figures are one noisy checkpoint sample, not a benchmark.

#192 published all 48 eligible Action homes in one mandatory set: 18 Admin,
three LeaveRequests, six Profile/Staff, 14 Roster, two Support, and five
Timesheets declarations. It added six private `.Generated.Action` modules
(1,307 lines) and six curated facades (276 lines). The complete managed Haskell
adapter set at that checkpoint was 20 modules: seven Resource, seven Live, and
six Action. Measured against the #191 checkpoint commit over all
changed `Web/**` production callers plus
`Application/Helper/View/Timesheets.hs`, the migration added 262 handwritten
lines and removed 269, for seven net handwritten production-caller lines
deleted. That deliberately modest net retains domain-shaped mappings for
Profile/Staff, Timesheets, and Admin shift-type same-shape bundles instead of replacing them
with opaque wide positional calls. The former 33 generic parser calls and 50
generic metadata calls are zero.

The post-migration operation-identity hardening keeps those mappings while
making their result type operation-polymorphic: each caller supplies its exact
generated builder, and the helper returns that builder's nominal bundle instead
of normalizing it back to one representative operation. The same-shape
production inventory at this seam is:

- all 13 zero-field generated Actions (two Support refreshes, seven Roster
  controls, two LeaveRequests decisions, Admin invite revoke, and Admin Xero
  sync);
- all five Timesheets state Actions;
- the four Admin shift-type create/update/autosave Actions;
- the three one-field Admin roster-group move/toggle Actions and the three
  one-field Admin shift-type move/toggle Actions;
- Admin roster-group create/update;
- Profile/Staff details, preferences, and leave-request pairs; and
- the four drag/drop Roster Intents, including the day-timeline operation.

`FrontendSurfaceWrongActionOperation` and
`FrontendSurfaceWrongIntentOperation` compile-failure fixtures select concrete
members of those groups and prove that a bundle from one operation cannot feed
another. The generator still derives every wrapper from the existing typed home
and checked declaration; no carrier record, consumer source scan, or parallel
operation registry was added.

The paired fresh-build cold compile of
`Web/Staff/ProfileSurfaceRequest.hs` moved from 522 modules in 47.679 seconds to
547 modules in 86.380 seconds: 25 modules (+4.8%) and 38.701 seconds (+81.2%) in
these noisy one-sample measurements. Both closures contained the same 480 IHP
model `Generated.*` modules and four `Web.*` modules; `Application.*` increased
from 38 to 63. The complete 25-module addition was:

- `Application.Helper.FrontendContract.{App,AppShell,AppValues,Htmx,IR,LiveUpdate,LiveUpdateValues,Reflect,Registry,UiRegion,Values}`;
- `Application.Helper.FrontendContract.Surface.{Contracts,Identity,Live,Runtime}`;
- `Application.Helper.FrontendContract.Wire.{Carrier,Json,LiveUpdate}`;
- `Application.Helper.{LiveUpdate.Internal,UiRegion,Url}`; and
- `Application.Helper.FrontendContract.Surface.HaskellAdapter.Association`,
  `Surface.Profile.HaskellAdapter`, `Surface.Profile.Generated.Action`, and
  `Surface.Profile.Action`.

The required isolated cold compile of `Surface.Profile.Action` loaded 50
`Application.*` modules in 37.783 seconds, with no model `Generated.*` or `Web.*`
modules. Its complete closure grouped by module family was:

- `Application.Helper.FrontendContract.{App,AppShell,AppValues,Core,DSL,Htmx,IR,Interaction,LiveUpdate,LiveUpdateValues,Naming,Reflect,Registry,UiRegion,Values}`;
- `Application.Helper.FrontendContract.Surface.{Admin,Billing,ContractIR,Contracts,DSL,Diagnostics,Identity,Interaction,LeaveRequests,Live,Profile,Reflect,Registry,Request,Roster,Runtime,SemanticIR,Support,Timesheets,Values}`;
- `Application.Helper.FrontendContract.Surface.HaskellAdapter.Association`,
  `Surface.Profile.HaskellAdapter`, `Surface.Profile.Generated.Action`, and
  `Surface.Profile.Action`;
- `Application.Helper.FrontendContract.Wire.{Carrier,Json,LiveUpdate}`;
- `Application.Bepis.{Action,Fact,Response}`; and
- `Application.Helper.{LiveUpdate.Internal,Profiling,Telemetry,UiRegion,Url}`.

Neither post-migration closure contains
`Surface.HaskellAdapter.{Core,Family,Generator,Registry,Request}`. The
wall-clock figures are compile-impact records, not benchmarks; the bounded,
feature-owned closure and absence of generator implementation modules are the
acceptance signal.

#187 published all five eligible Intent homes in one mandatory set: four Roster
and one Roster day-timeline declaration. It added one 228-line private
`.Generated.Intent` module and one 33-line curated `Intent` facade. The complete
managed Haskell adapter set is now 21 modules: seven Resource, seven Live, six
Action, and one Intent. Against the #187 baseline commit `96582ff2`, the two
production caller modules added 17 handwritten lines and removed 35, for 18 net caller
lines deleted. Removing the shared publication-state/expiry path while adding
the complete Intent homes changed the Action, Intent, Family, and Registry
modules by 31 additions and 102 deletions, another 71 net lines deleted.
Including the 33-line facade, those foundation and caller changes added 81 and
removed 137 handwritten Haskell lines, for 56 net deleted; the 228 generated
lines are recorded separately. The former five generic parser calls, five
generic form constructors, and two handwritten bundle bodies are absent.

Independent production characterization passed before caller replacement and
continues to pin all five complete bundles, literal DOM-owned form metadata,
successful required/optional text parsing, and declaration-ordered missing and
invalid-UTF-8 diagnostics. Nullable and nested-list behavior remains in the
compiled #185 fixture because no production Intent declares those shapes.

A paired fresh-build cold compile of `Web/RosterWeeks/FrontendSurface.hs` moved
from 555 modules in 51.061 seconds to 557 modules in 88.378 seconds: two modules
(+0.4%) and 37.317 seconds (+73.1%) in these noisy one-sample measurements. Both
closures contained the same 480 model `Generated.*` modules and seven `Web.*`
modules; `Application.*` increased from 68 to 70. The exact additions were
`Surface.Roster.Generated.Intent` and `Surface.Roster.Intent`, with no removals.

The required isolated cold compile of `Surface.Roster.Intent` loaded 50
`Application.*` modules in 37.330 seconds, with no model `Generated.*` or `Web.*`
modules. Its complete closure grouped by module family was:

- `Application.Helper.FrontendContract.{App,AppShell,AppValues,Core,DSL,Htmx,IR,Interaction,LiveUpdate,LiveUpdateValues,Naming,Reflect,Registry,UiRegion,Values}`;
- `Application.Helper.FrontendContract.Surface.{Admin,Billing,ContractIR,Contracts,DSL,Diagnostics,Identity,Interaction,LeaveRequests,Live,Profile,Reflect,Registry,Request,Roster,Runtime,SemanticIR,Support,Timesheets,Values}`;
- `Application.Helper.FrontendContract.Surface.HaskellAdapter.Association`,
  `Surface.Roster.HaskellAdapter`, `Surface.Roster.Generated.Intent`, and
  `Surface.Roster.Intent`;
- `Application.Helper.FrontendContract.Wire.{Carrier,Json,LiveUpdate}`;
- `Application.Bepis.{Action,Fact,Response}`; and
- `Application.Helper.{LiveUpdate.Internal,Profiling,Telemetry,UiRegion,Url}`.

Neither #187 closure contains
`Surface.HaskellAdapter.{Core,Family,Generator,Registry,Request}`. The
wall-clock samples are compile-impact records, not benchmarks; the exact
feature-owned two-module caller increase and bounded facade closure are the
acceptance signals.

#196 split generated request metadata from the mount/live runtime. The focused
`Surface.Request.Runtime` module owns only the opaque `FrontendSurfaceAction`,
`FrontendSurfaceIntentForm`, and `FrontendSurfaceHtmxRequest` metadata types and
the marker-indexed Action/Intent metadata constructors. `Surface.Runtime`
consumes their read-only selectors for HTML rendering but does not re-export the
focused interface. Generated Action/Intent modules import the focused module
directly. Separately, production-registry binding moved out of
`Surface.Reflect` and into `Surface.Contracts`, so feature-local values and
request metadata can use the shared reflection evaluator without loading the
registered Surface catalog.

The deterministic cold-compile capture used a fresh build and log directory for
every target/run. Run the function at baseline fixed point `ba13567d` and again
at the #196 candidate; use separate worktrees when retaining both trees:

```bash
capture_surface_request_closure() {
    run="$1"
    target="$2"
    out="$PWD/.pi/tmp/issue-196-closures/$run"
    rm -rf "$out"
    mkdir -p "$out"
    TYPECHECK_BUILD_DIR="$out/build" \
        bash ./bin/in-env typecheck "$target" >"$out/typecheck.log" 2>&1
    sed -nE \
        's/^\[[^]]+\][[:space:]]+Compiling[[:space:]]+(Application\.[^[:space:]]+).*/\1/p' \
        "$out/typecheck.log" | sort -u | tee "$out/application-modules.txt"
}

capture_surface_request_closure \
    profile \
    Application/Helper/FrontendContract/Surface/Profile/Action.hs
capture_surface_request_closure \
    roster-intent \
    Application/Helper/FrontendContract/Surface/Roster/Intent.hs
```

The post-#193/#195 baseline was 50 `Application.*` modules for each target. Its
exact 47-module common set was:

- `Application.Bepis.{Action,Fact,Response}`;
- `Application.Helper.FrontendContract.{App,AppShell,AppValues,Core,DSL,Htmx,IR,Interaction,LiveUpdate,LiveUpdateValues,Naming,Reflect,Registry,UiRegion,Values}`;
- `Application.Helper.FrontendContract.Surface.{Admin,Billing,ContractIR,Contracts,DSL,Diagnostics,Identity,Interaction,LeaveRequests,Live,Profile,Reflect,Registry,Request,Roster,Runtime,SemanticIR,Support,Timesheets,Values}` plus
  `Surface.HaskellAdapter.Association`;
- `Application.Helper.FrontendContract.Wire.{Carrier,Json,LiveUpdate}`; and
- `Application.Helper.{LiveUpdate.Internal,Profiling,Telemetry,UiRegion,Url}`.

Profile added only `Surface.Profile.{Action,Generated.Action,HaskellAdapter}`;
Roster Intent added only
`Surface.Roster.{Generated.Intent,HaskellAdapter,Intent}`.

The current compiler-observed closures are 20 modules for operation-local Roster
Action, 21 for Profile Action, and 22 for Roster Intent. The latter two retain
their exact 17-module common set:

- `Application.Helper.FrontendContract.{ClosedScalar,Core,DSL,Interaction,Naming}`;
- `Application.Helper.FrontendContract.Surface.{ContractIR,DSL,Diagnostics,LeaveRequests,Reflect,Request,Request.Runtime,Request.Runtime.Internal,SelfServiceLeave,SemanticIR,Values}`; and
- `Application.Helper.FrontendContract.Surface.HaskellAdapter.Association`.

Profile retains only `Surface.Profile` plus
`Surface.Profile.{Action,Generated.Action,HaskellAdapter}`. Roster Intent
retains `Surface.Interaction`, `Surface.Roster`, and
`Surface.Roster.{Generated.Intent,HaskellAdapter,Intent}`. Relative to the
recorded baseline, both targets add `ClosedScalar`, `Surface.Request.Runtime`,
and the shared `Surface.SelfServiceLeave` declaration module. Both remove the shared 31-module
set:

- `Application.Bepis.{Action,Fact,Response}`;
- `Application.Helper.FrontendContract.{App,AppShell,AppValues,Htmx,IR,LiveUpdate,LiveUpdateValues,Reflect,Registry,UiRegion,Values}`;
- `Application.Helper.FrontendContract.Surface.{Admin,Billing,Contracts,Identity,Live,Registry,Runtime,Support,Timesheets}`;
- `Application.Helper.FrontendContract.Wire.{Carrier,Json,LiveUpdate}`; and
- `Application.Helper.{LiveUpdate.Internal,Profiling,Telemetry,UiRegion,Url}`.

Profile additionally removes `Surface.Interaction` and `Surface.Roster` (33
removed, three added, 50 to 20); Roster Intent additionally removes
`Surface.Profile` (32 removed, three added, 50 to 21). Operation-local Roster
Action has no `HaskellAdapter.Association`; its compact additions are
`Surface.Roster.{Action,Generated.Action}`; the shared
`Surface.Request.Runtime.Internal` owns opaque constructors without exporting
them through the public runtime.

Every retained dependency has one request-facade role:

- `ClosedScalar` owns the canonical finite-value projection/parser without
  importing the production scalar registry or generated enum catalog;
- `Surface.DSL`, `Surface.Diagnostics`, and `Surface.Values` own declaration
  lookup, nominal field construction, diagnostics, and read-only serialization;
- `Surface.Request` owns exact parsers and structured field errors;
- `Surface.Request.Runtime`, its constructor-owning `Runtime.Internal` sibling,
  `Surface.Reflect`, and `Naming` own opaque metadata construction and
  marker-derived names;
- `Surface.ContractIR`, `Surface.SemanticIR`, `Core`, and the global
  `DSL`/`Interaction` modules are the canonical reflected metadata model rather
  than a request-specific duplicate IR;
- `HaskellAdapter.Association` supplies the feature family's nominal Surface;
- `Surface.LeaveRequests` and `Surface.SelfServiceLeave` supply the shared leave
  declaration bundles; and
- the Profile or Roster feature modules supply only the selected declarations,
  generated operations, curated facade, and Roster's shared interaction aliases.

The architecture regression check computes transitive membership from generated
source facts and compares these exact sets, not just counts:

```bash
bash ./bin/in-env architecture-surface-request-closure --print-modules
```

It is also part of `architecture-check-fresh`. All three closures exclude the
registered Surface catalog, `Surface.Runtime`, mount/live/wire implementation,
and `Surface.HaskellAdapter.{Core,Family,Generator,Registry,Request}`; Roster
Action also excludes the family association and temporary proof.

Write and verify output with:

```bash
bash ./bin/in-env frontend-surface-adapters
bash ./bin/in-env frontend-surface-adapters-check
```

The check formats a temporary rendering, compares the complete managed module
set, and rejects missing, extra, stale, or unformatted generated files.

## Runtime Implementation

Migrated surfaces expose mount behavior through
`Application.Helper.FrontendContract.Surface.Runtime.SurfaceImpl spec`.
`SurfaceImpl` is the feature-facing runtime value.

For a server-rendered mount whose controllers/views already own fragment
rendering and action routes, use `mkSurfaceImplFromValues`. It is the sole
production constructor and derives the surface name, canonical scope key, exact
scope/mount-state JSON, and live subscription from marker-indexed values in one
step. Build descriptors with `frontendSurfaceMountedFragmentFor`; it derives
fragment identity, the exact target ID, and lazy defaults from the owning
Surface declaration. Every fragment declares one `MountTarget marker fields`;
views render the same declaration through `surfaceFragmentTargetId`. Static and
parameterized target IDs therefore share the reflection naming evaluator and
declaration-ordered typed fields. URLs and protection remain mount-local.

Pass each concrete dynamic or repeated fragment set directly to that constructor
(or a feature helper that calls it). Each mounted fragment stores the opaque
semantic key created by its own Surface/fragment marker; actor planning maps
mounted keys directly and never reattaches a free-text Surface name or selects a
fragment through its target ID. There is no post-construction descriptor
patching and no generic handler/action/intent catalog on `SurfaceImpl`. Real
interaction intent forms are feature-owned marker-indexed values supplied to the
interaction shell; ordinary action routes remain next to their server-rendered
views. Compile-failure tests enforce Surface, marker, field completeness, and
transport opacity rather than ceremonial handler counts.

Render mounts with `renderFrontendSurfaceMount impl body`. This emits
`data-bepis-surface` and `data-bepis-surface-config`. Do not handwrite these
attributes in feature views except in guardrail fixtures. Reflection generates a
surface-discriminated exact `FrontendSurfaceMountConfig` parser. The only mount
properties are `surface`, `scopeKey`, `mountKey`, `fragments`, and
`subscription`; each descriptor contains only `fragmentKey`, `targetId`, `url`,
and `protection`, while a non-null subscription contains only the typed `scope`.
Server `MountState`, load behavior, and derived resync lists must not be added to
the browser envelope without a browser consumer. DOM/config surface disagreement
is an invalid mount and must be reported rather than coerced.

The websocket endpoint, client-id header, and surface config/action/owner DOM
attribute names come from reflected global constants shared by Haskell and
TypeScript. Add or change those values in the frontend contract registry, not as
runtime string literals.

Lazy placeholders must use the
`renderFrontendSurfaceLazyFragmentWithConfig` runtime helper with
`defaultFrontendSurfaceLazyFragmentConfig` when the defaults suffice, so
canonical UI-region attrs, HTMX swap attrs, retry metadata, and
primitive-derived lazy behavior stay Haskell-owned. Use
`customPlaceholderFrontendSurfaceLazyFragmentConfig` when the placeholder markup
already renders its own panel/card chrome, so the outer lazy region stays a
transparent HTMX/region shell instead of visually nesting surfaces. Feature views
may pass root/slot classes in the config; the shared runtime must not infer
layout geometry. Intent/action forms should use the runtime render helpers so
HTMX attributes and hidden fields stay Haskell-owned.

Controllers remain normal IHP mutation entrypoints in this epic. They parse and
authorize params, call feature mutation/read-model code, and render validation
failures or successful actor extras. Successful migrated `FrontendSurface`
mutations should report typed `SurfaceResourceValue` touches using the
feature-owned smart constructors in `Surface.<Feature>.Resource`, while
`Application.Helper.SurfaceResource` owns only `LiveMutationResult` and its
opaque touched-resource set. Mutations then return actor-local semantic
invalidation instructions plus extras. The actor tab and
passive viewers both refresh by resolving semantic scope and fragment keys
through mounted surface metadata and each mount's plain fragment GET URL, so
successful actor responses must not carry authoritative business OOB HTML.

A feature that needs transient mount-local request context may register a
mechanical fragment-request decorator through
`frontend/ts/live-updates/request-context.ts`. The registry is shared across
separately bundled feature and live-update entrypoints; decorators may add only
values encoded by their generated browser-outbound DTO and must leave business
calculation/filtering on the server. Context ownership must be tied to the
concrete configured Surface mount so child refreshes retain it and mount
replacement naturally discards it.

## Live Authorization, Resources, And Fragment Rendering

`FrontendSurface` invalidations are semantic and surface-native:
transport identifies generated kebab-case surface names, generated scope DTOs,
and generated fragment names plus typed params. Haskell emits ready-to-use mount
subscription JSON from `Scope` plus mounted `Fragment ... Live` values;
composition-only parent surfaces omit `Live` fragments and therefore do not
subscribe. The emitted subscription contains the typed scope only. The browser
uses mounted descriptors plus the generated reflected `Live` fragment set for
initial/reconnect resync keys; it must not parse scope keys or switch on
app-specific surface/fragment names.

`Scope` owns websocket subscription identity and authorization. Every scope must
carry exactly one auth marker: `Authorize SomePolicy` for server-checked scopes,
or explicit `NoAuth` for public/test-only scopes. Authorization reflection lowers
to closed `ScopeAuthIR` constructors with the exact required field count. Every
referenced field must be a required UUID; missing, extra, absent, or incorrectly
typed fields fail checked-IR validation. The authorization field list contains
only fields consumed by that policy; other scope-identity fields remain separate
and must still be authorized by their fragment routes. Runtime authorization
pattern-matches those constructors and parses their carried field names; it never
redispatches policy text. `Web.SurfaceInvalidation` derives subscription authorization from
the reflected `RegisteredFrontendSurfaces` metadata; feature code must not add
hard-coded fallback authorization for a surface/scope pair.

Fragments that participate in passive invalidation declare `Live` and then one
invalidation mode. Prefer explicit `DependsOn SomeResource '[ ...sources... ]`,
where each dependency field is sourced with `FromScope ScopeField` or
`FromFragment FragmentField`. Parameterized fragments are the preferred shape for
homogeneous repeated regions that differ mainly by a typed key/section, such as
leave section count/list fragments, timesheet day sections, roster day sections,
or roster rows. The parameter should also be the natural resource boundary so
actor-local `setActorLiveResourcesRefresh` and passive websocket invalidation plan
through the same `DependsOn ... FromFragment ...` declaration. Do not
parameterize unrelated tabs/sections merely because they appear together in a
page; keep distinct fragments when dependencies, permissions, forms, or response
modes differ materially. Use `ResyncOnly` only when a live fragment is refreshed
by reconnect/resync or actor paths and has no passive business-resource
dependency. The generator validates that live fragments have one mode and that
resource field sources are concrete and non-conflicting.

`Resource` declarations live in the type-level surface specs and are discovered
by walking `RegisteredFrontendSurfaces`. The generic marker-indexed constructor
and matcher live in `Application.Helper.FrontendContract.Surface.Resource`;
feature modules such as `Surface.Roster.Resource` and
`Surface.Timesheets.Resource` expose concrete values such as
`rosterWeekResource`, `timesheetDayResource`, or `xeroConnectionResource`.
Mutation/domain code emits only those declared values. The carrier constructor
is internal, and no free resource-name/field constructor, undeclared sentinel,
custom dependency hook, or bridge conversion is supported.

Roster template consumers share three generated Roster Surface resources:
`roster-template-library` is roster-group-scoped, `roster-template` identifies one
saved template, and `roster-template-draft` identifies the effective user's
private global draft. `Surface.Roster.Resource` owns their constructors and typed
matchers; designer/library code must not create parallel resource names or expose
a private draft through a group-only identity.

`RosterTemplateDesignerSurface` owns the isolated designer/reference mount. Its scope carries venue, roster group, and effective user, but it declares no live fragments or ordinary roster mutation intents. A generated reference-target role and closed `compatible` state annotate native GET selection forms; Haskell/controller authority owns selection and confirmation while CSS provides hover/focus treatment and native forms provide keyboard/touch activation.

The ordinary Roster Surface owns its editor-only template library and application interactions. A user-parameterized live library fragment depends on group-library and effective-user draft resources. Generated card/config/form/target/cancel roles, Day/Week drag source refs, Day/whole-week dropzone refs, and typed preview/apply actions are the only browser contract. The roster adapter manages cancellable Day selection mechanics; generic pointer sessions manage drag; both submit the same server-rendered confirmation boundary.

The singular actor/passive planner is generated-data driven:

1. accept exact semantic keys from an actor mount or active subscription;
2. evaluate each key's fragment `DependsOn` declarations from scope/fragment params;
3. intersect those concrete dependency values with touched generated resources;
4. collapse exact duplicates, then use reflected `Contains` paths to drop a
   selected descendant when its matching ancestor is also selected before actor
   delivery or passive broadcast.

Containment matching is transitive and parameter-aware. For repeated fragments,
an ancestor's declared parameter fields must have equal values on the descendant,
so one roster day section does not suppress a row mounted under another day.
Siblings remain independent. Structural wrappers should depend only on dedicated
resources that actually change wrapper-owned structure or state; child-owned
ordinary updates must use narrower resources. Use `ResyncOnly` when no passive
resource changes the wrapper at all. Reusing one broad child resource on the
wrapper would make ancestor-wins normalization correctly avoid overlapping swaps
but unnecessarily replace focus or scroll ownership. Roster uses separate week-
structure, slots-structure, and broad slots-content resources so precise
slot/day changes preserve both the grid frame and day-row slot scroller.

Runtime/domain expansion is separate from static fragment dependency planning.
When a mutation has broad semantic effects, expand it in the producer or a small
feature-owned helper to concrete generated resources before invalidation (for
example, active roster-week resources for roster-affecting leave/staff changes).
Do not encode broad fanout as a `FrontendSurface` custom dependency or fragment
fanout DSL.

Use direct database/read-model rendering first. If profiling later proves
caching is needed, add an explicit feature-owned read-model/cache seam or
`SurfaceImpl` backend with viewer-aware keys, dependency versions, and tests.

`MountState` models Haskell/server view state separately from the live
subscription scope. Keep query-param or future persisted state behind a small
backend seam so changing storage does not change the type-level surface spec.
The generator does not emit browser `MountState` types or mount JSON unless a
future contract adds an actual browser consumer.

## Generated TypeScript Consumption

`frontend/ts/generated/contracts.ts` is backend-owned. Runtime TypeScript should
consume generated types, constants, guards, parsers, encoders, manifests, static
interaction schemas, field names, fragment names, and conflict-policy unions.
Use generated `parseX` at unknown JSON/data boundaries and `encodeX` for outbound
surface DTOs. If TypeScript switches on a generated closed union, use
`assertNever` so `frontend-check` fails when Haskell adds a new variant.

Generic browser code may decorate HTMX requests from the closest mounted surface,
manage disposable sessions/layers, fill generated intent forms, and refetch
mount-local fragments. It must not infer feature URLs, target ids, canonical
field names, surface names, or mutation endpoints.

## Authoring Rules

Production feature surfaces use type-level `FrontendSurface` specs plus
`SurfaceImpl`. Keep one reflected registry, one checked IR, generated mount
parsers, and generated interaction/fragment registries; do not author parallel
mount metadata, registry catalogs, or cross-feature projection caches.

For a new surface or migration:

1. Define the type-level spec and add it to `RegisteredFrontendSurfaces`.
2. Implement `SurfaceImpl` handlers and render mounts with runtime helpers.
3. Move static interaction/action metadata into the spec or shared helper
   aliases, including generated source/dropzone/activation refs and their
   session/intent compatibility.
4. Render role-specific refs with `renderFrontendSurfaceSourceRef`,
   `renderFrontendSurfaceDropzoneRef`, or `renderFrontendSurfaceActivationRef`, and
   render intent forms through `SurfaceImpl`/runtime helpers so URLs, targets,
   swaps, sync, hidden values, and triggers remain server-owned.
5. Render fragments directly from feature read models.
6. Generate contracts and update TypeScript to consume generated surface data.
7. Add/adjust Hspec, frontend, and E2E coverage for mount discovery, duplicate
   mounts, actor-local invalidation, passive invalidation, lazy fragments, and
   interaction behavior as applicable.
8. Add guardrails if the migration removes a legacy path that should not return.


## Architecture Facts And Diagrams

`Surface.Architecture` renders semantic facts from checked production IR. Use
deterministic project commands rather than prose inventories:

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-surface-request-closure --print-modules
printf '%s\n' '{"name":"generated-contracts","args":{"target":"roster"}}' \
  | bash ./bin/in-env architecture-query
```

The generated-contracts query shows the reflection pipeline, per-Surface
semantics, generated contracts, and browser consumers. Source/module scanners
and telemetry remain authoritative for imports, routes, schema, and runtime
traces.

## Verification Authority


The checked reflected IR and runtime round trips own semantic Surface behavior.
Compile-fail fixtures own impossible marker, field, wire, lane, and operation
combinations. Byte-identical generated TypeScript/Haskell checks own complete
rendered output. Architecture queries own generated-facade dependency closure.
`frontend-surface-guardrails` owns only narrow deleted-vocabulary tombstones and
forbidden import edges. `typed-contract-authority-check` owns the final
cross-cutting zero-bypass tombstones: migrated finite `WireText`, handwritten
operation field names, generic production Action/Intent calls, discriminator
envelopes, rendered-enum decisions, and non-empty Weeder baseline. Do not
duplicate checked IR or generated output with broad positive source inventories.

## Verification

Use focused checks while developing and the broader frontend gate before commit:


```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-surface-compile-fail-check
# Focused authoring loop; no argument remains the complete gate:
bash ./bin/in-env frontend-surface-compile-fail-check FrontendSurfaceWrongClosedScalarDomain
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env typed-contract-authority-check
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface" --match "SurfaceDependency" --match "SurfaceGuard"
```

Run feature-specific Hspec and E2E when changing a concrete Surface.
