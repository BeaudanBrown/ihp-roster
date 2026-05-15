# Typed Live Surface Architecture

Status: active

Tickets:

- `ir-nnfx` - parent epic
- `ir-ix0n` - surface-indexed live surface types
- `ir-lxkv` - surface-owned authorization for subscriptions and fragments
- `ir-3wwj` - mutation and actor-response helpers
- `ir-qd8e` - reusable live surface contract tests
- `ir-fgtz` - smaller declarative JavaScript transport
- `ir-nxqx` - invalidation coalescing and optional batched refetch
- `ir-ukkn` - LiveBus abstraction for process boundaries
- `ir-tqwl` - migration and documentation

Related tickets:

- `ir-jooi` - surface projection cache work
- `ir-f2p4` - focused-field protection cleanup

Living docs to update:

- `Application/Helper/LiveUpdate.SPEC.md`
- `Web/Controller/AGENTS.md`
- `Web/View/AGENTS.md`
- `static/AGENTS.md`
- feature-local specs or agent docs for roster, timesheets, leave, support, and
  admin surfaces as they migrate

Archived context:

- `docs/archive/plans/56-declarative-live-fragments.md`
- `docs/archive/plans/62-live-fragment-system-refactor.md`

## Goal

Make adding or expanding a live section a local, typed feature change instead
of a manual wiring exercise across scope constructors, fragment refs, DOM ids,
URLs, authorization checks, controller broadcasts, view metadata, tests, and
JavaScript behavior.

## Current State

The implemented architecture is sound: server-rendered HTML remains the source
of truth, the actor gets an immediate HTMX fragment or out-of-band update, and
passive viewers receive websocket invalidations that cause authorized HTTP
fragment refetches.

The weak points are ergonomics and guarantees. Scopes and fragment keys are
centralized global types, simple surfaces can still hand-build refs and URLs,
authorization is easy to duplicate between websocket and HTTP paths, controller
mutations manually thread actor and passive-viewer update paths, and tests do
not yet provide a compact reusable proof that a surface config, fragment route,
target id, and auth rule all agree.

## Intended Contract

- A live surface definition owns its surface key, fragment type, live scope,
  authorization rule, default resync fragments, fragment refs, render hook,
  request decoration, and wire conversion.
- Feature modules own their local fragment enums. Global wire payloads remain
  simple JSON at the protocol edge, not the authoring interface for every
  feature.
- A fragment cannot be broadcast on the wrong surface without crossing an
  explicit type-erasing boundary.
- Websocket subscription authorization and HTTP fragment authorization use the
  same surface-owned rule.
- Mutations use a helper that pairs the actor HTMX response with passive
  invalidation, source-client handling, dedupe, and optional projection warming.
- The browser runtime stays generic: discover surface configs, keep one
  websocket per tab, subscribe scopes, decorate matching HTMX requests, refetch
  mounted fragments, preserve focused fields through declared policies, and
  swap returned HTML.
- Performance-sensitive surfaces can coalesce repeated invalidations and
  collapse many small fragments into a larger fragment by surface policy.
- The in-process live-update store remains the default, but a LiveBus boundary
  makes later multi-process or background-job fanout possible without rewriting
  controllers.

## Implementation Plan

1. Build the typed surface contract as a compatibility layer over the existing
   protocol (`ir-ix0n`).
2. Move authorization into the surface contract and make migrated fragment
   endpoints use the same rule as websocket subscriptions (`ir-lxkv`).
3. Add mutation helpers so controllers declare the changed typed fragments once
   and get actor refresh plus passive invalidation consistently (`ir-3wwj`).
4. Add reusable contract tests for config JSON, fragment routes, target ids,
   authorization, and mounted metadata (`ir-qd8e`).
5. Shrink the JavaScript runtime to the declarative transport responsibilities
   and reconcile focused-field protection with the existing cleanup ticket
   (`ir-fgtz`, related `ir-f2p4`).
6. Add coalescing and optional batched refetch for hot surfaces after the typed
   fragment metadata exists (`ir-nxqx`, related `ir-jooi`).
7. Extract the LiveBus boundary while preserving the current single-process
   implementation (`ir-ukkn`).
8. Migrate representative simple and projection-backed surfaces, then update
   local docs with the new add-a-live-fragment workflow (`ir-tqwl`).

## Exit Criteria

- Adding a live fragment to a migrated feature is isolated to that feature's
  surface definition, fragment route/render function, and mutation call site.
- At least support/admin, one of leave or timesheets, and roster are migrated or
  have explicit remaining tickets.
- Contract tests cover migrated surfaces without requiring browser automation
  for ordinary target/auth/config drift.
- Focused Playwright coverage remains only for browser behavior such as
  subscription lifecycle, resync, focus protection, no full-page navigation, and
  multi-view updates.
- Durable rules are moved into the live-update spec and local agent docs before
  this workstream is closed.
