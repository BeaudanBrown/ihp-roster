# Controller Guidelines

## Reference
Read `/home/beau/documents/projects/ihp/Guide/controller.markdown` before implementing any controller logic.

## Creating a New Controller

Every controller requires changes in **four files** (missing any will cause compile errors):

1. **`Web/Types.hs`** — Define the controller type:
   ```haskell
   data PostsController
       = PostsAction
       | NewPostAction
       | ShowPostAction { postId :: !(Id Post) }
       | CreatePostAction
       | EditPostAction { postId :: !(Id Post) }
       | UpdatePostAction { postId :: !(Id Post) }
       | DeletePostAction { postId :: !(Id Post) }
       deriving (Eq, Show, Data)
   ```

2. **`Web/Routes.hs`** — Add AutoRoute:
   ```haskell
   instance AutoRoute PostsController
   ```

3. **`Web/FrontController.hs`** — Mount the controller (add import + parseRoute):
   ```haskell
   import Web.Controller.Posts
   -- ...
   instance FrontController WebApplication where
       controllers =
           [ startPage WelcomeAction
           , parseRoute @PostsController
           ]
   ```

4. **`Web/Controller/Posts.hs`** — Implement actions:
   ```haskell
   module Web.Controller.Posts where
   import Web.Controller.Prelude

   instance Controller PostsController where
       action PostsAction = do
           posts <- query @Post |> fetch
           render IndexView { .. }
       action NewPostAction = do
           let post = newRecord
           render NewView { .. }
       action CreatePostAction = do
           let post = newRecord @Post
           post
               |> buildPost
               |> ifValid \case
                   Left post -> render NewView { .. }
                   Right post -> do
                       post <- post |> createRecord
                       redirectTo PostsAction
   ```

## Common Patterns

- Always import `Web.Controller.Prelude` — it re-exports everything needed
- Keep IHP as the controller framework boundary. Bepis-specific action
  semantics are introduced through `runBepis` inside normal IHP `beforeAction`
  and `action` definitions, not through a custom router or parallel controller
  lifecycle. Delegate action bodies near the top with the bound action value and
  operation kind, e.g. `action currentAction@ShowThingAction { thingId } = runBepis currentAction BepisPageAction do`.
- Use `param @Type "name"` only when a missing or malformed value should abort the action. For form fields, prefer record builders with `fill`, explicit `requireParam` checks for required fields, and `ifValid` rerender branches.
- `fill` attaches parser errors to fields, but missing params are ignored. Required dates, ids, numbers, and text fields must be checked server-side; do not rely on HTML `required`, hidden fields, or select options.
- Normalize user text in builders (`normalizeTextField`, `normalizeMaybeTextField`, `requiredBoundedTextField`) before saving. Trim required text, convert blank optional text to `Nothing`, and apply max lengths that match schema constraints.
- Parse user-controlled ids with total parsers such as `parseUUIDText` plus model-specific wrappers. After parsing, query by current venue/tenant before using the id; malformed and cross-venue ids should rerender validation or produce controlled 4xx/redirect responses, never 500s.
- Use `fetch`, `fetchOne`, `fetchOneOrNothing` to run queries
- Use `redirectTo SomeAction` after mutations
- Use `render ViewName { .. }` with RecordWildCards to pass data to views
- Use `buildPost` pattern for form validation (see `/home/beau/documents/projects/ihp/Guide/validation.markdown`)
- Access current user with `currentUser` (requires auth setup)

## Navigation Controller Pattern
- Keep `RosterWeeksAction` as the canonical "this week" redirect endpoint.
- Week navigation should remain URL-driven via `ShowRosterWeekAction { weekOffset }`.
- When a page supports HTMX week-shell swaps, keep the same canonical routes and branch inside the action: full `render` for normal requests, `respondHtml` fragment for HTMX requests.
- If an HTMX request hits a redirect-style reset action such as `RosterWeeksAction`, prefer returning the target fragment and set `HX-Push-Url` to the canonical `Show...Action` path instead of relying on an AJAX redirect.
- For planned modules (e.g. timesheets/admin), scaffold lightweight placeholder controllers/views/routes early so header links are always valid.

## State Transition Pattern
- For status transitions with side effects (e.g. leave approval triggering roster conflict refresh), wrap the update + side-effect hook in `withTransaction` so both commit atomically.

## Overlay Controller Pattern
- Prefer dedicated HTMX dialog-fragment actions for in-place workflows instead of `setModal` + page jump.
- Recommended shape:
  - GET dialog action reads `weekOffset` or other context params and `respondHtml` with dialog fragment only
  - POST/PATCH dialog submit action re-renders the dialog fragment on validation failure
  - successful submit returns only the updated page fragment(s) needed by the current screen plus any out-of-band dialog or toast updates
- Keep `setModal` only as an explicit fallback when a workflow truly needs non-HTMX behavior.
- Reuse the same form/view helper for initial dialog render and validation rerender so field errors stay localized to the shared dialog mount.
- If a workflow mutates roster or timesheet data, return the smallest updated fragment possible (`#roster-content`, row OOB fragments, or a single day section), not a full page redirect.
- Only one workflow dialog should be active at a time. Utility pickers are a separate overlay lane and must not reuse the workflow dialog mount.

