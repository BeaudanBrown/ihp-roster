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
- Blaze attribute decorators (`element ! attr`, including typed contract helpers) cannot decorate an HSX fragment that the quasi-quoter reduced to static pre-rendered text. Keep at least one genuine dynamic expression on the root element or construct that root with Blaze when attrs are applied outside the quote; pin the decorated output in a render test.

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

HTML form attributes are not validation. Keep `required`, hidden inputs, and select options for browser UX, but pair them with controller-side `requireParam`, typed parsing, venue-scope checks, and record validation so tampered or missing values rerender safely.

## Key Imports
- Always import `Web.View.Prelude` — it re-exports `IHP.ViewPrelude`, `Web.View.Layout`, `Generated.Types`, `Web.Types`, and `Application.Helper.View`
- Shared view helpers should be added to focused modules under `Application/Helper/View/` first. Use `Application/Helper/View.hs` as the compatibility wrapper, not the default implementation bucket.
- Layout is defined in `Web/View/Layout.hs`
- Use `appendQueryParams` for links/forms that need query strings. It URL-encodes keys and values; do not hand-build `?key=value` strings from user or token text.

## Overlay Pattern
- Dialog-style modals must go through `Application.Helper.View.Overlay` helpers (`renderDialogOverlay`, `renderDialogOverlayBodyOnly`, or the approved page-dialog helper) and should target `#dialog-overlay-mount` for HTMX workflows.
- For migrated app-owned dialog/overlay request initiators that are not owned by a mounted `FrontendSurface`, declare an `AppShellAction` dialog-lane action in `Application.Helper.FrontendContract.AppShell` and render/apply attrs with `Application.Helper.FrontendContract.AppShell.Runtime`. Keep `SurfaceAction` for mounted surface request initiators; do not classify global dialog workflow controls as surface actions just because they are launched from a surface.
- Do not render hidden modal templates or raw `.modal`/`.modal-backdrop` markup inside accordions, panels, tables, or live fragments. Put only the trigger in page content, then load the dialog into the shared mount.
- The picker and toast lanes stay separate: picker overlays are globally mounted helpers such as `renderQuarterHourTimePickerModal`, and toasts use the toast overlay helpers.
- When migrating a bespoke modal, remove obsolete modal-specific JS, CSS selectors, data attributes, exports, and tests in the same change.

## Reusable Passkey Pattern
- Render login and registration controls through `Application.Helper.View.Passkey`.
  `FrontendContract.Passkey.Runtime` owns generated roles, exact tagged flow
  configuration, mount-local status relationships, and closed prompt mode.
- Haskell owns begin/finish routes, optional redirects, action/status/recovery
  copy, and complete accessible status/recovery markup. Do not handwrite
  `.js-passkey-*`, scalar URL/status datasets, status ids, or prompt-mode text.
- Keep prompt dismissal semantic state on the generated passkey dismissal role
  while also applying the generated Overlay close role through the typed helper.
  Consume the generated Overlay dismissal event for close, Escape, and backdrop
  UX hints; the generic Overlay adapter alone owns dialog removal, body locking,
  and focus policy.
- Native WebAuthn objects, browser capability checks, base64url conversion, and
  local-storage hints stay inside the generic TypeScript adapter and never enter
  generated schemas.

## Page Help Pattern
- Scoped authenticated pages can opt into contextual help through `appPageHelpTopic` on `AppPageConfig`. Keep the trigger title-adjacent; do not add duplicate page-specific help buttons in toolbars.
- Help content lives in `Application.Helper.View.PageHelp` and is loaded into `#dialog-overlay-mount` through the shared help dialog. When changing visible page controls, workflows, gestures, settings, or role-specific behavior, update the matching help topic in the same change.
- Keep help copy concise, role-aware, and grounded in implemented behavior. Do not add public/auth/legal/dev-lab pages to contextual help unless a ticket explicitly expands the scope.

