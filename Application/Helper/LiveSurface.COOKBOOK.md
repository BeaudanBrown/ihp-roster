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

## Add A Fragment

1. Add a feature-local fragment constructor, for example
   `RosterProjectionRow` or `TimesheetProjectionDaySection`.
2. Map that constructor in the feature's `TypedLiveSurfaceDefinition` with a
   stable `targetId` and canonical fragment GET URL.
3. If the fragment target is nested inside another live fragment target, declare
   a containment path with `surfaceFragmentRefWithPath`; otherwise the default
   path is the target id.
4. Add or reuse a fragment GET action that renders the exact DOM node named by
   the `targetId` and no sibling live-fragment targets.
5. Authorize the GET action with `ensureTypedLiveSurfaceAuthorized` and the same
   typed surface definition that created the fragment ref.
6. Render `data-live-update-surface={liveSurfaceConfigJson surface}` on a
   stable owner shell, where `surface` comes from `mkTypedDefinedLiveSurface`.
7. Add `typedSurfaceDependsOn` entries that describe the semantic
   `LiveResource` values read by each fragment.
8. Register the surface in `Web.LiveSurfaceRegistry` so touched resources can be
   matched to subscribed scopes and fragments.
9. Make the business mutation return touched resources and call
   `invalidateTouchedResources` or `invalidateTouchedResourcesWithoutContext`
   after the write commits.
10. For HTMX actors, set requester-local refresh triggers with
   `setTypedLiveSurfaceActorRefresh` only when the actor response needs an extra
   client refetch.
11. Add contract coverage for the surface config, dependencies, fragment target,
   fragment URL, containment behavior, default resync fragments, and fragment GET
   target.

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

## Review Checklist

- The fragment enum is local to the feature.
- The typed surface definition is registered in `Web.LiveSurfaceRegistry` when
  websocket authorization needs it.
- The rendered shell has stable `data-live-update-surface` metadata.
- The fragment GET action returns plain target HTML, not actor-only OOB wrappers
  or sibling live-fragment targets.
- The actor path refreshes only the requester; passive updates are derived from
  touched resources and `typedSurfaceDependsOn`.
- Tests cover the typed mapping, containment behavior, and the fragment endpoint
  authorization.
