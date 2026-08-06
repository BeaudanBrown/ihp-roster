# Live Update And Live Surface Specification

This is the durable contract for `FrontendSurface` freshness across Haskell
mutations/controllers, server fragments, websocket transport, and the generic
browser runtime.

## Delivery Contract

Server-rendered HTML is authoritative. A resource-backed migrated mutation
reports typed changed resources. One dependency planner selects/coalesces
semantic fragment keys for both the actor's mounted keys and passive viewers'
subscriptions. The actor receives a local refresh trigger plus requester-only
extras; passive viewers receive websocket invalidations. Each browser refetches
its own authorized plain fragment GET URL.

Transport carries semantic scope/fragment keys only—never executable URLs,
targets, selectors, or protection policy. A tab uses one websocket connection
with many authorized logical-scope subscriptions. Fragment routes enforce the
same authorization and visibility as full-page routes.

Validation failures rerender the submitted form/dialog directly. Successful
migrated responses do not carry authoritative business OOB HTML; OOB remains for
extras such as toasts/dialog cleanup. Fragment GET responses contain exactly the
target node.

## Declaration And Runtime Seams

Production mounts are declared in `RegisteredFrontendSurfaces`, implemented by
`SurfaceImpl`, and rendered through `renderFrontendSurfaceMount`. The exact
generated mount parser accepts only Surface identity, scope key, mount key,
fragment descriptors, and optional subscription. Descriptors carry semantic key,
local target, URL, and protection. Unknown/mismatched fields are rejected rather
than coerced. Server mount state, load policy, and duplicate resync lists stay
outside browser config.

A scope declares one checked authorization policy (or explicit public/test-only
`NoAuth`) and required UUID fields. Runtime authorization derives from registered
checked metadata, never feature-name or text dispatch. Browser-supplied keys are
assertions, not authority.

Live fragments declare exactly one mode:

- `DependsOn` maps fields from typed scope/fragment identity to a Resource.
- `ResyncOnly` participates in reconnect/explicit actor refresh but has no
  passive business dependency.

See `Application/Helper/FrontendContract/Surface/README.md` for authoring and
`Application/Helper/Interaction.SPEC.md` for disposable-session conflicts.

## Resources, Planning, And Mutations

`Application.Helper.SurfaceResource` is the business-mutation boundary.
Mutations return `LiveMutationResult` with opaque `SurfaceResourceValue`s built
by `Surface.<Feature>.Resource`; mutation modules own writes, audit/version side
effects, old/new scope comparison, and passive invalidation together.
Controllers parse/authorize and choose response extras; they do not issue a
second passive broadcast.

`Surface.DependencyPlanner` is the singular pure actor/passive planner. It
matches concrete resources to exact mounted/subscribed semantic keys using
checked `DependsOn` metadata, collapses duplicates, and applies typed containment
so a selected ancestor suppresses its matching descendant while siblings and
different parameters remain independent.

Broad domain effects expand to concrete resources in the producer or a focused
feature helper, bounded by active scopes before cold historical queries. The
generic planner contains no feature switches, custom dependencies, bridge
conversions, or fanout callbacks. Background jobs use the same touched-resource
boundary without request context.

`setActorLiveResourcesRefresh` plans resource-backed actor updates.
`setActorLocalFragmentsRefresh` is limited to requester-local workflows with no
shared resource change. Direct raw transport/broadcast helpers remain inside
`Web.SurfaceInvalidation` and `Application.Helper.LiveUpdate.Runtime`.

## Browser Runtime And Protection

Generated TypeScript owns exact scope/key/mount/message parsing and canonical key
identity. Runtime modules under `frontend/ts/live-updates/` separately own mount
reconciliation, subscriptions, connection/reconnect, invalidation/version
routing, request decoration, refetch/swap, focus protection, and diagnostics.
`app-live-updates.ts` remains orchestration-only.

Incoming keys resolve only against matching local mounted descriptors. There is
no URL/target fallback. Same-scope subscriptions merge; invalidations may select
multiple keys/mounts. Nested mount lifecycle follows current DOM recursively so
new children initialize, removed descendants dispose, and subscription state
matches mounted scopes.

`focus.ts` is the sole focused-field replacement owner. It applies the exact
Haskell-declared protection, keeps only the latest deferred refresh, refetches on
blur, and restores configured field state. Replace-policy fragments refresh
immediately. Reconnect/version-gap resync uses the same path and protection.

UI-region lifecycle is opt-in only for server-declared fragment roots. Ordinary
forms, dialogs/pickers/toasts, navigation swaps, autosave controls, and one-off
HTMX snippets do not become regions without a typed Haskell fragment contract.
TypeScript does not infer regions from routes, targets, classes, or names.

## LiveBus Contract

The `LiveBus` interface exported by `Application.Helper.LiveUpdate.Runtime` owns
subscriptions, monotonically increasing versions per scope, active-scope
discovery, and key-only broadcasts.
The current in-memory implementation may be replaced, but distributed transports
must preserve those semantics and server-side authorization.

## Extension Rules

Add a live surface only when another actor/tab/job can stale mounted DOM. New
fragment actions use the owning `SurfaceImpl` handler. Do not add feature-specific
JavaScript for normal subscribe, resync, refetch, dedupe, nested reconciliation,
or focus protection; do not add compatibility mount formats or fallback auth.

For a mutation: declare Resources and fragment dependencies, emit focused typed
resources, route passive updates through the mutation boundary, and test planning,
authorization, actor response, and passive delivery at their canonical seams.

## Architecture And Verification

Use deterministic source-derived reports instead of prose inventories:

```bash
printf '%s\n' '{"name":"realtime-coverage","args":{"surface":"all","detail":"summary"}}' \
  | bash ./bin/in-env architecture-query
printf '%s\n' '{"name":"realtime-flow","args":{"action":"UpdateRosterSlotAction"}}' \
  | bash ./bin/in-env architecture-query
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "LiveUpdate" --match "SurfaceInvalidation" --match "SurfaceDependency" --match "MutationBoundary"
bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

Use profiling commands only for performance diagnosis; their output is evidence,
not a correctness gate.
