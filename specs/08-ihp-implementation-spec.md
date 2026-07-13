# IHP Implementation Architecture

This file describes cross-cutting IHP implementation expectations. It is not a
feature plan. Use `IMPLEMENTATION_PLAN.md`, `docs/workstreams/`, and GitHub
Issues for future work routing.

## Schema

- Define entities in `Application/Schema.sql`.
- Regenerate generated types after schema changes.
- Add first-class venue ownership fields to venue-owned records.
- Keep business-role authority on `venue_memberships`, not `users`.
- Keep platform support capability separate from venue roles.
- Add explicit historical reproducibility for payroll-adjacent records through
  immutable version/history records.
- Do not add sensitive future data directly to `users` or `staff` without a
  dedicated spec.

## Controllers

Each new controller requires:

1. Type in `Web/Types.hs`.
2. `AutoRoute` in `Web/Routes.hs`.
3. Mounting in `Web/FrontController.hs`.
4. Implementation in `Web/Controller/*`.
5. Focused Hspec coverage under `Test/Controller/`.

Controllers own request params, authorization response choices, redirects,
HTMX/OOB response shape, and orchestration. Domain services, projections, and
render models should move into feature/application modules when they grow.

## Views

- HSX views live under `Web/View/*`.
- Layout integration lives in `Web/View/Layout.hs`.
- Bootstrap and semantic app classes are preferred.
- Shared page/panel/overlay helpers live under `Application/Helper/View/`.
- Authenticated pages use the global header and must preserve the nav order
  documented in root `AGENTS.md`.
- High-frequency in-place workflows should use HTMX fragments and shared
  overlay helpers.

## Helpers And Services

- Shared controller helpers live under `Application/Helper/Controller*`.
- Shared view helpers live under `Application/Helper/View/*`.
- Export helpers live under `Application/Helper/Export/`.
- Xero application logic lives under `Application/Xero/`.
- Feature read models and response helpers should live next to their feature
  modules when they are not truly global.

## Realtime

- Actor-side mutations use HTMX fragments/OOB swaps.
- Passive viewers use websocket invalidation plus authorized fragment refetch.
- Haskell declares live surfaces and fragment refs; JavaScript owns generic
  subscribe, resync, request decoration, refetch, swap, and protection policy
  behavior.
- Invalidation payloads stay structural and must not broadcast rendered HTML.

See `Application/Helper/LiveUpdate.SPEC.md` for the detailed contract.

## Data Consistency

- Publishing, approval, export, Xero submission, and sensitive role changes
  should use safe transaction boundaries when side effects are coupled.
- Audit/event writes should participate in the same transaction as the business
  action where feasible.
- Export snapshots and Xero submissions must use defined data scopes and
  historical pay/config context.
- Corrections must preserve traceability rather than silently overwriting
  business history.
