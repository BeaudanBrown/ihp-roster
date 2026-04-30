---
id: ir-gz6l
status: closed
deps: []
links: []
created: 2026-04-30T06:31:22Z
type: task
priority: 2
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:exports, area:authz, source:2026-04-30-audit]
---
# Align export access docs with admin-only implementation

Docs and older plans still say managers may generate exports, but the current implementation and tests restrict export generation/download surfaces to venue admins/owners/super admins via ensureAdminRole.

## Design

Update Application/AGENTS.md and plans/46-payroll-export-e2e-hardening.md/current planning notes to reflect admin-only export generation. Preserve manager export wording only as historical/superseded context.

## Acceptance Criteria

No active doc tells agents to grant manager export generation; docs reference Test/Controller/ExportsSpec manager-denial coverage or equivalent; admin-only export access remains intentional.
