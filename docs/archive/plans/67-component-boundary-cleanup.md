# Pipeline 67 - Component Boundary Cleanup

Read after `IMPLEMENTATION_PLAN.md`, `AGENTS.md`, and
`docs/archive/plans/59-code-smell-remediation.md`.

## Goal

Turn the 2026-04-30 read-only component-boundary review into a staged cleanup
plan. The aim is not broad style churn. The aim is to make high-churn parts of
the app easier to reason about by separating controller orchestration,
application services, projection/read-model construction, view rendering, CSS
ownership, and live-update protocol concerns.

Live status lives in repo-local `tk` tickets. This plan is durable design
context and sequencing guidance.

## Source Tickets

- `ir-18tm` - parent epic for this review: component boundary cleanup from the
  2026-04-30 scan.
- `ir-jhsv` - move Xero admin web response code out of `Application` namespace.
- `ir-yi7u` - decompose the timesheet controller around projection and
  live-surface modules.
- `ir-gj4q` - decompose leave requests and profile leave integration.
- `ir-tk23` - move shared domain and URL helpers out of the view namespace.
- `ir-u7c6` - split payroll export helpers into focused service modules.
- `ir-18ci` - split FWC MAPD sync into fetch, decode, curation, persistence,
  projection, and runner modules.
- `ir-a7dt` - normalize shared app-surface CSS and feature stylesheet
  ownership.
- `ir-lxfx` - extract shared week navigation and path helpers for roster and
  timesheets.
- `ir-ihv0` - centralize live-update scope identity and projection-backed
  live-surface definitions.

Related existing tickets:

- `ir-6vvh` - parent code smell remediation backlog.
- `ir-23k7` - completed first Admin/Xero split, useful history for `ir-jhsv`.
- `ir-36t6` - URL-encoding hardening, related to `ir-tk23`.
- `ir-w8dk` - reusable week controls, related to `ir-lxfx`.
- `ir-f2p4` and `ir-jooi` - live-fragment runtime work related
  to `ir-ihv0`.

## Current Findings

### 1. Timesheets and leave still have broad controllers

Roster is the cleanest local model: `Web/RosterWeeks/Projection.hs`,
`RenderData.hs`, `Responses.hs`, `LiveUpdates.hs`, `Dom.hs`, and related
feature modules keep the root controller mostly orchestration-focused.

Timesheets and leave still keep too many concerns in the controller and nearby
views:

- projection fetching and render model construction
- `LiveSurfaceDefinition` and fragment references
- HTMX and OOB response helpers
- form parsing and validation
- profile-specific leave fragment coupling

Use `ir-yi7u` and `ir-gj4q` to bring those features closer to the roster
pattern without changing behavior.

### 2. Xero admin still leaks web concerns into application modules

The first Admin/Xero split reduced root controller/view size, but several
`Application.Xero.Admin.*` modules still import `Web.Controller.Prelude` and
perform request/response work. That makes the namespace misleading: application
modules should own read models, service decisions, persistence, API calls, and
pure mapping logic; web modules should own params, redirects, toasts, HTMX/OOB
responses, and permission response choices.

Use `ir-jhsv` as a follow-up to `ir-23k7`.

### 3. Export and FWC MAPD sync are large mixed-concern services

`Application.Helper.Export` mixes export orchestration, report definitions,
read models, persistence, audit payloads, file naming, and rendering adjacency.
`Application.FwcMapd.Sync` mixes external payload types, API fetch/decode,
curation profiles, raw persistence, award projection, and runner orchestration.

These modules should be split only along stable, behavior-preserving boundaries.
Avoid a rewrite. Move declarations and helpers in stages and keep public
entrypoints stable.

### 4. Some domain helpers live in view modules

`Application.Helper.View` is now mostly a compatibility wrapper, but some
non-view callers still import it for helpers such as `isTrialStaff` and
`appendQueryParams`. This couples controllers, email helpers, projections, and
exports to a view namespace.

Use `ir-tk23` to introduce non-view homes for these helpers, while leaving
temporary view re-exports for compatibility during migration.

### 5. Shared CSS is still partly feature-owned

Shared toolbar and week-navigation styles are used by roster and timesheets but
are still defined in roster feature CSS. Leave list rules are duplicated between
roster and leave styles, and the leave stylesheet currently has an extra
closing brace at the end.

Use `ir-a7dt` for a narrow CSS ownership correction. Do not redesign the pages.

### 6. Live-update ownership is close but not complete

The Haskell side now sends `scopeKey` through live-surface config and websocket
messages. The JavaScript runtime still keeps a fallback `buildScopeKey` switch,
which duplicates protocol knowledge. Timesheet and leave surface definitions are
also not as centralized as roster.

Use `ir-ihv0` after `ir-yi7u` and `ir-gj4q`, so feature-owned live-surface
definitions exist before the JS fallback is retired.

### 7. Roster and timesheet week controls repeat path and toolbar logic

Roster week paths are duplicated between controller and view code. Timesheets
already has a path helper, but it is still coupled to view helper imports. The
toolbar shape is converging across roster and timesheets.

Use `ir-lxfx` after or alongside `ir-tk23`. Extract only the path and UI pieces
that are genuinely shared.

## Stage Order

### Stage 0 - Remeasure before editing

Before each slice, re-run focused searches because this repo has active
parallel work:

