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
3. Add or reuse a fragment GET action that renders the exact DOM node named by
   the `targetId`.
4. Authorize the GET action with `ensureTypedLiveSurfaceAuthorized` and the same
   typed surface definition that created the fragment ref.
5. Render `data-live-update-surface={liveSurfaceConfigJson surface}` on a
   stable owner shell, where `surface` comes from `mkTypedDefinedLiveSurface`.
6. After a mutation commits, broadcast typed fragments with a feature refresh
   helper such as `refreshRosterFragments` or `refreshTimesheetFragments`.
7. For HTMX actors, also set an actor refresh trigger with the shared
   broadcast-and-actor helper or the feature wrapper around it.
8. Add contract coverage for the surface config, fragment target, fragment URL,
   default resync fragments, and fragment GET target.

## Safety Rules

- Do not hand-build websocket JSON, raw `LiveUpdateWireFragment` values, or raw
  actor-refresh payloads in feature modules.
- Do not make `static/app-live-updates.js` infer target ids, URLs, scopes, or
  protection policies from compact fragment keys.
- Do not add feature-specific JavaScript for generic subscribe, reconnect,
  resync, refetch, dedupe, swap, or focused-field protection behavior.
- Prefer broad but safe fragments over stale DOM. For hot row churn, coalesce in
  Haskell before broadcasting.
- Use active-scope discovery for broad fanout mutations so closed historical
  pages do not force unnecessary database work.

## Review Checklist

- The fragment enum is local to the feature.
- The typed surface definition is registered in `Web.LiveSurfaceRegistry` when
  websocket authorization needs it.
- The rendered shell has stable `data-live-update-surface` metadata.
- The fragment GET action returns plain target HTML, not actor-only OOB wrappers.
- The actor path and passive path refresh compatible fragments.
- Tests cover the typed mapping and the fragment endpoint authorization.
