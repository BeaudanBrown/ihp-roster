---
id: ir-wkpb
status: open
deps: []
links: []
created: 2026-06-02T07:20:13Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:docs, area:payroll, area:providers]
---
# Document payroll provider architecture ADR and workstream

Create the durable architecture and workstream docs for the multi-provider Payroll direction before broad implementation begins.

## Design

Add an ADR or equivalent architecture note covering the provider-neutral boundary, one-active-provider-per-venue rule, direct-MYOB-only scope, Xero-first migration order, and company-file credential decision requirements. Add or update a docs/workstreams entry that links this epic and lists living docs to update as slices land. Keep implementation status in tk, not in markdown checklists.

## Acceptance Criteria

Docs record the approved decisions and non-goals. The workstream links this epic and names Application/Xero, future Payroll provider modules, Web controller/view docs, specs, and any ADRs that must be reconciled. The company-file credential decision is explicitly deferred to the MYOB spike with concrete evidence requirements.

