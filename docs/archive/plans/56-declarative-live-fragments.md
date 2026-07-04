# Declarative Live Fragments

## Goal

Refactor live fragments so Haskell defines live surfaces, fragments, scopes, and refresh behavior declaratively, while JavaScript becomes one generic runtime with reusable policies.

New features should not need a custom JavaScript adapter unless they have genuinely custom browser behavior. Existing regular refresh sections should be easy to upgrade by adding a fragment action, a stable target id, a surface declaration, and an invalidation broadcast.

## Target Design

Add a Haskell-first surface model:

```haskell
data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: Text
    , socketPath             :: Text
    , scope                  :: SurfaceScope
    , resyncFragments        :: [LiveFragmentRef]
    , decorateRequestsWithin :: [Text]
    }
```

Extend fragment metadata so interactive sections can declare browser-side protection policies:

```haskell
data SurfaceFragmentProtection
    = NoProtection
    | FocusedFieldProtection FocusedFieldProtectionConfig
```

Keep `deferUntilBlur` temporarily for compatibility, then migrate roster-style input protection to the explicit policy model.

Views should render one declarative config onto the live owner:

```html
<section data-live-update-surface="{...json...}">
```

The JavaScript runtime should read that config and handle subscriptions, resyncs, HTMX request decoration, invalidation messages, fragment fetching, swapping, version gaps, and protection policies.

## Phase 1: Add Generic Surface Config

Add:

```text
Application/Helper/LiveSurface.hs
```

Responsibilities:

- define `LiveSurfaceConfig`
- encode it to JSON
- provide `liveSurfaceAttrs :: LiveSurfaceConfig -> [(Text, Text)]` or an HSX-friendly helper
- provide constructors for common surfaces and fragment lists
- keep generated JSON stable and covered by tests

Start with support because it is simple:

```haskell
supportLiveSurface =
    mkLiveSurface
        "support"
        SupportPlatformScope
        [ supportAwardRatesSectionFragmentRef
        , supportPublicHolidaysSectionFragmentRef
        ]
```

During transition, render both the old `data-live-update-*` attributes and the new `data-live-update-surface` config.

Add tests for JSON encoding of:

- support surface
- leave requests surface
- timesheet week surface
- roster week surface with protected fragments

## Phase 2: Add Generic JavaScript Adapter

In `static/app-live-updates.js`, add a declarative adapter:

```js
function declarativeSurfaceAdapter() {
  // finds [data-live-update-surface]
  // parses JSON
  // validates scope
  // subscribes
  // resyncs listed fragments
  // decorates HTMX requests inside configured selectors
}
```

Do not remove the existing feature adapters yet.

Generic behavior:

- `collectSubscriptions()` reads all declarative surfaces
- `resync()` refreshes `surface.resyncFragments`
- `shouldDecorateRequest()` checks `decorateRequestsWithin`
- invalidation handling remains unchanged because server invalidation already sends `LiveFragmentRef`s
- invalid JSON should be reported safely without breaking all live updates

Skip old adapters for owners that already have `data-live-update-surface`, so migration can happen one surface at a time.

## Phase 3: Migrate Simple Surfaces

Migrate surfaces that need no custom browser logic:

1. Support
2. Leave requests
3. Admin invites
4. Admin slot names

For each surface:

- define a feature-local `*LiveSurface`
- replace scattered `data-live-update-*` attributes with `liveSurfaceAttrs`
- keep fragment `id` and `data-live-update-url` where useful
- remove the matching custom JavaScript adapter once tests pass

Expected JavaScript deletion:

- most of `supportAdapter`
- most of `leaveRequestsAdapter`
- most of `adminInvitesAdapter`
- most of `adminSlotNamesAdapter`

Tests:

- existing Hspec controller tests continue to pass
- rendered pages include `data-live-update-surface`
- HTMX fragment responses still return the expected stable target ids

## Phase 4: Migrate Timesheets

Timesheets currently discovers mounted day sections in JavaScript. Move that declaration to Haskell.

Instead of JavaScript scanning:

