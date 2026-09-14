# Architecture Map

Use source-derived architecture tooling for implemented structure. Subsystem
behavior belongs in nearby code and README/SPEC files; this document only maps
major ownership boundaries and query entry points.

## Deterministic Evidence

Project commands are declared in `.pi/architecture.json`. Whole-project outputs
are ignored under `output/architecture/`; focused query artifacts go under
`.pi/tmp/architecture-query/` or `.pi/tmp/architecture-trace/`.

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-check-fresh
```

Use Pi's `architecture_queries` to discover current query names and arguments,
then `architecture_query` for focused controller, request-flow, schema-table,
module, realtime, generated-contract, or trace evidence. A missing facts artifact
is generated automatically. Existing facts are accepted without regeneration
only when their complete source, generated-contract, and parser/policy fingerprint
is current; stale or legacy facts fail closed and direct callers must run
`bash ./bin/in-env architecture-facts` before retrying. Queries report source
provenance and confidence where relationships are heuristic. Do not treat a
source scan as a compiler-perfect call graph or commit generated diagrams unless
a ticket explicitly changes that policy.

The architecture gate owns closed wiring parity:

- controllers declared by `Web/Types.hs` are routed by `Web/Routes.hs` and
  mounted by `Web/FrontController.hs` exactly once;
- top-level `frontend/ts/app*.ts` entrypoints are loaded through
  `Web/View/Layout.hs` exactly once;
- authenticated navigation and runtime assets follow the Layout policy;
- intentional wiring exceptions require an owner and reason in
  `scripts/architecture/wiring-policy.mjs`.

Generated JavaScript byte drift remains frontend-owned. Architecture facts and
checks are implemented under `scripts/architecture/`; inspect those sources
rather than copying their current entity or query inventories into prose.

## Bepis And IHP

IHP remains the outer web lifecycle: routes, `Controller` instances,
`beforeAction`, request context, QueryBuilder, generated model types, HSX, and
middleware stay IHP-native. Bepis adds typed policy and effect meaning inside
that lifecycle through `runBepis`, generated contracts, and helpers that emit
facts while performing real authorization, audit, live-update, or response
effects.

Prefer typed behavior over parallel metadata. Architecture extraction should
use, in order:

1. Haskell-owned Bepis runner, fact, and generated contracts;
2. app-owned Surface and frontend contract registries;
3. source scans for usage locations;
4. explicit low-confidence naming fallbacks.

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
app-library output is static-only and deterministic output/inventory budgets are
blocking; builder RSS, cgroup memory, and swap are comparative evidence rather
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
