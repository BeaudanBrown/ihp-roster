# View Guidelines

Read the IHP view, HSX, and form guides referenced by root `AGENTS.md` before
view work. Import `Web.View.Prelude`; keep shared helpers in focused
`Application/Helper/View/` modules rather than the compatibility facade.

## HSX And Forms

Use `[hsx|...|]`, valid closed HTML, typed action values, and existing render
helpers. A Blaze decorator cannot decorate an HSX fragment reduced to static
pre-rendered text; keep a genuinely dynamic root expression or build that root
with Blaze, then pin it with a render test.

HTML form attributes are browser UX, not validation. Controllers must enforce
required fields, typed parsing, bounds, and venue scope. Build query strings
with `appendQueryParams`, never concatenated request/token text.

## Overlays And Interactions

Dialog-style modals must go through `Application.Helper.View.Overlay` helpers
and target the shared dialog mount. Do not place hidden templates or raw modal
markup in feature views. Workflow dialogs, utility pickers, and toasts are
separate lanes; only one workflow dialog is active at a time.

Before adding interaction/live markup, read:

- `Application/Helper/Interaction.SPEC.md`
- `Application/Helper/LiveUpdate.SPEC.md`
- `Application/Helper/FrontendContract/Surface/README.md`

Render `FrontendSurface` mounts, actions, fragments, interaction roles, and
intent forms through typed Haskell helpers. Do not handwrite mount config,
`data-bepis-*` contracts, target IDs, URLs, or browser-owned business state.
Server-rendered plain fragments remain authoritative; actor and passive refresh
paths share semantic fragment keys. Disposable UI stays in declared disposable
layers and must not become business DOM.

## Layout And Navigation

Render the root-defined header order from `Web/View/Layout.hs`: `roster`,
`profile`, `timesheets`, `unavailability`, `xero`, `billing`, `admin`, `support`,
`logout`. View-local audience rules are: Xero owner/super-admin; Billing ordinary
owner only when its deployment control is enabled; Admin admin-only; Support
founder-only. Hiding Billing navigation must not disable its authorized direct
route. Auth pages do not render the header, and page views do not duplicate it.
Logout/destructive actions use explicit native forms rather than JavaScript-only
links.

Use `renderAppPage`/`renderAppPanel` and semantic CSS classes from the existing
component/token system. Put CSS in the narrowest `static/css/` owner; avoid
inline layout styles, hard-coded light-theme classes, raw colours, viewport
horizontal overflow, hover-only actions, and clipped mobile dialogs. Read
`static/css/README.md` before CSS work.

Roster window browsing remains URL-driven through ISO `anchorDate`; use
canonical actions and stable shell/fragment IDs. Live fragment GETs return plain
target nodes, not OOB wrappers.

## Verification

Run `bash ./bin/in-env typecheck` plus focused render/controller Hspec. For
responsive, HTMX, overlay, or live behavior, run focused Playwright and inspect
screenshots where visual judgment is required.