```bash
git status --short
rg -n "import Web.Controller.Prelude" Application/Xero/Admin
rg -n "import Application.Helper.View|appendQueryParams|isTrialStaff" Application Web
rg -n "app-surface-toolbar|leave-request-list|function buildScopeKey" static Web Application
```

Do not revert unrelated dirty files. Work with nearby changes if they affect the
slice.

### Stage 1 - Fix the highest-risk namespace boundaries

Start with `ir-jhsv` and `ir-tk23`.

`ir-jhsv` reduces confusion around what is web/controller code versus Xero
application/service code. `ir-tk23` gives later export, path, email, and
projection cleanup a proper non-view helper home.

### Stage 2 - Decompose feature controllers

Handle `ir-yi7u` and `ir-gj4q`.

Use roster modules as the local pattern. Keep routes, action types, path
semantics, DOM ids, HTMX targets, toast mounts, live-surface data attributes,
and authorization behavior stable.

### Stage 3 - Centralize live-surface ownership

Handle `ir-ihv0` after timesheet and leave feature modules exist.

Prefer server-provided `scopeKey` values. Remove or quarantine JavaScript
fallback scope-key construction only after all live-surface config and websocket
messages are verified to carry `scopeKey`.

### Stage 4 - Split large application services

Handle `ir-u7c6` and `ir-18ci`.

Keep public entrypoints stable and move code along obvious responsibility
boundaries. For exports, preserve generated output where practical. For FWC MAPD
sync, preserve raw storage and projection behavior unless a separate ticket
authorizes a business change.

### Stage 5 - Normalize shared UI structure

Handle `ir-a7dt` and `ir-lxfx`.

These can run earlier if file ownership does not overlap with feature work.
Keep them narrow: shared CSS primitives and shared week path/navigation helpers,
not visual redesign.

## Verification

For Haskell-only extraction:

```bash
bash ./bin/in-env typecheck
```

Add focused Hspec where extracted logic becomes easier to test or where a
controller boundary changes:

```bash
bash ./bin/in-env hspec-test --match "Timesheets"
bash ./bin/in-env hspec-test --match "Leave"
bash ./bin/in-env hspec-test --match "Xero"
```

For CSS or view changes, use focused screenshots or Playwright specs for the
touched pages. Prefer the repo wrappers:

```bash
bash ./bin/in-env e2e e2e/timesheets.spec.ts
bash ./bin/in-env e2e e2e/leave.spec.ts
bash ./bin/in-env screenshot-page /RosterWeeks test-results/roster-boundary-check.png --selector '#roster-content'
```

For export changes, compare representative generated artifacts before and after
where practical. For live-update changes, run focused live-fragment tests and at
least one browser-level flow that exercises an actor update plus a passive
viewer refresh.

## Guardrails

- Keep each slice behavior-preserving unless the ticket explicitly names a bug.
- Preserve route/action types, current URLs, query parameters, DOM ids,
  `hx-*` attributes, live-surface metadata, websocket message shapes, and toast
  mount ids.
- Do not introduce a broad framework abstraction. Extract named helpers and
  small records only when they remove real duplication.
- Do not mix structural moves with copy, layout, or visual redesign.
- Do not run broad formatting over untouched modules.
- Update relevant `AGENTS.md` files only if a reusable pattern or gotcha is
  discovered while implementing.

## Fresh Agent Prompt

Use this prompt for a fresh implementation agent:

```text
You are working in /home/beau/documents/projects/ihp-roster.

Goal: implement the component-boundary cleanup tracked by tk epic ir-18tm and
docs/archive/plans/67-component-boundary-cleanup.md. This is a staged, behavior-preserving
refactor. Do not redesign UI or change product behavior unless a ticket
explicitly calls for it.

Start by reading:
- AGENTS.md
- IMPLEMENTATION_PLAN.md
- docs/archive/plans/59-code-smell-remediation.md
- docs/archive/plans/67-component-boundary-cleanup.md
- tk show ir-18tm
- tk ready

Then choose the highest-impact ready child ticket under ir-18tm. Prefer this
order unless current dependencies or conflicts say otherwise:
1. ir-jhsv - move Xero admin web response code out of Application namespace.
2. ir-tk23 - move shared domain and URL helpers out of the view namespace.
3. ir-yi7u - decompose timesheet controller around projection/live-surface modules.
4. ir-gj4q - decompose leave requests and profile leave integration.
5. ir-ihv0 - centralize live-update scope identity and surface definitions.
6. ir-u7c6 - split payroll export helper into focused service modules.
7. ir-18ci - split FWC MAPD sync into focused modules.
8. ir-a7dt and ir-lxfx - normalize shared CSS and week navigation/path helpers.

Before editing, run git status --short and focused rg searches for the ticket.
Do not revert unrelated dirty work. Use the roster decomposition as the model
for timesheets and leave. Keep routes, action types, DOM ids, hx attributes,
live-surface metadata, websocket scope shapes, toast mounts, and query
parameters stable.

For each slice, make the smallest coherent extraction, then run:
- bash ./bin/in-env typecheck
- focused hspec-test or e2e/screenshot checks when the touched boundary affects
  controller behavior, live fragments, exports, or UI layout.

Close or update only the tk ticket you actually complete. If you discover a
new durable convention, update the relevant AGENTS.md concisely.
```
