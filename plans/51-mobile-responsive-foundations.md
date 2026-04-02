# Mobile And Responsive Foundations

Read after `IMPLEMENTATION_PLAN.md`, `plans/20-roster-and-conflicts.md`, and `plans/30-timesheets-and-leave.md`.

## Goal

Establish a durable cross-device UI direction for the app so future work does not keep solving mobile one screen at a time.

The product stance is:

- the roster creator must remain usable on mobile, even if extended editing is still more efficient on desktop
- live roster viewing is a first-class desktop and mobile surface
- leave requests should be treated as mobile-first
- timesheets should be treated as mobile-friendly by default
- admin/config remains desktop-primary and can trail the other surfaces

## Design Direction

Treat responsiveness as three different modes rather than one generic CSS exercise:

1. stacked forms and cards
   - best for leave, timesheets, profile, support, and most dialogs
2. contained horizontal scroll
   - acceptable for dense operational tables when the editing model is still useful on phone
   - roster creator can use this mode as a baseline
3. alternate mobile presentation
   - required when the desktop information architecture is too dense to scan on a phone
   - live roster viewing is the strongest candidate for this mode

## Cross-Device UI Rules

- keep page-level horizontal overflow off the `body` and `html`; if a dense surface needs width, its own container must own the overflow
- prefer one-column stacking below the desktop breakpoints; do not rely on squeezed multi-column layouts as the mobile story
- dialogs must fit within the viewport width without clipped buttons or horizontal scroll
- touch actions should not depend on hover and should stay comfortably tappable
- keep page shells and major fragments stable so HTMX and live updates work the same way across devices
- use compact controls only when they remain tap-friendly; operational density does not justify tiny unusable targets
- distinguish between `desktop-primary but still usable on phone` and `mobile-first`; do not apply one standard to every page

## Surface Priorities

### Roster creator

- maintain mobile usability now
- preserve contained horizontal scroll instead of letting the whole page overflow
- avoid introducing desktop-only assumptions in new controls
- if a future edit flow becomes too dense for mobile, consider a mobile-specific row or day editor rather than forcing the whole desktop table into narrower widths

### Live roster viewing

- optimize for today-first, fast scanning, and readable shift blocks
- plan for a dedicated mobile view if the desktop grid remains too dense

### Leave requests

- move toward a mobile-first list/card presentation
- keep create/edit workflows dialog-friendly on small viewports

### Timesheets

- preserve the existing card/day-section structure
- treat dialogs and entry cards as the primary responsive unit

### Admin/config

- keep non-broken on smaller screens
- defer heavy optimization until the operational surfaces above are in better shape

## Testing Direction

Use Playwright to enforce responsive behavior as a product contract, not just for screenshots.

The minimum cross-device check set should cover:

- collapsed authenticated navigation
- no page-level horizontal overflow on mobile-first surfaces
- contained overflow for dense tables such as the roster grid
- workflow dialogs fitting inside phone-sized viewports
- route smoke coverage for roster, leave, and timesheets on mobile and tablet

Visual snapshots are useful, but only after the structural assertions above exist. Prefer seeded, stable shells and focused component screenshots over broad full-page diffs for highly dynamic pages.