## Roster HTMX Pattern
- Roster shift edits are whole-shift dialog submits. Grid cells/cards are launchers with `data-roster-shift-launcher`, not inline autosave inputs.
- Dialog forms post atomically to the slot create/update actions and target `#dialog-overlay-mount`; successful actor responses clear the dialog and trigger live fragment refreshes.
- Keep row/day/content fragment IDs stable (`data-roster-row="true"`, day section ids) so actor and passive live refreshes can replace the right server-rendered fragment.
- Do not wire feature/view behavior directly to `turbolinks:load`. The shared client runtime emits `bepis:page-ready` for full-page loads and HTMX swaps, and that runtime is responsible for re-processing any fresh `hx-*` markup.
- When a roster shell participates in live fragments, render scope metadata on the stable shell (`#roster-week-shell`) so JS can subscribe/unsubscribe as `weekOffset` changes without guessing from the URL.
- Live fragment refetch endpoints should return plain server-rendered fragments for the target DOM node. For migrated `FrontendSurface` success paths, reserve `hx-swap-oob` for requester-only extras such as toasts/dialog clears, not authoritative business fragments.
- For viewer-side row refetches, do not return `hx-swap-oob` row wrappers from the fragment GET action; return the plain `<tr>` fragment and let JS replace the target row directly.
- Do not add blur deferral for roster shift launchers or committed dialog submits. Reintroduce narrow protection only if a delayed free-text control returns.

## FrontendSurface Live Shell Pattern
- Treat a `FrontendSurface` mount as the subscription owner. Render mounts with `renderFrontendSurfaceMount`; do not handwrite mount attributes, target ids, URLs, or focused-protection metadata in feature views. The renderer emits the exact generated mount envelope; server-only mount state and lazy/load decisions do not belong in browser JSON.
- Keep scopes as authorized logical data slices rather than page names. A page may render multiple child surface mounts when independently stale feature areas live together.
- Keep fragment/region enums and `SurfaceImpl` handlers feature-local. Views should consume the typed surface implementation and render helpers; avoid duplicating scope, target id, URL, action, intent, or focused-protection wiring beside the markup.
- A parent fragment/region may contain nested child surface mounts when its type-level spec declares the contained surface topology. Child surfaces still own their own subscriptions, fragments, request decoration, and invalidations.
- Parent fragments that refresh over child mounts are allowed, but the shared runtime must reconcile lifecycle recursively: removed child/grandchild mounts unsubscribe when no longer present, newly inserted mounts initialize, and duplicate mounts do not double-subscribe.
- Use one semantic fragment model with multiple triggers: plain fragment renderers serve GET/live refetches, passive websocket invalidation names semantic fragments, and migrated actor success responses emit actor-local semantic invalidation plus extras. Avoid adding parallel `renderXxxOob` business wrappers for migrated success paths; extras-only OOB such as toasts/dialog clears remain allowed.
- Keep reusable browser-side protection such as focused-field deferral in the local FrontendSurface mount descriptor. Websocket and actor invalidations carry semantic fragment keys only; do not add feature adapters for generic lifecycle, reconnect, dedupe, nested reconciliation, version tracking, request decoration, resync, refetch queueing, or swapping.
- For migrated surface-owned HTMX request initiators, declare `Action` metadata in the surface spec and render forms/buttons/links through `Application.Helper.FrontendContract.Surface.Runtime` helpers. Haskell route builders still own `pathTo`/`appendQueryParams`; the DSL owns submitted fields and browser-visible request metadata. Use `CustomHtmx` only with a generated reason, and keep successful mutations on actor-local/passive invalidation rather than business fragment OOB.
- The staff edit modal is a real `StaffSurface` mount. Staff profile, shift-preference, and unavailability forms inside that modal must use `StaffSurface` actions/fragments; do not borrow `staffSurfaceAction` metadata outside the mounted staff surface or reintroduce staff-modal success business OOB.
- Shared reconnect contract: subscriptions should carry a `lastSeenVersion`, subscribe acks should report `currentVersion` plus whether a scope resync is needed, and a gap in scope versions should trigger a full scope resync using live keys derived from the mounted descriptors and reflected fragment metadata instead of a duplicated config list.
- When a reconnect resync falls back to a coarse content fragment, keep the same focus-protection rules as normal live invalidations; do not defer roster content just because a shift launcher is focused.
- Do not use a live surface just because a form currently redirects. A surface is warranted when the mounted page can become stale from another actor, another tab, or an async job. For actor-only edits outside migrated FrontendSurface flows, prefer ordinary HTMX fragments/OOB swaps when useful. For auth, passkey, support venue switching, and other session/security flows, prefer normal browser navigation unless the product explicitly needs in-place behavior.
- Fan-out invalidations should not search every historical table row just to discover possible cold targets. Use the active live-scope snapshot helpers in `Application.Helper.LiveUpdate` to narrow broad mutations to currently mounted scopes, then fetch detailed fragment data for those scopes only.
- Existing non-live candidate areas:
  - export job/recent exports can become a live surface when async job progress matters while the page is open
  - support venue switching, venue creation, owner invitations, passkeys, and auth/session flows should stay full-page or explicit HTMX workflows unless there is a concrete collaborative stale-DOM requirement

