# Live Fragment Cookbook

Use this checklist when adding or changing a collaborative server-rendered
fragment. Keep the browser runtime generic: Haskell owns scopes, target ids,
URLs, authorization, and protection policy.

## Vocabulary

- **Surface**: the stable mounted owner that subscribes to one live scope via
  `data-live-update-surface`.
- **Scope**: the authorized logical data slice, such as one roster week or one
  timesheet week. A scope is not a page name.
- **Fragment**: a feature-local enum value that maps to one refreshable DOM
  target and one GET URL.
- **Containment path**: server-only metadata that describes DOM ownership among
  selected fragments. Parent/child overlaps collapse to the parent; siblings are
  preserved.
- **Wire fragment**: the self-describing transport payload derived from a typed
  fragment. Feature code should not construct it directly.
- **Actor response**: the immediate HTMX response for the browser that made the
  mutation.
- **Passive invalidation**: the websocket message that tells other mounted
  browsers to refetch authorized fragments.
- **Projection**: a cached server render snapshot used when a fragment can be
  regenerated from the same read model.
- **Interaction capability**: optional typed metadata attached to the same
  surface origin for disposable UI layers, user intents, generated HTMX intent
  forms, and live-fragment conflict policy. The durable interaction contract is
  `Application/Helper/Interaction.SPEC.md`.
- **Disposable layer**: a Haskell-declared client-owned region for temporary UI
  such as drag previews, resize ghosts, selection rectangles, context menus, or
  command overlays. It is not authoritative and must be safe to clear.
- **Intent form**: a Haskell-rendered HTMX form for a typed committed user
  intent. TypeScript fills generated hidden fields and dispatches the generated
  trigger; it must not construct persistence URLs.

The living interaction contract is `Application/Helper/Interaction.SPEC.md`.
Use it for typed surface/layer/intent/form/conflict-policy details; this
cookbook remains the checklist for live fragments.

## Preferred Simple Surface Path

For a small current-venue surface with one or more static fragments, prefer the
refined descriptor helpers instead of hand-writing the full
`TypedLiveSurfaceDefinition` record:

```haskell
adminExampleLiveSurfaceDefinition ::
    (?context :: ControllerContext) =>
    TypedLiveSurfaceDefinition AdminExampleSurface () AdminExampleLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminExampleLiveSurfaceDefinition =
    adminExampleLiveSurfaceDefinitionForVenue currentVenueScopeId

adminExampleLiveSurfaceDefinitionForVenue ::
    UUID ->
    TypedLiveSurfaceDefinition AdminExampleSurface () AdminExampleLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminExampleLiveSurfaceDefinitionForVenue surfaceVenueId =
    currentVenueUnitScopeSurfaceForVenue
        "admin-example"
        surfaceVenueId
        adminExampleVenueScope
        RequireCurrentVenueAdmin
        [ staticLiveFragmentDescriptor
            AdminExampleFragment
            AdminExampleWireFragment
            "admin-example-fragment"
            (pathTo ShowAdminExampleFragmentAction)
            (const (liveFragmentDependsOn (AdminExampleResource surfaceVenueId) []))
        ]

adminExampleVenueScope :: VenueLiveUpdateScope
adminExampleVenueScope =
    venueLiveUpdateScope
        AdminExampleScope
        (\case
            AdminExampleScope { venueId } -> Just venueId
            _ -> Nothing)
```

Use `currentVenueUnitScopeSurface` when no context-free/test/sample definition is
needed. Use the `...ForVenue` form when `Web.LiveSurfaceRegistry` should derive
manifest metadata from the typed definition without a request context.

For a fragment whose URL depends on a local key, keep the URL explicit with
`liveFragmentDescriptor`:

```haskell
liveFragmentDescriptor
    AdminInvitesFragment
    (\key ->
        mkSurfaceFragmentRef
            AdminInvitesWireFragment
            "admin-invites-fragment"
            (appendQueryParams (pathTo ShowAdminInvitesFragmentAction) (inviteQuery key)))
    (const (liveFragmentDependsOn (AdminInvitesResource surfaceVenueId) []))
```

For focused-field protection or nested fragments, compose descriptor modifiers:

```haskell
staticLiveFragmentDescriptor fragment wireKey targetId url dependencies
    |> liveFragmentDescriptorWithFocusedProtection focusProtection
    |> liveFragmentDescriptorWithPath ["parent-fragment", targetId]
```

