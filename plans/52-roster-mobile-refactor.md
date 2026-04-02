# Roster Mobile Refactor Plan

Read after `IMPLEMENTATION_PLAN.md`, `plans/20-roster-and-conflicts.md`, and `plans/51-mobile-responsive-foundations.md`.

## Goal

Use the roster page as the first concrete cross-device refactor surface.

The target is not "make the desktop roster tiny enough to fit on a phone."
The target is:

- mobile roster creation remains usable
- page-level layout stays stable on phone and tablet
- dense roster editing stays inside a controlled scroll surface
- the page becomes structurally ready for a later, better mobile presentation where needed

## Current Baseline To Protect

The current mobile roster contract is:

- authenticated users can reach the roster on phone and tablet
- week navigation still works on narrow viewports
- add/remove day-row controls still work on narrow viewports
- the roster grid stays inside a local `.table-responsive` wrapper instead of forcing whole-page horizontal overflow
- the staff panel stops behaving like a sticky desktop sidebar and falls back to normal document flow below desktop breakpoints
- the core editable cells remain reachable on narrow viewports

These expectations are covered by `e2e/roster-mobile.spec.ts`.

## Refactor Direction

### 1. Separate page structure from table structure

- keep the page shell, header, controls, grid wrapper, and staff panel as distinct layout regions
- avoid letting table internals drive the whole page layout
- make the roster content region explicitly responsible for any horizontal scrolling

### 2. Promote a mobile-first control hierarchy

- keep week navigation and the most common actions visible before the full grid
- avoid requiring the sidebar to be visible before the user can interact with the main roster surface
- treat the roster grid as the primary mobile interaction surface; the staff panel is secondary

### 3. Make overflow intentional

- the viewport should not scroll sideways
- the roster grid may scroll sideways inside its wrapper when the content requires it
- any future sticky or capped-height behavior should stay desktop-only unless deliberately reintroduced for tablet

### 4. Prepare for alternative mobile presentation

- if the grid remains too dense for efficient phone editing, introduce a focused mobile editing path instead of compressing every column further
- likely candidates:
  - one-day focus mode
  - one-row editor dialog
  - mobile live-view presentation separate from the full editing grid

## Suggested Refactor Order

1. stabilize roster page regions and spacing without changing the editing model
2. improve narrow-viewport control placement and visual priority
3. simplify the mobile relationship between grid and staff panel
4. only then decide whether phone editing needs a dedicated alternate flow

## Testing Contract

Keep Playwright checks in place while refactoring:

- `e2e/roster-mobile.spec.ts` for phone/tablet baseline behavior
- existing desktop roster specs for sticky sidebar and denser desktop workflows

If the product decision changes from "mobile-usable grid" to "separate mobile editor", update the tests to enforce that new contract explicitly rather than weakening them indirectly.
