---
id: ir-gt0e
status: closed
deps: [ir-mwma]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Make audit helpers emit audit facts

Make audit/version/domain-event helpers emit typed audit facts as a side effect of successful writes.

## Design

Change or wrap recordAuditEvent, recordCurrentUserAuditEvent, recordUserAuthenticationAuditEvent, and key version helpers so they call emitBepisFact after the DB write succeeds. Remove auditedAs-style descriptive labels from final action code.

## Acceptance Criteria

At least timesheet approval and one auth/session audit path emit audit facts from actual audit helpers; no auditedAs calls remain; focused audit tests assert both DB rows and captured facts.