## Live Fragment Pattern
- For collaborative pages, split delivery paths:
  - actor response returns immediate HTMX fragments/OOB swaps
  - cross-viewer updates flow from mutation-emitted `LiveResource` touches through `Web.LiveSurfaceRegistry`; feature-local fragment enums still point to dedicated GET fragment actions
- Declare ordinary live surfaces from Haskell with `Application.Helper.LiveSurface.TypedLiveSurfaceDefinition`; render them through `mkTypedDefinedLiveSurface` + `liveSurfaceConfigJson`. The browser runtime discovers `data-live-update-surface` and owns subscription, request decoration, resync, refetch queueing, swapping, and reusable protection policies.
- Typed fragment GET actions should use `serveTypedLiveFragment` with the same surface key and definition that produced the fragment contract. Websocket subscription authorization must be registered in `Web.LiveSurfaceRegistry`; do not fall back to raw scope authorization.
- Treat scopes as authorized logical data slices, not pages. A mutation may invalidate multiple scopes, and only a subset of fragments within each scope.
- Prefer one websocket connection per browser tab/client with many active scope subscriptions instead of one socket per page.
- Keep typed fragment mappings explicit (`targetId`, `url`, defer/swap metadata) so the transport stays structural and controllers do not need to know mounted DOM state.
- Keep reconnect semantics explicit in the transport: each scope should expose a monotonic version, subscribe commands may include the client's `lastSeenVersion`, and the server should tell the client when a full scope resync is required instead of assuming no invalidations were missed.
- Keep fragment GET actions authorized with the same venue/visibility rules as the full page; do not expose restricted fragments just because the websocket payload names them.
- Use `invalidateTouchedResources` after the business transaction commits so the acting tab's `X-Live-Update-Client-Id` is carried by the registry broadcast and the client can suppress its own invalidation echo.
- Do not broadcast affected scopes directly from controllers or feature modules. For fan-out mutations that could touch many roster weeks or other cold surfaces, add active-scope-bounded expansion in `Web.LiveResourceInvalidation`. Closed pages should rely on fresh HTTP rendering unless the feature explicitly needs durable missed-update semantics.
- When a slot mutation can change conflict state across multiple rows, it is acceptable for the actor response to return a full `#roster-content` OOB refresh instead of trying to keep actor-side row patches perfectly minimal.
- Keep the roster week shell subscribed even when the week is empty or hidden so create/copy/publish transitions can invalidate passive viewers already sitting on that offset.
- For server-mutating UI that can leave another mounted copy stale, use the live-fragment path by default while keeping the actor path immediate. Add the controller surface in this order: feature-local fragment enum, typed surface definition with `typedSurfaceFragmentContract`, explicit `liveFragmentDependsOn` or `liveFragmentResyncOnly` intent, registry registration, fragment GET action through `serveTypedLiveFragment`, rendered surface metadata, mutation touched resources plus post-commit invalidation, actor-path HTMX response, Hspec contract coverage for config/target/auth/dependency drift, then Playwright coverage when browser behavior such as resync, focus protection, or no-full-page navigation is part of the feature.
- Successful actor HTMX responses for typed live surfaces should use `respondWithTypedLiveSurfaceFragments` when the feature has a shared read model, so actor OOB swaps and passive live refetches share the same fragment enum and containment normalization. Keep validation failures as direct form/dialog rerenders, and keep fragment GET actions plain target-node responses rather than OOB wrappers.

## Bepis Runtime Fact Pattern
- Do not add descriptive mutation metadata at controller call sites. Facts come
  from helpers that perform real effects: authorization helpers emit scope
  facts, audit/version helpers emit audit facts, live invalidation helpers emit
  live facts, and response helpers emit response facts.
- Controller code should stay boring: `runBepis currentAction BepisMutationAction do`,
  then call the normal Bepis-owned helper/mutation/response functions. If a new
  effect matters for architecture, telemetry, or tests, make the helper emit a
  typed `BepisFact`; do not add a parallel label beside the helper call.
- Do not hide business semantics in broad typeclass instances. Keep real effect
  helpers visible at the call site unless the behavior is purely mechanical and
  intrinsic to the data type.

## Typed Interaction Controller Pattern
- Typed interaction work is planned under `docs/workstreams/typed-interaction-surfaces.md` and `ir-jsyd`. Controllers should not add ad hoc JSON/fetch mutation endpoints for interaction UI when a Haskell-rendered HTMX intent form can own the route, method, target, swap, and validation boundary.
- Interaction intent actions should parse opaque string tokens from generated hidden form fields with total helpers, authorize venue/scope, validate business rules server-side, then return authoritative HTMX fragments/OOB swaps. TypeScript is only the generic bridge from committed intent to generated form submission.
- Keep actor responses and passive invalidation aligned with typed live fragments when the interaction mutates collaborative state. The committed actor response wins for the requester; passive invalidation should still flow from touched resources for other mounted surfaces.
