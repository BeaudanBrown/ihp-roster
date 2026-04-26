# View Guidelines

## Reference
Read `/home/beau/documents/projects/ihp/Guide/view.markdown` and `/home/beau/documents/projects/ihp/Guide/hsx.markdown` before creating views.

## Creating a View

Each view is a separate file in `Web/View/ControllerName/ActionName.hs`:

```haskell
module Web.View.Posts.Index where
import Web.View.Prelude

data IndexView = IndexView { posts :: [Post] }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <h1>Posts</h1>
        {forEach posts renderPost}
    |]

renderPost :: Post -> Html
renderPost post = [hsx|
    <div>
        <h2>{post.title}</h2>
        <a href={ShowPostAction post.id}>Show</a>
    </div>
|]
```

## HSX Rules
- `[hsx|...|]` is the quasi-quoter — type-checked at compile time
- Embed Haskell expressions with `{expression}`
- Use `{forEach items renderItem}` for lists
- Action values work directly as `href` values: `href={ShowPostAction postId}`
- Conditional rendering: `{when condition [hsx|...|]}`
- HSX is strict about valid HTML — close all tags

## Forms
Read `/home/beau/documents/projects/ihp/Guide/form.markdown` for full details. Basic pattern:
```haskell
renderForm :: Post -> Html
renderForm post = formFor post [hsx|
    {textField #title}
    {textareaField #body}
    {submitButton}
|]
```

## Key Imports
- Always import `Web.View.Prelude` — it re-exports `IHP.ViewPrelude`, `Web.View.Layout`, `Generated.Types`, `Web.Types`, and `Application.Helper.View`
- Shared view helpers should be added to focused modules under `Application/Helper/View/` first. Use `Application/Helper/View.hs` as the compatibility wrapper, not the default implementation bucket.
- Layout is defined in `Web/View/Layout.hs`

## Roster HTMX Pattern
- For high-frequency roster edits, avoid `hx-target="#roster-content"` full-fragment swaps on each input.
- Prefer row-targeted updates: set stable `<tr id=... data-roster-row="true">` IDs and return only affected rows with `hx-swap-oob="outerHTML"`.
- Keep `hx-sync` on roster inputs anchored to a stable wrapper that will not be replaced by the response (for roster week pages, use `#roster-week-shell:queue last`, not `#roster-content`).
- Do not wire feature/view behavior directly to `turbolinks:load`. The shared client runtime emits `app:page-ready` for full-page loads and HTMX swaps, and that runtime is responsible for re-processing any fresh `hx-*` markup.
- When a roster shell participates in live fragments, render scope metadata on the stable shell (`#roster-week-shell`) so JS can subscribe/unsubscribe as `weekOffset` changes without guessing from the URL.
- Live fragment refetch endpoints should return plain server-rendered fragments for the target DOM node; reserve `hx-swap-oob` variants for the actor path.
- For viewer-side row refetches, do not return `hx-swap-oob` row wrappers from the fragment GET action; return the plain `<tr>` fragment and let JS replace the target row directly.
- Mark row fragments as blur-deferred on the client when remote updates should not overwrite focused `.slot-cell-input` controls.
- If a blur-deferred row contains repeated field names across slot columns (`staffId`, `note`, `startTime`), render a stable per-control key such as `data-roster-field-key` from the slot id. Client-side restore logic must target that key instead of the first matching `[name=...]` in the row.
- Keep blur deferral narrow. On the roster grid it should protect the delayed flag input (`.slot-note-input`), not discrete controls like staff selects or committed time-picker changes.

