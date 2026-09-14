# App CSS Architecture

App-owned CSS is split into directly linked stylesheets. `Web/View/Layout.hs`
is the sole ordered stylesheet inventory and loads every asset with `assetPath`;
style-audit checks it for missing, duplicate, and unlinked app CSS. IHP's optional
`prod.js`/`prod.css` concatenation is disabled for this app; production serves
the split static assets directly. Do not use app-owned CSS `@import`, do not add
a bundler, and do not edit third-party CSS (`static/vendor/**`).

## Cascade order

Keep stylesheet order deliberate. Broad foundations load first and narrow
feature styles load later:

1. vendor Bootstrap / icon / IHP styles
2. `tokens.css` - app design tokens and CSS custom properties
3. `palette.css` - persisted palette key values shared by roster/admin colour UI
4. `bootstrap-bridge.css` - Bootstrap variable and component bridge
5. `layout.css` - document shell, page layout, authenticated header
6. `components/*.css` - shared app components
7. `overlays.css` - dialogs, toasts, pickers, overlay hosts
8. `features/*.css` / `features/<feature>/*.css` - feature-scoped styles

When adding, moving, or splitting files, preserve selector order unless the
ticket explicitly calls for a semantic refactor. Add every new linked stylesheet
to `Web/View/Layout.hs` in the intended cascade position.

## Display density

`data-ui-scale` is the app-wide display-density hook. It currently supports
`compact`, `normal`, and `large`; unset is the same as `normal`. Keep normal
values equal to the existing default experience, then derive compact/large from
shared token scales in `tokens.css`:

- `--app-density-font-scale` for text tokens
- `--app-density-space-scale` for spacing tokens
- `--app-density-control-scale` for control heights and control-adjacent widths

Shared surfaces and Bootstrap bridges should consume `--text-*`, `--app-space-*`,
and `--app-control-height-*` rather than hard-coding one-off density values.
Feature-specific density, such as roster grid widths, may still add feature
variables, but it should remain layered on top of the app-wide scale instead of
becoming an isolated zoom system.

## Ownership map

- **Tokens and palettes:** put semantic variables in `tokens.css` before using
  raw colour, spacing, radius, or shadow values elsewhere. Persisted shift-type
  palette key values and `data-roster-shift-colour` mappings belong in
  `palette.css`, not duplicated inside roster or admin selectors.
- **Bootstrap bridge:** put global Bootstrap variable overrides or unavoidable
  Bootstrap component bridges in `bootstrap-bridge.css`. Keep these broad and
  documented by selector intent.
- **Layout chrome:** put `html`, `body`, `.app-shell`, `.app-content`,
  `.app-page*`, page headers, and global authenticated navigation in
  `layout.css`.
- **Shared components:** put reusable surfaces, generated SidePanel layout,
  menus/navigation, week toolbar, badges/status, horizontal strip primitives,
  public/auth surfaces, forms,
  dense controls, buttons, tables, accordions, toggles, and admin primitives in
  focused `components/*.css` modules.
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
- **Other features:** put leave, preferences, staff-documents, and Xero styles
  in their matching `features/*.css` files. Create and link an export feature
  stylesheet only when export-specific CSS exists. Feature-only CSS should not
  redefine global `.btn`, `.form-*`, `.nav-*`, `.breadcrumb`, or `.app-*`
  behavior unless an explicit exception is documented.

## Examples

- A new roster day-column affordance belongs in the roster feature module that
  owns day columns. If it needs a new colour, add a semantic token first.
- A timesheet week strip and roster day-column strip should use the shared
  `app-horizontal-frame`, `app-horizontal-grid`, and `app-horizontal-panel`
  primitives when their layout rules match; generated horizontal-scroll roles
  remain the browser discovery boundary and transient classes stay adapter-local.
- A dialog footer or toast visual change belongs in `overlays.css` and the
  shared overlay helpers, not in a feature stylesheet.
- Leave request list/accordion rules belong in `features/leave.css`; shared
  accordion chrome belongs in `components/accordions.css`.
- Admin setting rows and admin-specific colour controls belong in
  `components/admin.css`/`components/admin-responsive.css`; if the same control
  appears outside admin, extract a shared component primitive first.
- A form field spacing rule used by roster and admin belongs in a shared forms
  component module. Roster dense cells compose `app-dense-control` and
  `app-dense-static` for reusable transparent dense controls while keeping
  roster sizing and states in roster modules.
- Button, table, badge/status, menu, navigation, and accordion rules that apply
  across pages belong in shared component modules. Compact icon/actions compose
  `app-icon-button` or `app-compact-action-button`; feature styles may compose
  those classes but should avoid overriding Bootstrap globally.
- Public/auth page surfaces belong in shared public/auth component CSS, while a
  feature-specific marketing or legal block belongs in that feature's stylesheet.

## Audit commands

- `bash ./bin/in-env ./bin/style-audit` is the hard gate. It fails on
  undefined CSS variables; missing, duplicate, or unlinked Layout stylesheet
  assets; app-owned CSS `@import`; files over the `CSS_LINE_BUDGET` budget; raw
  colour literals outside token/palette/bridge modules; and unexpected
  app/global/Bootstrap selectors in feature modules. The remaining light
  Bootstrap utility and inline-style sections are review output only. Inline
  styles that only set CSS custom properties through named helper functions are
  allowed so dynamic geometry stays in CSS-owned rules.
- Intentional exceptions must stay rare and explicit. Prefer moving CSS to the
  correct shared module or adding a token first; if an exception is genuinely
  durable, add the narrowest path/selector allowlist entry in `bin/style-audit`
  with a nearby comment or ticket note explaining ownership.
- `bash ./bin/in-env ./bin/style-audit --report` runs the same hard gate and
  additionally prints Layout's runtime order, all app-owned CSS line counts, and
  the reviewed app/global/Bootstrap-like feature selectors. Use it before and
  after CSS architecture work when the compact debt report is useful.

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
   architecture changes; add `--report` when you need the ordered inventory and
   compact architecture report.
