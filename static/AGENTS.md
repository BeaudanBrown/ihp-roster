# Static Asset Agent Notes

Read this before editing `static/` assets.

## Local Rules

- Runtime assets are app-owned and loaded through `assetPath`.
- App JavaScript source lives in `frontend/ts/`. Do not edit generated browser
  output: `static/app*.js` is checked in and must not be hand-edited.
- Use `bash ./bin/in-env frontend-build` to regenerate JS, and
  `bash ./bin/in-env frontend-check` before committing frontend changes.
- Generated TypeScript contracts live in `frontend/ts/generated/`, are owned by
  Haskell DTOs/enums plus the type-level FrontendSurface registry, and must not
  be hand-edited. Use generated contracts for backend-emitted JSON/data-*
  boundaries where applicable; unknown JSON uses generated `parseX` helpers and
  outbound DTOs use generated `encodeX` helpers.
- Keep app JavaScript split by concern:
  - `app-bootstrap.js`
  - `app-date-pickers.js`
  - `app-dialog-overlays.js`
  - `app-horizontal-scroll.js`
  - `app-live-updates.js`
  - `app-passkeys.js`
  - `app-preferences.js`
  - `app-roster.js`
  - `app-scrollbars.js`
  - `app-time-picker.js`
  - `app-timesheets.js`
  - `app-toasts.js`
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
  app-owned stylesheet in `Makefile` `CSS_FILES` so style-audit can keep direct
  Layout assets complete and in cascade order. IHP `prod.js`/`prod.css`
  concatenation is disabled for this app.
- Do not use production CSS `@import` for app-owned files because imported URLs
  do not receive IHP's cache-busting query string.
- Do not edit third-party CSS (`static/vendor/**`) as part of app stylesheet
  refactors.
- Run `bash ./bin/in-env ./bin/style-audit` after stylesheet link, token, or
  architecture changes. It is a hard gate for Layout/Makefile sync, missing
  app-owned stylesheet links, `@import`, line budget, raw colour, and unexpected
  global-selector regressions. Use `bash ./bin/in-env ./bin/css-inventory` for
  the warning-only CSS architecture report (line budgets, raw colours, global
  feature selectors, and stale-selector candidates).
- The supported browser-code bundler is the existing Nix/devenv esbuild
  pipeline that emits split `static/app*.js` files. Do not add ad hoc bundlers,
  re-enable IHP `prod.js` concatenation, Vite dev servers, true-HMR
  requirements, or npm/npx project workflows as part of ordinary runtime
  refactors.

## Live Runtime

- Generic live-update behavior belongs in `app-live-updates.js`.
- Do not add feature-specific adapters for normal live-surface discovery,
  subscription, request decoration, version-gap resync, fragment fetching,
  swapping, or focused-field protection.
- Treat `data-bepis-surface-config` JSON as server-owned surface output and parse
  it only through the generated exact per-surface mount parser. Static JS should
  not infer feature scopes, target ids, or URLs that belong in Haskell surface
  definitions. FrontendSurface subscriptions, websocket invalidations, and actor
  events carry semantic fragment keys only; the browser resolves them against
  each matching local mount's URL, target, and protection policy. DOM/config
  mismatches must be reported and skipped. Do not add browser mount state/load
  policy/duplicated resync fields, raw live endpoint/header/DOM strings,
  `data-live-update-surface` support, or feature-specific live transport
  switches.
- Focused-field protection is owned only by the live-update runtime and consumes
  the exact generated descriptor policy. Do not add Morphdom wrappers, IHP Auto
  Refresh compatibility, feature-local blur queues, or fallback field-key
  attributes. `replace` fragments must not be delayed merely because a control
  inside them has focus.
- Feature scripts may handle genuinely feature-specific UI behavior.

## Typed Interaction Runtime

- Read `Application/Helper/Interaction.SPEC.md` before adding `data-bepis-*`
  interaction markup or runtime behavior. Use
  `docs/workstreams/typed-interaction-surfaces.md` only for remaining ticket
  history while it is still active.
- Interaction surfaces, server layers, disposable layers, item/slot/handle
  markers, intent names, intent fields, HTMX triggers, targets, and swaps should
  be rendered by Haskell helpers from typed Haskell contracts. Do not handwrite
  raw `data-bepis-*` attrs or interaction HTMX forms in feature views except in
  tests/fixtures that explicitly exercise guardrails.
- Static/TypeScript runtime code consumes generated live-update,
  registered-surface, FrontendSurface, and interaction contracts and stays
  generic: it may manage disposable sessions and disposable UI inside declared
  layers, but must not mutate server-owned business DOM, infer live-fragment
  URLs/target ids, or construct mutation URLs. Do not handwrite
  validators/parsers/encoders for generated contract names; import generated
  `isX`/`parseX`/`encodeX` instead.
- Use standard HTMX primitives first: generated forms, custom event triggers,
  lifecycle events, `hx-sync`/`hx-disabled-elt` where useful, and OOB swaps.
  Do not introduce HTMX extensions or custom elements until a later ticket proves
  that repeated stable lifecycle behavior belongs there.

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

Use frontend unit/DOM tests for importable TypeScript behavior that does not
need the IHP server or a real browser:

```bash
bash ./bin/in-env frontend-test
bash ./bin/in-env frontend-check
```

Do not add frontend unit tests or Playwright E2E to pre-commit hooks. The
tracked pre-commit hook is only for generated JS drift via
`bash ./bin/in-env frontend-drift-check`.
