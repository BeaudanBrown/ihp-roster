# Architecture Agent Guidelines

This directory documents durable architecture understanding for Bepis. Prefer current code, schema, generated types, and deterministic architecture outputs over hand-drawn assumptions.

## Deterministic Architecture Tooling

Project-local architecture commands are declared in `.pi/architecture.json` and are intended for Pi's `architecture_commands`, `architecture_command`, `architecture_queries`, and `architecture_query` tools.

Whole-project generated outputs are written under `output/architecture/`, which is gitignored initially. Focused query outputs are written under `.pi/tmp/architecture-query/` or `.pi/tmp/architecture-trace/`.

Focused queries share one fact-currency boundary. Facts record a SHA-256 fingerprint of every scanned Haskell/frontend file, generated Bepis contract input, and fact-parser/policy source. A missing facts artifact is generated automatically; an existing artifact is queried only when its complete fingerprint is current. Stale or legacy facts fail closed with the recovery command `bash ./bin/in-env architecture-facts`; current facts are read without regeneration.

Use these wrappers from the project environment:

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-wiring-registry-test
bash ./bin/in-env architecture-schema
bash ./bin/in-env architecture-web-map
bash ./bin/in-env architecture-module-graph
bash ./bin/in-env architecture-runtime-overlay
bash ./bin/in-env architecture-check-fresh
```

For focused questions, prefer structured queries through Pi when available:

- `component`: generic controller/action/table/module neighborhood diagrams.
- `controller`: grouped controller/action surface reports.
- `request-flow`: static action request-flow reports with source provenance and
  heuristic confidence warnings.
- `realtime-usage`: live freshness usage metrics/diagrams.
- `generated-contracts`: backend-owned contract/codecs to generated TypeScript
  and frontend consumer reports.
- `table`: classified schema neighborhoods with audit edge filtering.
- `module`: filtered module dependency neighborhoods.
- `trace`: OpenTelemetry trace timing diagrams from profile artifacts.

Do not commit generated architecture outputs unless a future ticket explicitly changes that policy.

## Closed Wiring Registries

`Web/Types.hs` controller declarations are the canonical controller set; every
controller must have exactly one `AutoRoute` instance in `Web/Routes.hs` and one
`parseRoute` mount in `Web/FrontController.hs`. Custom routes remain part of
that parity. Websocket applications are a separate mount kind and do not enter
the controller set.

Every top-level `frontend/ts/app*.ts` entrypoint is a globally built bundle and
must appear exactly once as its `/app*.js` output in `Web/View/Layout.hs`.
Generated-file byte drift remains owned by `frontend-drift-check`; this
architecture gate owns only authored-entrypoint/Layout parity. Rare intentional
exceptions belong in `scripts/architecture/wiring-policy.mjs` with an
accountable subsystem owner and specific reason. Ownerless, reasonless,
duplicate, or stale exceptions fail the gate.

## Adopted Workflow Import Boundaries

`workflow-boundaries.mjs` under `scripts/architecture/` owns a small, explicit
set of adopted module roles. `architecture-facts` records observed imports,
owners, consumed exceptions and violations; the architecture gate and
`conventions` query consume that same evidence. Changes to its parser or policy
invalidate the fact fingerprint. Fixtures run in `verify-tooling`; run them
alone with `bash ./bin/in-env node --test scripts/architecture/workflow-boundaries.test.mjs`.

The guard rejects Application-to-Web imports, mutation-to-adopted-workflow/
response/view imports, workflow-to-adopted-response imports, response-to-adopted-
mutation imports, and direct passive-publisher imports in workflow/response
owners. It permits the exact named response import exception only with explicit
`type` namespace selectors (not bare uppercase names or constructors); missing
owners/reasons, duplicate, unknown, broad or stale exceptions fail. Check
source-line diagnostics in both positive and deliberately violating fixtures
when extending roles. Unadopted modules are not inferred from their names.

This is lexical import evidence, not a compiler call graph: facade reexports,
local IO, implicit contexts, rollback and subjective depth still need review and
semantic tests. No blanket IHP import ban, business-effects inventory or
file/export-count policy. Keep generated-contract and Weeder authority intact.
The retained extension contract lives in `Web/Controller/AGENTS.md`, not a
parallel provisional workstream.

## Bepis-IHP Boundary

When documenting or inspecting controller architecture, keep IHP as the outer
framework boundary. Do not replace IHP routes, `Controller` instances,
`beforeAction`, request context, HSX rendering, QueryBuilder, generated types, or
middleware with a parallel app framework. Bepis-specific semantics should be a
thin `runBepis` boundary plus helper-emitted runtime facts inside the IHP
lifecycle.

Prefer typed behavior over standalone metadata. Architecture extraction should
classify controller/action facts in this order:

1. typed Bepis runner/fact contracts from Haskell (`runBepis`, `BepisFact`, and
   `emitBepisFact`);
2. app-owned live-surface and generated-contract registries;
3. static source/call scans for usage location only;
4. naming-convention fallback.

Report provenance and confidence whenever a query uses source scanning or naming
fallback. Do not present heuristic request-flow, table-use, or realtime edges as
compiler-perfect truth.

## Flexibility

Keep architecture tooling adaptable:

- Model observed source facts and relationships before drawing diagrams.
- Add source provenance and confidence when scanners infer relationships; never
  present heuristic request-flow/call facts as compiler-perfect call graphs.
- Keep scanners/classifiers project-local and replaceable; keep Pi harness generic.
- Prefer intent-based query names over current implementation mechanisms.
- Treat live updates, fragments, generated contracts, and frontend surfaces as mechanisms/classifications that can evolve.

## Provenance

When updating durable docs, cite the source code or generated fact file used. If generated architecture output conflicts with prose, flag the drift and prefer source-derived evidence.