## Shared Live Shell Pattern
- Treat the page shell as the subscription owner. Render scope metadata on a stable shell element so the shared client can subscribe/unsubscribe as HTMX navigation swaps shells in and out.
- Mark each subscribing shell with `data-live-update-surface={liveSurfaceConfigJson surface}`. The JSON surface config owns the feature name, socket path, scope, resync fragments, and request-decoration selectors.
- A shell may subscribe to more than one scope, but scopes should represent logical data slices rather than page names.
- Fragment invalidations should name explicit target ids and refetch URLs. Keep the fragment GET route canonical for that DOM region instead of rebuilding HTML inside websocket handlers.
- Use `LiveFragmentProtection` policies for reusable browser-side protection such as focused-field deferral. Do not add feature adapters for generic websocket lifecycle, reconnect, dedupe, version tracking, request decoration, resync, refetch queueing, or swapping.
- Shared reconnect contract: subscriptions should carry a `lastSeenVersion`, subscribe acks should report `currentVersion` plus whether a scope resync is needed, and a gap in scope versions should trigger a full scope resync through the feature adapter instead of guessing which invalidations were missed.
- When a reconnect resync falls back to a coarse content fragment, keep the same focus-protection rules as normal live invalidations: defer the content refetch until blur if a `.slot-cell-input` inside that fragment is still focused, while allowing unrelated mounted fragments such as side panels to refresh immediately.

## Reusable Time Picker Pattern
- Use a shared picker overlay + JS behavior for quarter-hour time selection instead of native `<input type="time">` in dense grids.
- Markup contract:
  - wrap field with `data-time-picker-field`
  - store canonical value in hidden `.js-time-picker-input` (`HH:MM` 24-hour)
  - open picker via `.js-time-picker-trigger`
  - render text in `.js-time-picker-label` (12-hour with AM/PM)
  - optional range override per field: `data-time-picker-start="HH:MM"` + `data-time-picker-end="HH:MM"` (end may wrap past midnight)
  - optional empty-label override per field: `data-time-picker-empty-label="Time"`
  - step buttons are optional; when omitted, the shared picker should still use the same wrapper/input/trigger contract
- Render `renderQuarterHourTimePickerModal` once in the global layout so it stays in the picker lane and can open above a workflow dialog without competing for the shared dialog mount.
- Keep HTMX autosave on the hidden input (`hx-trigger="change"`), and let JS dispatch `change` after selecting/clearing a modal option.

## Theming Pattern (Dark Mode)
- The app uses a centralized token system in `static/app.css` (`:root` CSS variables) with dark mode as the default.
- Root layout sets dark mode via `<html data-bs-theme="dark">`; all new views should inherit this instead of setting per-page theme flags.
- Prefer semantic app wrappers/classes over one-off utilities:
  - page shells: `app-shell`, `app-content`, `app-page`, `app-page-auth`
  - surfaces: `app-panel`, `app-auth-card`, `app-panel-body`, `app-auth-body`
  - sizing/text helpers: `app-form-width`, `app-muted`
- Signed-in pages should use `renderAppPage` from `Application/Helper/View/Chrome.hs` plus `app-panel` surfaces. Reserve `app-page-auth` / `app-auth-card` for unauthenticated auth and welcome flows only.
- Prefer `renderAppPanel` from `Application/Helper/View/Chrome.hs` for ordinary themed surfaces instead of hand-writing `app-panel`, `app-panel-header`, and `app-panel-body` markup in each view. Use the custom-header escape hatch only when a surface needs richer toolbar chrome like week navigation.
- Keep page-level titles and summary copy in the shared `app-page-header`. Use panel headers (`app-panel-header`, `app-panel-title`, `app-panel-description`) only for secondary sections inside the page body.
- Avoid inline `style="..."` in HSX for layout/sizing; add a reusable class in `static/app.css` instead.
- Avoid hardcoded light-mode classes (`bg-light`, `text-muted`) in new views; use semantic classes/tokens.
- For new component colors, add/consume CSS variables first, then apply them in selectors (including Bootstrap overrides).

