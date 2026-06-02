---
id: ir-sfod
status: open
deps: [ir-5o52]
links: []
created: 2026-06-02T07:51:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:ui, area:exports, area:myob]
---
# Add MYOB import export setup UI

Let venue owners/admins maintain the manual MYOB mappings required by the import-file bridge.

## Design

Add an admin/export or payroll setup surface for staff Employee Card IDs, payroll category mappings for Bepis pay buckets/pay items, and optional job mappings. Include inline validation, mapping completion summary, MYOB import instructions, and clear copy explaining that direct API connection is not required for this bridge.

## Acceptance Criteria

Authorized admins can create/update/archive MYOB import mappings without editing the database. The UI shows completion status and preflight blockers. Unauthorized roles cannot access or mutate mappings. User-facing copy says MYOB timesheet import TXT/TSV and does not imply direct API connection.

