# Styling System Refactor

Created: 2026-04-26

## Purpose

Improve the app styling architecture so `ihp-roster` is easier to theme, refactor, and keep visually consistent across roster, timesheets, leave, admin, exports, support, auth, and overlay workflows.

This plan is based on a readonly scan of the current `roster` branch at commit `ec0a3f1a5029a46a25708584d334b5aefded7ee4`, with existing local modifications present in `static/app.css` and `Web/View/Admin/Index.hs`.

## Current State

- Styling is Bootstrap plus custom CSS, not Tailwind. There is no Tailwind or PostCSS config in the repo.
- Bootstrap 5.3.8 is loaded directly from `static/vendor/bootstrap-5.3.8/` in `Web/View/Layout.hs`.
- The main app stylesheet is `static/app.css`, currently a single file of roughly 2,300 lines.
- The app has a useful initial token layer in `:root`, dark mode is set at layout level with `<html data-bs-theme="dark">`, and shared page/panel helpers already exist in `Application/Helper/View/Chrome.hs`.
- `renderAppPage` and `renderAppPanel` are used by the main app pages, but many inner surfaces still hand-roll Bootstrap utility combinations and Bootstrap color classes.

## Key Issues

### 1. One Large Mixed Stylesheet

`static/app.css` mixes several concerns:

- design tokens
- Bootstrap overrides
- app layout and header
- page and panel primitives
- overlay/toast/picker styles
- roster grid and roster export styles
- roster week overview styles
- roster staff panel styles
- leave request styles
- admin slot-name styles
- timesheet card/timeline styles

This makes ownership hard to see and makes unrelated styling changes risky.

### 2. Incomplete Token Layer

The token layer is a good start, but it is incomplete.

Known undefined variables currently referenced:

- `--app-accent`
- `--app-text-muted`

There are also many hardcoded hex and rgba values outside the token block. That means a future theme change would still require broad file edits rather than changing a small set of semantic variables.

### 3. Partial Bootstrap Integration

The app overrides some Bootstrap surfaces, especially tables, forms, and outline buttons. But other Bootstrap components still depend heavily on Bootstrap-native color utilities and defaults:

- badges
- alerts
- dropdown menus
- modals
- form text
- success/warning/danger button variants
- utility classes such as `bg-white`, `bg-light-subtle`, `text-muted`, and `text-body-secondary`

This creates uneven dark-mode behavior and makes venue theming harder.

### 4. Reuse Is Good But Not Complete

The app already has reusable page and panel helpers:

- `renderAppPage`
- `renderAppPanel`
- overlay helpers
- toast helpers
- reusable time picker helpers

However, many repeated patterns still live directly in HSX:

- `border rounded p-*` local surfaces
- Bootstrap badge status classes
- week navigation toolbar variants
- dropdown action menus
- checkbox/toggle sections
- empty states and muted support text

These should move into helper-backed semantic components where they are repeated.

### 5. Generic Components Still Carry Feature Names

Some styles are shared beyond their original feature but still use feature-specific names.

Examples:

- `roster-week-more-menu` is reused by timesheets.
- `roster-grid-header` duplicates or aliases `app-surface-toolbar`.
- week navigation classes mix `app-week-*` and `roster-week-*`.

This makes reuse harder to discover and encourages new pages to copy old feature names.

### 6. Venue Theming Has No Model Yet

The database has `venues` and `venue_config`, but no theme or branding fields. The layout hard-pins the app to dark mode, and there is no current server-rendered venue theme variable layer.

The app should support theming by rendering approved CSS custom properties, not by loading arbitrary CSS per venue.

### 7. Asset Pipeline Has Stale References

`Makefile` still lists IHP vendor Bootstrap and Flatpickr asset inputs, while `Web/View/Layout.hs` loads local Bootstrap 5.3.8 assets. This should be reconciled so the asset story is explicit and future styling work does not depend on stale build assumptions.

## Target Architecture

Keep the current Bootstrap plus plain CSS approach for the first refactor. Do not introduce Tailwind or a frontend bundler as the first move.

Target shape:

- a small, semantic token layer
- Bootstrap variables bridged from app tokens
- feature CSS separated by ownership
- shared view helpers for repeated app components
- feature-specific classes only where the feature genuinely needs custom behavior
- venue theming implemented as controlled CSS variable overrides

