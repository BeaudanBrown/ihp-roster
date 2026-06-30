# Architecture Agent Guidelines

This directory documents durable architecture understanding for Bepis. Prefer current code, schema, generated types, and deterministic architecture outputs over hand-drawn assumptions.

## Deterministic Architecture Tooling

Project-local architecture commands are declared in `.pi/architecture.json` and are intended for Pi's `architecture_commands`, `architecture_command`, `architecture_queries`, and `architecture_query` tools.

Whole-project generated outputs are written under `output/architecture/`, which is gitignored initially. Focused query outputs are written under `.pi/tmp/architecture-query/` or `.pi/tmp/architecture-trace/`.

Use these wrappers from the project environment:

```bash
bash ./bin/in-env architecture-facts
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
