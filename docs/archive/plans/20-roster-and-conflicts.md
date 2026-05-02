# Pipeline 20 — Roster and Conflicts

Read after `IMPLEMENTATION_PLAN.md`. Respect the auth/scoping rules from pipelines 00 and 10.

## Goal

Treat the roster week page as the primary operational surface, including staff-side management and conflict visibility.

## Scope

- roster week navigation
- live/draft controls and import flow
- roster-side staff management UX
- quarter-hour picker reuse
- conflict engine and rendering
- navigation/header polish tied to roster workflow

## Slices

### 2.1 Staff management migration into roster workflow
- **Status:** [x]
- **Related slices:** 2.1a, 2.1b, 2.1c, 2.1d, 2.2

### 3.1 Universal week navigation and manager auto-create
- **Status:** [x]
- **Related slices:** 3.1a, 3.1b

### 3.2 Roster settings and live visibility controls
- **Status:** [x]
- **Related slices:** 3.2a, 3.2b

### 3.3 Import overwrite workflow
- **Status:** [x]
- **Related slices:** 3.3a, 3.3b

### 3.4 Roster page as manager/admin operations hub
- **Status:** [x]
- **Related slices:** 3.4a, 3.4b, 3.4c

### 3.5 Reusable quarter-hour modal time picker
- **Status:** [x]

### 4.1 Conflict engine baseline (non-pay)
- **Status:** [x]

### 4.2 Late-to-Early start-gap conflict
- **Status:** [x]

### 4.3 Conflict priority rendering
- **Status:** [x]

### 4.4 Global navigation header and placeholder controllers
- **Status:** [x]

### 8.1 Bootstrap roster grid UX pass
- **Status:** [ ]
- **Goal:** Refine the roster UI once the deeper business-logic foundations are stable.

## Active Concerns

- Do not reintroduce global-role assumptions in roster controller/view logic.
- Any new roster queries should use venue-scoped helpers from pipeline 10.
- Staff editing entrypoints should remain aligned with the shared overlay architecture.

## Primary Files

- `Web/Controller/RosterWeeks.hs`
- `Web/View/RosterWeeks/*`
- `Application/Helper/View.hs`
- `Application/Helper/Conflict.hs`
- `static/app.css`
- `static/app.js`
- roster-related e2e tests under `e2e/`