Suggested stylesheet ownership:

- `static/css/tokens.css`
- `static/css/bootstrap-bridge.css`
- `static/css/layout.css`
- `static/css/components.css`
- `static/css/overlays.css`
- `static/css/features/admin.css`
- `static/css/features/exports.css`
- `static/css/features/leave.css`
- `static/css/features/roster.css`
- `static/css/features/timesheets.css`

The repo can either load those files directly in layout, or concatenate them into `static/app.css` later. Direct loading is the simplest first step for an IHP app without a bundler.

## Token Plan

Create a clearer semantic token set before migrating component CSS.

Recommended groups:

- color background: `--app-bg`, `--app-bg-elevated`
- color surface: `--app-surface`, `--app-surface-raised`, `--app-surface-muted`
- color border: `--app-border`, `--app-border-strong`, `--app-border-subtle`
- color text: `--app-text`, `--app-text-muted`, `--app-text-subtle`, `--app-text-inverse`
- color action: `--app-accent`, `--app-accent-hover`, `--app-accent-soft`, `--app-focus-ring`
- status: `--app-success`, `--app-success-soft`, `--app-warning`, `--app-warning-soft`, `--app-danger`, `--app-danger-soft`, `--app-info`, `--app-info-soft`
- surfaces: `--app-panel-bg`, `--app-panel-border`, `--app-menu-bg`, `--app-modal-bg`
- geometry: `--app-radius-sm`, `--app-radius-md`, `--app-radius-lg`, `--app-radius-pill`
- elevation: `--app-shadow-sm`, `--app-shadow-md`, `--app-shadow-lg`
- density: `--app-space-*`, `--app-control-height-*`
- typography: `--text-xs`, `--text-sm`, `--text-base`, `--text-lg`, `--text-xl`
- roster density: `--roster-row-height`, `--roster-text-xs`, `--roster-text-sm`, `--roster-text-base`

Then map Bootstrap variables from those tokens:

- `--bs-body-bg`
- `--bs-body-color`
- `--bs-border-color`
- `--bs-primary`
- `--bs-secondary`
- `--bs-success`
- `--bs-warning`
- `--bs-danger`
- `--bs-link-color`
- `--bs-link-hover-color`
- `--bs-modal-bg`
- `--bs-dropdown-bg`
- `--bs-tertiary-bg`

## Component Helper Plan

Add or extend helper modules under `Application/Helper/View/` so repeated markup becomes semantic and centralized.

Suggested helper areas:

- `Chrome.hs`: app page, panel, surface, section, empty state, toolbar.
- `Status.hs`: app status badge variants for success, warning, danger, neutral, info.
- `Actions.hs`: week navigation, action menu, icon button, button-group patterns.
- `Forms.hs`: themed checkbox card, toggle row, field description, validation summary.
- `Overlay.hs`: keep modal/dialog behavior here.
- `Toast.hs`: keep toast behavior here.

Avoid making `Application/Helper/View.hs` the implementation bucket. Keep it as the compatibility re-export boundary.

## Venue Theming Plan

Venue theming should be data-driven and constrained.

Recommended model:

- Add a nullable `theme_config JSONB` or explicit nullable theme fields to `venue_config`.
- Start with a small allowlist:
  - accent color
  - success color
  - warning color
  - danger color
  - optional logo URL or uploaded asset reference later
  - optional mode only if light mode is deliberately supported
- Validate colors server-side as safe hex colors.
- Convert venue theme values into CSS variables in the layout.
- Render the variables on a high-level element such as `<body>` or an app theme wrapper.
- Keep fallback defaults in `tokens.css`.
- Do not allow arbitrary venue CSS.

Example target rendering shape:

```html
<body class="theme-dark" style="--app-accent:#...;--app-accent-soft:...">
```

Longer term, prefer a helper that renders the style attribute from a typed theme config rather than building ad hoc strings in layout.

## Phased Refactor

### Phase 1: Stabilize And Audit

Scope:

- Fix undefined CSS variables.
- Reconcile asset references between `Makefile` and `Web/View/Layout.hs`.
- Add a small style audit script that reports:
  - undefined CSS variable references
  - hardcoded colors outside token files
  - banned light-mode Bootstrap utilities in HSX
  - new inline `style=` usage outside approved dynamic CSS variable cases

Acceptance:

- No undefined CSS variables remain.
- Current pages still typecheck.
- The style audit can run locally and produce useful output.

### Phase 2: Split CSS By Ownership

Scope:

- Split `static/app.css` into clear ownership files.
- Keep behavior equivalent.
- Load multiple CSS files directly from `Web/View/Layout.hs`, or introduce a simple deterministic concatenation step if preferred.
- Add short comments at the top of each file explaining ownership and when to add styles there.

Acceptance:

- Styling remains visually equivalent.
- CSS ownership is clear from filenames.
- Feature styles no longer obscure app-wide token and component layers.

### Phase 3: Complete The Semantic Token And Bootstrap Bridge

Scope:

- Expand tokens to cover all repeated colors, surfaces, borders, radii, focus rings, status colors, shadows, and density values.
- Replace hardcoded colors in shared components first.
- Bridge Bootstrap variables from app tokens.
- Add explicit overrides for badges, alerts, dropdowns, modals, and form text.

Acceptance:

- Global theme changes mostly happen in token files.
- Bootstrap-native components no longer visually drift from app components.
- New status colors come from semantic tokens.

### Phase 4: Promote Repeated Markup Into Helpers

Scope:

- Add `Status`, `Actions`, and `Forms` helper modules as needed.
- Replace repeated badge rendering in admin, support, exports, leave, and roster overview.
- Replace hand-rolled local surfaces with a shared `renderAppSurface` or `renderAppSection`.
- Replace repeated week toolbar/action menu patterns with shared helpers.

Acceptance:

- Pages no longer need to know exact Bootstrap badge classes for common statuses.
- Local surfaces use semantic helper classes instead of one-off `border rounded p-*` combinations.
- `roster-week-more-menu` is replaced by a generic `app-action-menu` class where it is not roster-specific.

### Phase 5: Feature CSS Cleanup

Scope:

- Keep roster dense-grid CSS feature-local.
- Rename shared roster-prefixed classes that are used by other features.
- Move timesheet-only, leave-only, admin-only, export-only styles into their feature files.
- Remove duplicate selector blocks and reduce `!important` use where Bootstrap bridging makes it unnecessary.

Acceptance:

- Feature styles have obvious owners.
- Shared classes use `app-*` names.
- Feature names appear only where styles are feature-specific.

### Phase 6: Add Venue Theme Configuration

Scope:

- Add the schema foundation for venue theme config.
- Add typed parsing and validation for the allowed theme fields.
- Render venue theme variables in layout for authenticated venue-scoped pages.
- Add an admin/support-only editing surface if product-ready; otherwise seed/test through fixtures first.

Acceptance:

- A venue can override a small set of theme variables safely.
- Invalid theme values are rejected.
- The default theme remains unchanged when no venue theme is configured.
- Support/admin flows can verify two venues with different theme accents without loading arbitrary CSS.

### Phase 7: Verification And Visual Regression

Scope:

- Add controller/typecheck coverage for new helpers where useful.
- Add Playwright smoke checks for main styled surfaces:
  - auth
  - roster
  - timesheets
  - leave
  - admin
  - exports
  - support
- Add screenshot checks for default theme and at least one alternate venue accent theme.

Acceptance:

- `bash ./bin/in-env typecheck` passes.
- Relevant E2E smoke coverage passes.
- Screenshots show no obvious dark-mode regressions or unreadable themed surfaces.

## First Recommended Implementation Slice

Start with a low-risk foundation slice:

1. Fix `--app-accent` and `--app-text-muted`.
2. Add the style audit script.
3. Split only tokens and Bootstrap bridge out of `static/app.css`.
4. Update `Web/View/Layout.hs` to load the split files.
5. Migrate Exports as the first page from hand-rolled light surfaces and Bootstrap status badges to semantic helper-backed surfaces.

Exports is a good first page because it has several current styling issues, uses repeated status badges and local surfaces, and is less risky than the dense roster grid.

## Constraints

- Keep Bootstrap for now.
- Do not introduce Tailwind as the first styling refactor.
- Do not introduce a JS bundler just to support CSS structure.
- Do not allow arbitrary venue CSS.
- Avoid broad visual redesign while first improving ownership, tokens, and consistency.
- Preserve the existing dark theme as the default.
- Treat dense roster grid styling as a later, careful feature-specific cleanup after shared styling foundations are stable.