## Typed Interaction Surface Pattern
- Read `Application/Helper/Interaction.SPEC.md` and `Application/Helper/FrontendContract/Surface/README.md` before adding `data-bepis-*` markup or frontend interaction behavior.
- Interaction-capable views should render surface mounts, server layers, disposable layers, activation markers, item/slot/handle attrs, and HTMX intent forms through Haskell helpers generated from typed contracts. Do not handwrite raw interaction attrs/forms in feature views once those helpers exist.
- Keep concrete surface mounts portable: derive ids, HTMX targets, and form ids from the typed surface scope plus mount key so the same surface can move across pages or appear more than once.
- Disposable UI belongs in declared disposable layers and is not authoritative. Views should keep server-owned business DOM separate from disposable layers so live fragments can update behind non-conflicting active sessions.
- Mutating interaction intents submit through Haskell-rendered HTMX forms. TypeScript fills generated hidden fields and dispatches generated triggers; views/controllers keep routes, methods, targets, swaps, and validation server-owned.

## Reusable Time Picker Pattern
- Use `renderTimePickerField` plus the shared picker overlay for quarter-hour time selection instead of native `<input type="time">` in dense grids.
- `Application.Helper.FrontendContract.TimePicker` owns the focused global field, value, trigger, label, step, option-grid, option, clear, and modal identities. Views and feature scripts must not handwrite picker role attributes or use presentation classes as browser selectors.
- `TimePickerConfig` is the complete Haskell construction boundary. Haskell owns the range (including overnight wrapping), step, empty-state copy, option values/labels, initial display label, disabled state, and accessibility copy. The view helper serializes exact generated field and option records; TypeScript parses them with the generated parsers and supplies no fallback range, value, label, or copy.
- Step buttons may be omitted through `timePickerShowStepButtons`; the shared renderer still owns the complete generated field/value/trigger/label boundary.
- Malformed field or option payloads are reported locally and skipped without rewriting the server-rendered field or modal options.
- Render `renderQuarterHourTimePickerModal` once in the global layout so it stays in the picker lane and can open above a workflow dialog without competing for the shared dialog mount.
- The generated Toggle capability separately owns timesheet break-field activation. The picker consumes native disabled state and must not query toggle/break roles, synchronize toggle transport, or add a duplicate break handler.
- Keep HTMX autosave on the generated hidden picker value when a workflow needs it, and let the generic adapter dispatch `change` after selecting or clearing an option.

## Reusable Ordered Range Pattern
- `Application.Helper.FrontendContract.OrderedRange` owns generated
  root/config/state/start/end/availability roles, exact configuration/state
  schemas, position properties, and the closed crossing policy. Views must use
  its runtime attr helpers rather than handwrite range datasets.
- Haskell owns the complete allowed range, step, workflow defaults, ordered
  display-label inventory, current values, native accessibility labels/output
  relationships, and initial availability. Keep these values shared with server
  validation rather than reconstructing them in TypeScript.
- Compose availability with the generated Toggle control, but keep the
  OrderedRange availability role on a local wrapper. OrderedRange may read the
  one native checkbox inside that wrapper; it must not import Toggle roles or
  take over Toggle's repeated-field transport.
- Malformed config/state or local DOM disagreement must be reported and skipped
  before mutation. Use native disabled state for unavailable styling and keep
  initialized browser state outside server DOM.