## Global Header Pattern
- Authenticated navigation is centralized in `Web/View/Layout.hs` (`renderAppHeader`) so every signed-in page gets the same header.
- Keep nav button labels/order consistent: `roster`, `profile`, `timesheets`, `leave`, `admin`, `support`, `logout`.
- Keep `admin` link visibility role-gated (admin only) via `currentUserIsAdmin`.
- Keep `support` link visibility founder-only via `currentUserIsSupportAdmin`; do not expose it to ordinary venue admins.
- Do not duplicate primary nav in page-level views unless there is a specific workflow reason.
- Logout and other destructive actions should be explicit forms, not `.js-delete` links. Prefer `method="POST"` plus hidden `_method="DELETE"` so the control works without `helpers.js`; add HTMX attributes only when the surrounding page already needs an in-place update.
- For low-frequency full-page forms, prefer plain native browser submission. If a form is only serving as a full-page workflow, do not turn it into HTMX or a custom AJAX path by default.

## Responsive Design Contract
- Treat responsiveness as product-specific, not one-size-fits-all:
  - roster creation must remain usable on phone
  - live roster viewing is critical on both phone and desktop
  - leave should move toward mobile-first
  - admin can remain desktop-primary
- Keep page-level horizontal overflow off the viewport. If a surface needs extra width, a local wrapper such as `.table-responsive` must own that overflow instead of letting `body` scroll sideways.
- Prefer one-column stacking on smaller screens over squeezed side-by-side controls.
- When a desktop table becomes too dense for phones, choose deliberately between:
  - contained horizontal scroll
  - a card/list rendering
  - a separate mobile-specific presentation
- Dialogs and overlays must fit within phone-sized viewports without clipped primary actions.
- Do not rely on hover-only affordances for important actions; touch remains a first-class input mode.

## Roster Week Controls
- Keep week browsing URL-driven via `weekOffset` action params.
- Use compact controls in the roster page header: `<`, `this week`, `>`.
- `this week` should link to `RosterWeeksAction` (server-side reset to current offset), not a client-side calculation.
- For HTMX week browsing, wrap the header + page content in a stable shell id, target that shell with `hx-get`, `hx-swap="outerHTML"`, `hx-select`, `hx-push-url="true"`, and `hx-sync="#shell-id:replace"`.
- Do not add `data-turbolinks` attributes in new view code. TurboLinks is no longer part of the app runtime, so ordinary links should use normal browser navigation and HTMX controls should stand on their own.
- For roster side-panel sizing on desktop, prefer CSS-only sticky layout with a viewport-capped panel and internal scroll over JS height syncing.
- Roster create/copy/publish controls belong to the interactive roster surface. Keep them on HTMX with explicit fragment targets instead of falling back to native full-page reloads.

## Overlay Pattern
- Prefer HTMX-driven workflow dialog fragments over `setModal` + page-jump flows for roster, timesheets, and other high-frequency in-place workflows.
- Render top-level overlay hosts in `Web/View/Layout.hs`:
  - one shared dialog mount for workflow dialogs
  - one shared toast mount for transient notifications
  - picker markup rendered separately for utility overlays
- Default toast placement is bottom-center. Future left/right placement changes should come from shared helper config, not layout-specific markup changes.
- Keep reusable overlay helpers in `Application/Helper/View/Overlay.hs` and toast helpers in `Application/Helper/View/Toast.hs` so structure, title, close behavior, footer/button handling, and toast rendering stay centralized.
- When adding new shared UI helpers, split by concern:
  - page/panel/navigation wrappers in `View/Chrome.hs`
  - dialog workflow wrappers in `View/Overlay.hs`
  - toast rendering in `View/Toast.hs`
  - dense time-input or form-specific helpers in their own dedicated modules rather than extending the wrapper module
- Dialog launch contract:
  - trigger uses `hx-get`
  - target is the shared dialog mount
  - swap is `innerHTML`
  - include `weekOffset` or other return-context params in the URL/query
- Dialog submit contract:
  - validation failure returns the dialog fragment again into the same mount
  - success returns updated page fragments plus any out-of-band dialog or toast updates, instead of redirecting the full page
- Prefer dialog footers built from shared overlay button config. Form helpers should usually not render their own save/cancel rows.
- Only allow one workflow dialog at a time. Pickers may appear above a dialog, but they are a separate overlay kind with separate JS behavior.
