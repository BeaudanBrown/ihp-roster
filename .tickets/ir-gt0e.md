---
id: ir-gt0e
status: open
deps: [ir-mwma]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Make audit helpers produce audit evidence

Make audit/version/domain-event helpers return typed audit evidence as a byproduct of successful writes.

## Design

Change or wrap recordAuditEvent, recordCurrentUserAuditEvent, recordUserAuthenticationAuditEvent, and key version helpers so their return values include BepisAuditEvidence. Remove auditedAs-style descriptive labels from final action code.

## Acceptance Criteria

At least timesheet approval and one auth/session audit path produce audit evidence from actual audit helpers; no auditedAs calls remain; focused audit tests pass.