For multi-fragment surfaces, declare one `staticLiveFragmentDescriptor` or
`liveFragmentDescriptor` per feature-local fragment and let the descriptor lower
them into default resync fragments and decorate selectors. Complex surfaces such
as roster or timesheets may still use the full `TypedLiveSurfaceDefinition` or
projection helpers where they need custom candidate fragments, containment,
interaction capability, or projection behavior.

## Add A Fragment

1. Add feature-local closed ADT constructors, for example
   `RosterProjectionRow` or `TimesheetProjectionDaySection`. Do not model
   fragment selectors as free `Text`; parse external section/query values into
   the closed fragment type first.
2. Map that constructor with `staticLiveFragmentDescriptor` when the fragment has
   a fixed wire key, target id, URL, and dependency function. Use
   `liveFragmentDescriptor` only when the ref is key-dependent, such as query
   parameters derived from the surface key.
3. Give the descriptor a stable `targetId`, canonical fragment GET URL,
   protection policy, and containment path. Use
   `liveFragmentDescriptorWithPath` when the target is nested inside another
   live fragment target; otherwise the default path is the target id.
4. Declare the fragment's dependency intent in the same descriptor with
   `liveFragmentDependsOn` for passive `LiveResource` dependencies or
   `liveFragmentResyncOnly` when the fragment is only refreshed by resync/actor
   paths.
5. Add or reuse a fragment GET action that renders the exact DOM node named by
   the `targetId` and no sibling live-fragment targets.
6. Serve the GET action with `serveTypedLiveFragment` and the same typed surface
   definition that created the fragment contract.
7. Render `data-live-update-surface={liveSurfaceConfigJson surface}` on a
   stable owner shell, where `surface` comes from `mkTypedDefinedLiveSurface`.
8. Register the surface in `Web.LiveSurfaceRegistry` so touched resources can be
   matched to subscribed scopes and fragments. Prefer
   `manifestDescriptorFromTypedSurface` for descriptor-backed surfaces with a
   sample key so the generated TypeScript manifest follows the typed definition.
9. Make the business mutation return touched resources and call
   `invalidateTouchedResources` or `invalidateTouchedResourcesWithoutContext`
   after the write commits.
10. For HTMX actors, set requester-local refresh triggers with
   `setTypedLiveSurfaceActorRefresh` only when the actor response needs an extra
   client refetch.
11. Add contract coverage for the surface config, dependency intent, fragment
   target, fragment URL, containment behavior, default resync fragments, and
   fragment GET target.

## Safety Rules

- Do not hand-build websocket JSON, raw `LiveUpdateWireFragment` values, or raw
  actor-refresh payloads in feature modules.
- Do not make `static/app-live-updates.js` infer target ids, URLs, scopes, or
  protection policies from compact fragment keys.
- Do not add feature-specific JavaScript for generic subscribe, reconnect,
  resync, refetch, dedupe, swap, or focused-field protection behavior.
- Prefer broad but safe fragments over stale DOM. Let typed-surface containment
  normalization remove duplicate and parent/child refs during actor and passive
  invalidation planning.
- Use active-scope discovery for indirect fanout mutations so closed historical
  pages do not force unnecessary database work.
- Do not add feature-level passive broadcast or refresh helpers. Passive viewer
  updates flow from touched `LiveResource` values through `Web.LiveSurfaceRegistry`.
- Do not handwrite interaction `data-bepis-*` attrs, disposable layer mounts, or
  intent HTMX forms in feature views. Interaction markup should be generated
  from typed Haskell contracts so duplicate/moved surface mounts keep valid
  target ids and form attributes.

## Review Checklist

- The fragment enum is local to the feature and uses closed constructors rather
  than free-text selectors.
- The typed surface definition is registered in `Web.LiveSurfaceRegistry` when
  websocket authorization needs it.
- The rendered shell has stable `data-live-update-surface` metadata.
- The fragment GET action returns plain target HTML, not actor-only OOB wrappers
  or sibling live-fragment targets.
- The actor path refreshes only the requester; passive updates are derived from
  touched resources and the `liveFragmentDependsOn` declarations in each
  `FragmentContract`.
- Tests cover the typed mapping, containment behavior, and the fragment endpoint
  authorization.
