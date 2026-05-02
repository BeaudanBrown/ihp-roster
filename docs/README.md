# Documentation System

This repository uses living, code-adjacent documentation. The goal is to make
the implemented system easy for agents and humans to discover without losing
space for future feature streams.

## Document Types

- `README.md` near code: what the subsystem owns, where to start, and how it
  connects to the rest of the app.
- `SPEC.md` near code: current behavior, invariants, state transitions, and
  extension rules for implemented behavior.
- `AGENTS.md` near code: local editing rules, gotchas, and verification.
- `specs/`: product, domain, compliance, and acceptance intent that crosses
  subsystem boundaries.
- `docs/workstreams/`: proposed, active, or blocked feature streams that are
  not fully implemented yet.
- `docs/adr/`: durable architectural decision records.
- `.tickets/`: live implementation status, dependencies, and next actions.
- `docs/archive/`: historical plans, audits, and superseded notes.

## Update Rules

When implementing a feature stream:

1. Keep live task status in `tk`.
2. Keep future or partial design in `docs/workstreams/`.
3. Move implemented behavior into the nearest subsystem `SPEC.md`.
4. Move reusable editing rules into the nearest `AGENTS.md`.
5. Record architectural rationale in `docs/adr/` when the choice will matter
   later.
6. Archive or close the workstream when no active future behavior remains.

Do not leave the only description of implemented behavior in a workstream or
archived plan.

## Navigation

- Start at `README.md` and root `AGENTS.md`.
- Use `IMPLEMENTATION_PLAN.md` for global priority and ticket routing.
- Use `docs/workstreams/README.md` for future feature streams.
- Use `docs/architecture/README.md` for subsystem boundaries.
- Use `docs/adr/README.md` for decision history.
- Use `docs/archive/plans/README.md` when an old plan is referenced.

## Drift Policy

If code and docs disagree, trust code/tests first, then update docs or create a
ticket to close the gap. If a product spec describes behavior that is still
desired but not implemented, keep it in `specs/` or `docs/workstreams/` and
make sure a `tk` ticket exists.
