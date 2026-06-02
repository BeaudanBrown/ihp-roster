---
id: ir-f41v
status: open
deps: [ir-f7wo, ir-acnv]
links: []
created: 2026-06-02T07:20:14Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, area:docs, testing]
---
# Finalize provider migration hardening docs and compatibility cleanup

Close out the provider abstraction epic with verification, documentation reconciliation, and cleanup of obsolete Xero-specific downstream naming.

## Design

Run full relevant verification, update living subsystem specs/AGENTS docs, reconcile docs/workstreams, add closeout ADR notes if needed, archive/supersede stale Xero-only workstream text, remove or isolate compatibility code, and ensure no downstream Payroll flow imports provider internals unnecessarily.

## Acceptance Criteria

Provider abstraction and MYOB feature parity are documented as implemented behavior. Xero and MYOB tests pass. Obsolete Xero-only UI labels/routes/table names are either removed, migrated, or documented as compatibility internals. Epic acceptance criteria can be verified and closed.

