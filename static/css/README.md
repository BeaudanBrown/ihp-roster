# App CSS Architecture

App-owned CSS is split into directly linked stylesheets. `Web/View/Layout.hs`
loads each stylesheet with `assetPath`, and `Makefile` mirrors the same files in
`CSS_FILES` so packaging and cache-busting see every source. Do not use
app-owned CSS `@import`, do not add a bundler, and do not edit generated or
third-party CSS (`static/prod.css`, `static/vendor/**`).

## Cascade order

Keep stylesheet order deliberate. Broad foundations load first, narrow feature
styles load later, and the compatibility shim loads last:

1. vendor Bootstrap / icon / IHP styles
2. `tokens.css` - app design tokens and CSS custom properties
3. `bootstrap-bridge.css` - Bootstrap variable and component bridge
4. `layout.css` - document shell, page layout, authenticated header
5. `components/*.css` - shared app components
6. `overlays.css` - dialogs, toasts, pickers, overlay hosts
7. `features/*.css` / `features/<feature>/*.css` - feature-scoped styles
8. `../app.css` - compatibility-only shim; keep it minimal

When adding, moving, or splitting files, preserve selector order unless the
ticket explicitly calls for a semantic refactor. Add every new linked stylesheet
to both `Web/View/Layout.hs` and `Makefile` in the same cascade position.

## Ownership map

- **Tokens and palettes:** put semantic variables in `tokens.css` before using
  raw colour, spacing, radius, or shadow values elsewhere. Shift-type palette
  values belong with tokens/palette ownership, not duplicated inside roster or
  admin selectors.
- **Bootstrap bridge:** put global Bootstrap variable overrides or unavoidable
  Bootstrap component bridges in `bootstrap-bridge.css`. Keep these broad and
  documented by selector intent.
- **Layout chrome:** put `html`, `body`, `.app-shell`, `.app-content`,
  `.app-page*`, page headers, and global authenticated navigation in
  `layout.css`.
- **Shared components:** put reusable surfaces, menus/navigation, week toolbar,
  badges/status, public/auth surfaces, forms, buttons, tables, accordions,
  toggles, and admin primitives in focused `components/*.css` modules.
- **Overlays:** put workflow dialog, toast, picker, and overlay host styling in
  `overlays.css`.
- **Roster feature:** put roster-only selectors in focused
  `features/roster/*.css` modules. Current modules cover toolbar, week
  overview, staff panel, grid frame/cells, day actions, day columns, shift
  cards, responsive overrides, state badges/conflicts, and export/print. Keep
  feature selectors scoped to roster roots/prefixes such as `.roster-*`,
  `.day-column-*`, `.shift-card-*`, or the roster shell.
- **Timesheets feature:** put timesheet-only week/day/entry styling in
  `features/timesheets.css` (or `features/timesheets/*.css` if it grows). If a
  horizontal strip or dense control also serves roster, extract a shared
  component primitive instead of copying timesheet-specific CSS.
- **Other features:** put exports, leave, preferences, staff-documents, and Xero
  styles in their matching `features/*.css` files. Feature-only CSS should not
  redefine global `.btn`, `.form-*`, `.nav-*`, `.breadcrumb`, or `.app-*`
  behavior unless an explicit exception is documented.

## Examples

- A new roster day-column affordance belongs in the roster feature module that
  owns day columns. If it needs a new colour, add a semantic token first.
- A timesheet week strip and roster day strip should share a component primitive
  when their layout rules match; feature classes can remain as wrappers for JS
  and tests.
- A dialog footer or toast visual change belongs in `overlays.css` and the
  shared overlay helpers, not in a feature stylesheet.
- A form field spacing rule used by roster and admin belongs in a shared forms
  component module. A roster-only dense cell input rule stays in roster CSS until
  it becomes a documented dense-control primitive.
- Button, table, badge/status, menu, navigation, and accordion rules that apply
  across pages belong in shared component modules. Feature styles may compose
  those classes but should avoid overriding Bootstrap globally.
- Public/auth page surfaces belong in shared public/auth component CSS, while a
  feature-specific marketing or legal block belongs in that feature's stylesheet.

## Audit commands

- `bash ./bin/in-env ./bin/style-audit` is the hard gate. It fails on undefined
  CSS variables and Layout/Makefile stylesheet sync problems. It also prints
  existing warning-style findings for hardcoded colours, light Bootstrap
  utilities, and inline style attributes.
- `bash ./bin/in-env ./bin/css-inventory` is warning-only. It reports app-owned
  CSS line counts, files over the current size budget, raw colours outside
  token/bridge modules, feature stylesheets that mention app/global/Bootstrap
  selectors, simple stale-selector candidates with no HS/JS mention, and the
  Layout/Makefile asset-sync summary. Use it before and after split/refactor
  tickets to keep known debt visible without blocking early pure moves.

## Before adding CSS

1. Search for an existing selector, helper class, token, or component module.
2. Prefer shared semantic classes for reusable surfaces, controls, strips,
   badges, tables, and overlays.
3. Add or reuse semantic tokens before introducing raw colour, shadow, radius,
   or spacing values outside `tokens.css`.
4. Scope feature CSS by feature root or prefix; do not add broad global
   overrides from feature stylesheets.
5. Avoid global `.app-*`, `.btn`, `.form-*`, `.nav-*`, `.breadcrumb`, or
   Bootstrap utility overrides unless the module owns that shared concern and
   the exception is intentional.
6. Preserve cascade order during pure split/move work; do semantic selector
   rewrites in a separate ticket.
7. Keep modules focused. Split growing files before they become a mixed-purpose
   stylesheet; new app-owned CSS modules should normally stay well under 1,000
   lines, with existing oversize files treated as refactor debt.
8. Run `bash ./bin/in-env ./bin/style-audit` after stylesheet link, token, or
   architecture changes, and `bash ./bin/in-env ./bin/css-inventory` when you
   need the warning-only architecture report.
