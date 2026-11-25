# Architecture Guide

Use code and subsystem README/SPEC files for implemented structure.
The focused `repository-wiring-check` checks controller, Layout, enum, and
workflow policy directly from source.

## Bepis And IHP

IHP remains the outer web lifecycle: routes, `Controller` instances,
`beforeAction`, request context, QueryBuilder, generated model types, HSX, and
middleware stay IHP-native. Bepis adds typed policy and effect meaning inside
that lifecycle through `runBepis`, generated contracts, and helpers that emit
facts while performing real authorization, audit, live-update, or response
effects.

A custom typed controller dispatcher was deliberately deferred; see
`controller-spec-prototype.md` for the rationale and revisit trigger.

## Ownership Map

- `Web/Types.hs`, `Web/Routes.hs`, and `Web/FrontController.hs`: web wiring.
- `Web/Controller/`: request handling, authorization orchestration, parameters,
  and response choice.
- `Web/View/`: server-rendered HSX and layout.
- `Web/RosterWeeks/`, `Web/Timesheets/`, `Web/LeaveRequests/`: feature
  projections, paths, responses, and local domain seams.
- `Application/Helper/`: shared services, contracts, exports, pay, live-update,
  and view helpers.
- `Application/Xero/`, `Application/FwcMapd/`, and
  `Application/PublicHolidays/`: named integration/domain boundaries.
- `Application/Schema.sql`: canonical fresh schema and generated-model source.
- `Application/Migration/`: customer-data-preserving deployed upgrade path.
- `frontend/ts/`: authored browser mechanics; Haskell owns business meaning.
- `static/`: checked-in generated bundles, local assets, and CSS.
- `Config/nix/README.md` and `Config/nix/production-*-inventory.tsv`: explicit
  production Haskell source and executable packaging authority.

Business authority is scoped by `venue_memberships`; founder support authority
is a separate platform role. Payroll-adjacent history must remain reproducible.
See root and subsystem `AGENTS.md` files for mandatory safety and verification
rules.

## Production Build Boundary

Production Haskell source, scripts, executable roots, and direct package
ownership are explicit inventories under `Config/nix/`; ambient source files or
packages in the development GHC environment are not production authority.
Frontend-contract generators are a separate build output, while shared checked
Haskell declarations remain the single runtime/tooling authority. Production
app-library output is static-only and structural inventory checks are blocking; builder RSS, cgroup memory, and swap are comparative evidence rather
than release ceilings.

See ADRs
`docs/adr/0006-operation-local-frontend-contract-evidence.md` and
`docs/adr/0007-explicit-production-haskell-package-boundary.md` for rationale,
`Config/nix/README.md` for ownership and maintenance, and
`docs/runbooks/production-build-profiling.md` for clean-builder diagnosis.

Current observability boundaries are summarized in `observability.md`; exact
profiling procedures live in `docs/runbooks/performance-profiling.md`, and
production operation/security procedures live in
`docs/runbooks/production-observability.md`.
