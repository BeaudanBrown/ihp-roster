---
id: ir-m8hc
status: open
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

Use plans/65-spec-agent-doc-alignment.md as the coordination plan. Treat Application/Schema.sql, controller tests, and current code as implementation truth; treat specs as product intent; preserve old plans as historical records with explicit superseded/current-status notes rather than rewriting their history.

## Acceptance Criteria

The high-risk pay snapshot gap is tracked for implementation, stale docs are updated or annotated, stale completed tracker items are reconciled, and future agents can tell which behavior is current without rediscovering this audit.

## Notes

**2026-04-30T07:24:48Z**

2026-04-30 doc-only pass: closed ir-z5dj, ir-gz6l, ir-r2pp, ir-nin6, ir-e3o5, ir-f8tn, and ir-tqnr; plans/65 now records those statuses. Snapshot/pay reproducibility remains open in the parallel append-only versioning workstream and was intentionally not modified here.
