---
id: ir-5si8
status: closed
deps: [ir-lg7p]
links: []
created: 2026-07-08T09:28:50Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:docs, area:payroll, agent-loop]
---
# Update docs and specs for award-rate rollover rule

Document the implemented raw FWC date vs Bepis venue-effective date semantics and current limitations.

## Design

Update specs/06-pay-engine.md, pay-config-versioning transition docs if needed, and any touched subsystem SPEC/AGENTS docs. State that venue week-start is the temporary pay-period proxy and explicit payroll calendar/frequency modelling is future work.

## Acceptance Criteria

Docs describe raw FWC operative dates, venue-effective rollover dates, and approved-entry non-rerating; non-goals include bulk re-rate tooling and provider-neutral payroll calendar settings.

