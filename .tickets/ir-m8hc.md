---
id: ir-m8hc
status: closed
deps: []
links: []
created: 2026-04-30T06:31:02Z
type: epic
priority: 2
assignee: beaudan
tags: [area:docs, area:maintenance, source:2026-04-30-audit]
---
# Align specs and agent docs with current implementation

Bring repo specs, AGENTS guidance, plans, and tk status back into agreement with the current implementation after the 2026-04-30 divergence audit.

## Design

Documentation alignment now uses the living-doc system:

- `docs/README.md` defines the documentation operating model.
- `docs/workstreams/` owns future and partial feature-stream design.
- subsystem-local `README.md`, `SPEC.md`, and `AGENTS.md` own implemented behavior and local editing rules.
- `docs/archive/plans/65-spec-agent-doc-alignment.md` is historical audit context only.

Treat Application/Schema.sql, controller tests, and current code as implementation truth; treat specs as product intent; preserve old plans as historical records rather than live guidance.

## Acceptance Criteria

The high-risk pay snapshot gap is tracked for implementation, stale docs are updated or annotated, stale completed tracker items are reconciled, and future agents can tell which behavior is current without rediscovering this audit.

## Notes

**2026-04-30T07:24:48Z**

2026-04-30 doc-only pass: closed ir-z5dj, ir-gz6l, ir-r2pp, ir-nin6, ir-e3o5, ir-f8tn, and ir-tqnr; `docs/archive/plans/65-spec-agent-doc-alignment.md` records those statuses. Snapshot/pay reproducibility was intentionally handled in the parallel append-only versioning workstream.

**2026-05-02T00:00:00Z**

Documentation structure refactor completed: numbered plans moved to `docs/archive/plans/`, future feature streams moved to `docs/workstreams/`, root AGENTS guidance was shortened, local subsystem specs/agent notes were added for roster, timesheets, leave, exports, Xero, live updates, view helpers, controller helpers, and static assets, and ADR 0001 records the operating model.