```js
ownerEl.querySelectorAll('[data-timesheet-day-offset]')
```

the Haskell view should emit:

```json
"resyncFragments": [
  { "targetId": "timesheet-day-0", "url": "...dayOffset=0" },
  { "targetId": "timesheet-day-1", "url": "...dayOffset=1" }
]
```

Dynamic invalidations from the server can still send individual day-section fragment refs. The generic runtime already handles those because invalidation messages carry exact fragment refs.

## Phase 5: Extract Fragment Protection Policies

Replace roster-specific protection code with generic policies.

Current behavior is effectively:

```text
if fragment says deferUntilBlur
and target contains focused .slot-note-input
then queue refresh until focusout
and preserve field value across swap
```

Make that a reusable policy:

```json
"protectionPolicy": {
  "kind": "focused_field",
  "activeSelector": ".slot-note-input:focus",
  "fieldKeyAttr": "data-roster-field-key",
  "fieldNameFallback": true,
  "containerSelector": "tr[data-roster-row]"
}
```

JavaScript should expose a small registry:

```js
const protectionPolicies = {
  focused_field: focusedFieldProtection()
};
```

This makes the behavior reusable for future editable tables, including timesheets, pay-item editing, staff grids, and inline admin configuration.

## Phase 6: Split Roster Into Declarative Sub-Surfaces

Keep roster domain logic in Haskell, but make browser wiring declarative.

Define:

```haskell
rosterWeekLiveSurface ::
    Id Venue ->
    Id RosterGroup ->
    Int ->
    LiveSurfaceConfig

rosterGroupConfigLiveSurface ::
    Id Venue ->
    Id RosterGroup ->
    LiveSurfaceConfig
```

`rosterWeekLiveSurface` should declare base resync fragments:

- roster content
- staff panel

Dynamic server invalidations still send:

- row fragment
- day section fragment
- content fragment
- staff panel fragment

Use protection policies for:

- roster content
- roster row fragments
- any day sections that can contain active editable fields

Roster should no longer own generic subscription, request decoration, version, queue, or protection mechanics.

## Phase 7: Remove Legacy Adapter Code

Once all existing surfaces use `data-live-update-surface`:

- remove feature-specific JavaScript adapters
- keep only the declarative adapter
- keep the reusable protection policy registry
- keep generic websocket, queue, resync, and swap runtime
- remove old `data-live-update-scope-kind`, `data-live-update-venue-id`, and related attributes where no longer used

The remaining JavaScript should be shaped like:

```text
runtime
  websocket lifecycle
  subscription diffing
  invalidation handling
  fragment fetch/swap
  version gap handling
  HTMX request decoration
  policy registry

policies
  focused_field
  preserve_scroll later if needed
```

## Phase 8: Document The Adoption Pattern

Update `AGENTS.md` and `Web/View/AGENTS.md` with the standard pattern for turning a regular refresh section into a live fragment:

1. Create a fragment render action returning only the section HTML.
2. Give the section a stable `id`.
3. Define a `LiveFragmentRef`.
4. Define a `LiveSurfaceConfig`.
5. Render `liveSurfaceAttrs surface` on the owner shell.
6. On mutation or job completion, call `broadcastLiveInvalidation scope sourceClientId [fragmentRef]`.
7. Add Hspec coverage for the HTMX fragment response and surface config rendering.

## Suggested Order

1. Add Haskell `LiveSurfaceConfig` and JSON tests.
2. Add generic declarative JavaScript adapter.
3. Migrate support first.
4. Migrate leave and admin simple surfaces.
5. Migrate timesheets.
6. Add generic protection policy support.
7. Migrate roster.
8. Delete legacy adapters and old attributes.
9. Document the pattern.

## Success Criteria

- Adding a simple new live section requires Haskell, view, and controller changes only.
- Existing support, leave, admin, timesheet, and roster live updates continue to pass tests.
- Roster input protection still works.
- Websocket invalidation payloads remain structural, not rendered HTML.
- Generic JavaScript runtime has no feature names except optional policy names.
- New regular refresh sections can be upgraded by declaring a surface and fragment refs.
