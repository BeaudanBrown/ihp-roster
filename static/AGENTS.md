# Static Asset Agent Notes

Read this before editing `static/` assets.

## Local Rules

- Runtime assets are app-owned and loaded through `assetPath`.
- Keep app JavaScript split by concern:
  - `app-bootstrap.js`
  - `app-date-pickers.js`
  - `app-dialog-overlays.js`
  - `app-horizontal-scroll.js`
  - `app-live-updates.js`
  - `app-passkeys.js`
  - `app-preferences.js`
  - `app-roster.js`
  - `app-time-picker.js`
  - `app-timesheets.js`
  - `app-toasts.js`
  - `app.js`
- Keep CSS split by concern under `static/css/`; read `static/css/README.md`
  before adding or moving app-owned CSS.
- Choose the narrowest owner: semantic tokens in `static/css/tokens.css`,
  persisted palette key values in `static/css/palette.css`, Bootstrap
  bridges in `static/css/bootstrap-bridge.css`, shell/header layout in
  `static/css/layout.css`, shared UI primitives in focused
  `static/css/components/*.css` modules, overlays in `static/css/overlays.css`, and
  feature-only rules in `static/css/features/*` or focused feature modules.
- Add feature CSS to the narrowest matching file under `static/css/`; do not
  recreate a catch-all `static/app.css` unless a compatibility ticket requires
  it.
- Before adding selectors, search for existing modules/classes, prefer shared
  component primitives such as `app-horizontal-*`, `app-dense-*`,
  `app-icon-button`, and `app-compact-action-button`, add semantic tokens
  before raw colours, and scope feature CSS by feature root/prefix.
- Avoid global `.app-*`, `.btn`, `.form-*`, `.nav-*`, `.breadcrumb`, or
  Bootstrap overrides in feature stylesheets unless the exception is explicitly
  documented in the CSS README or local feature docs.
- Link split CSS from `Web/View/Layout.hs` with `assetPath`; mirror each linked
  app-owned stylesheet in `Makefile` `CSS_FILES` so packaging hash inputs stay
  complete and in cascade order.
- Do not use production CSS `@import` for app-owned files because imported URLs
  do not receive IHP's cache-busting query string.
- Do not edit generated or third-party CSS (`static/prod.css`,
  `static/vendor/**`) as part of app stylesheet refactors.
- Run `bash ./bin/in-env ./bin/style-audit` after stylesheet link, token, or
  architecture changes. It is a hard gate for Layout/Makefile sync, missing
  app-owned stylesheet links, `@import`, line budget, raw colour, and unexpected
  global-selector regressions. Use `bash ./bin/in-env ./bin/css-inventory` for
  the warning-only CSS architecture report (line budgets, raw colours, global
  feature selectors, and stale-selector candidates).
- Do not add a bundler as part of ordinary runtime refactors.

## Live Runtime

- Generic live-update behavior belongs in `app-live-updates.js`.
- Do not add feature-specific adapters for normal live-surface discovery,
  subscription, request decoration, version-gap resync, fragment fetching,
  swapping, or focused-field protection.
- Treat `data-live-update-surface` JSON as server-owned typed-surface output.
  Static JS should not infer feature scopes, target ids, or URLs that belong in
  Haskell surface definitions. The current websocket/actor-refresh payloads are
  intentionally self-describing; do not switch to compact fragment-key payloads
  without a protocol migration ticket and browser coverage.
- Feature scripts may handle genuinely feature-specific UI behavior.

## Horizontal Scroll Components

- Use `app-horizontal-frame`, `app-horizontal-grid`, and
  `app-horizontal-panel` for reusable horizontal strip layout, with
  `data-horizontal-snap` for reusable horizontal snapping and
  `data-horizontal-drag-scroll` for reusable mouse drag-scroll.
- Use generic runtime attrs only: `data-horizontal-snap-dragging` and
  `data-horizontal-dragging`. Do not add feature-specific aliases.
- Interactive descendants are ignored by drag-scroll by default; add a narrow
  `data-horizontal-drag-scroll-ignore-selector` only for extra feature-specific
  controls.
- The newest user scroll or drag must cancel stale snap intent. Do not add
  feature scripts that fight `app-horizontal-scroll.js` for the same scroller.

## UI Rules

- Keep page-level horizontal overflow off the viewport.
- Dense tables should own overflow in local wrappers such as `.table-responsive`.
- Dialogs and overlays must fit phone-sized viewports without clipped primary
  actions.
- Do not rely on hover-only affordances for important actions.

## Verification

Use focused Playwright and screenshots for runtime or responsive changes:

```bash
bash ./bin/in-env e2e e2e/mobile-experience.spec.ts
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env screenshot-page /RosterWeeks output/check.png --selector '#roster-week-shell'
```
