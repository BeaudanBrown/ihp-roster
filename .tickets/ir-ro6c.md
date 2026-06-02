---
id: ir-ro6c
status: open
deps: [ir-9pck]
links: []
created: 2026-06-02T07:51:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:schema, area:exports, area:myob]
---
# Add MYOB import export mapping schema

Persist the venue-scoped MYOB identifiers needed to create importable timesheet files without direct API access.

## Design

Add schema for staff to MYOB Employee Card ID mappings, Bepis pay bucket/pay item to MYOB Payroll Category mappings, and optional shift/tracking to MYOB Job mappings. Keep the schema bridge-specific or provider-neutral only where it will not conflict with the provider-abstraction epic. Enforce venue scope, uniqueness, soft-delete/audit timestamps where appropriate, and MYOB field-length constraints such as card ID <= 15, payroll category <= 31, and job <= 15.

## Acceptance Criteria

Generated types expose mapping records. Venue-scoped constraints prevent duplicate active MYOB card IDs and cross-venue mapping leakage. The schema can represent all data required by the MYOB import file and passes regen-types/typecheck after implementation.

