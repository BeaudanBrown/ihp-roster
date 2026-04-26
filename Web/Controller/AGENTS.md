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
- Use `param @Type "name"` to read request parameters
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
  - cross-viewer updates use `broadcastLiveInvalidation` with fragment refs that point to dedicated GET fragment actions
- Declare ordinary live surfaces from Haskell with `Application.Helper.LiveSurface.mkLiveSurface` and render them with `liveSurfaceConfigJson`; the browser runtime discovers `data-live-update-surface` and owns subscription, request decoration, resync, refetch queueing, swapping, and reusable protection policies.
- Treat scopes as authorized logical data slices, not pages. A mutation may invalidate multiple scopes, and only a subset of fragments within each scope.
- Prefer one websocket connection per browser tab/client with many active scope subscriptions instead of one socket per page.
- Keep fragment refs explicit (`targetId`, `url`, defer/swap metadata) so the transport stays structural and controllers do not need to know mounted DOM state.
- Keep reconnect semantics explicit in the transport: each scope should expose a monotonic version, subscribe commands may include the client's `lastSeenVersion`, and the server should tell the client when a full scope resync is required instead of assuming no invalidations were missed.
- Keep fragment GET actions authorized with the same venue/visibility rules as the full page; do not expose restricted fragments just because the websocket payload names them.
- Include the acting tab's `X-Live-Update-Client-Id` in broadcasts so the client can suppress its own invalidation echo.
- Broadcast invalidations for affected scopes after the business transaction commits, not before.
- For direct mutations that know their exact scope, broadcast that scope directly. For fan-out mutations that could touch many roster weeks or other cold surfaces, first intersect the candidate set with active subscriptions via `Application.Helper.LiveUpdate.activeLiveUpdateScopes` or `activeRosterWeekScopes`, then query/build refs only for those open scopes. Closed pages should rely on fresh HTTP rendering unless the feature explicitly needs durable missed-update semantics.
- When a slot mutation can change conflict state across multiple rows, it is acceptable for the actor response to return a full `#roster-content` OOB refresh instead of trying to keep actor-side row patches perfectly minimal.
- Keep the roster week shell subscribed even when the week is empty or hidden so create/copy/publish transitions can invalidate passive viewers already sitting on that offset.
- For new candidates, add the controller surface in this order: fragment GET action, authorized `LiveFragmentRef` builder, `LiveSurfaceConfig` in the view layer, actor-path HTMX response, post-commit `broadcastLiveInvalidation`, Hspec coverage for unauthorized/authorized fragment responses and rendered surface metadata, then Playwright coverage when browser behavior such as resync, focus protection, or no-full-page navigation is part of the feature.