## Theming Pattern (Dark Mode)
- The app uses a centralized token system in `static/css/tokens.css` (`:root` CSS variables) with dark mode as the default. Read `static/css/README.md` before adding or moving app-owned CSS.
- Root layout sets dark mode via `<html data-bs-theme="dark">`; all new views should inherit this instead of setting per-page theme flags.
- Prefer semantic app wrappers/classes over one-off utilities:
  - page shells: `app-shell`, `app-content`, `app-page`, `app-page-auth`
  - surfaces: `app-panel`, `app-auth-card`, `app-panel-body`, `app-auth-body`
  - sizing/text helpers: `app-form-width`, `app-muted`
  - horizontal strips: `app-horizontal-frame`, `app-horizontal-grid`, `app-horizontal-panel`
  - dense controls/buttons: `app-dense-control`, `app-dense-select-plain`, `app-dense-static`, `app-dense-time-value`, `app-icon-button`, `app-compact-action-button`
- Signed-in pages should use `renderAppPage` from `Application/Helper/View/Chrome.hs` plus `app-panel` surfaces. Reserve `app-page-auth` / `app-auth-card` for unauthenticated auth and welcome flows only.
- Prefer `renderAppPanel` from `Application/Helper/View/Chrome.hs` for ordinary themed surfaces instead of hand-writing `app-panel`, `app-panel-header`, and `app-panel-body` markup in each view. Use the custom-header escape hatch only when a surface needs richer toolbar chrome like week navigation.
- Keep page-level titles and summary copy in the shared `app-page-header`. Use panel headers (`app-panel-header`, `app-panel-title`, `app-panel-description`) only for secondary sections inside the page body.
- Avoid inline `style="..."` in HSX for layout/sizing; add a reusable class in the narrowest matching `static/css/` module instead.
- Avoid hardcoded light-mode classes (`bg-light`, `text-muted`) in new views; use semantic classes/tokens.
- For new component colors, add/consume CSS variables first, then apply them in selectors (including Bootstrap overrides).

## Global Header Pattern
- Authenticated navigation is centralized in `Web/View/Layout.hs` (`renderAppHeader`) so every signed-in page gets the same header.
- Keep nav button labels/order consistent: `roster`, `profile`, `timesheets`, `unavailability`, `xero`, `admin`, `support`, `logout`.
- Keep `xero` link visibility owner/super-admin only via the shared Xero audience logic.
- Keep `billing` after Xero and before Admin, visible only to an ordinary venue
  owner when the Stripe owner-navigation deployment control is enabled. Hiding
  navigation must never disable the authorized direct Billing route.
- Keep `admin` link visibility role-gated (admin only) via `currentUserIsAdmin`.
- Keep `support` link visibility founder-only via `currentUserIsSupportAdmin`; do not expose it to ordinary venue admins.
- Do not duplicate primary nav in page-level views unless there is a specific workflow reason.
- Logout and other destructive actions should be explicit forms, not `.js-delete` links. Prefer `method="POST"` plus hidden `_method="DELETE"` so the control works without `helpers.js`; add HTMX attributes only when the surrounding page already needs an in-place update.
- Do not emit `data-disable-javascript-submission`. Bepis does not load IHP `helpers.js`, so the attribute is inert; use native form semantics, HTMX synchronization, or explicit disabled controls instead.
- For low-frequency full-page forms, prefer plain native browser submission. If a form is only serving as a full-page workflow, do not turn it into HTMX or a custom AJAX path by default.

## Responsive Design Contract
- Treat responsiveness as product-specific, not one-size-fits-all:
  - roster creation must remain usable on phone
  - live roster viewing is critical on both phone and desktop
  - unavailability should move toward mobile-first
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
  - generated `AppShellAction` helpers are preferred for migrated launchers
  - trigger uses `hx-get`
  - target is the shared dialog mount
  - swap is `innerHTML`
  - include `weekOffset` or other return-context params in the URL/query
- Dialog submit contract:
  - validation failure returns the dialog fragment again into the same mount
  - migrated FrontendSurface success returns actor-local semantic invalidation plus any out-of-band dialog or toast extras, instead of authoritative business OOB fragments or full-page redirects
  - non-live legacy workflows may still return updated page fragments plus overlay/toast extras until migrated
- Prefer dialog footers built from shared overlay button config. Form helpers should usually not render their own save/cancel rows.
- Only allow one workflow dialog at a time. Pickers may appear above a dialog, but they are a separate overlay kind with separate JS behavior.
