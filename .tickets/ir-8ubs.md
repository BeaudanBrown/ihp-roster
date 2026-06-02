---
id: ir-8ubs
status: open
deps: [ir-2x24]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, submission]
---
# Submit MYOB timesheets with audit trail

Implement MYOB Timesheet GET/PUT submission behind the provider-neutral Payroll submission service.

## Design

Before writing, refresh OAuth, resolve/provide cftoken if required, fetch remote timesheet state, rerun readiness, then PUT the intended timesheet payload. Persist request/response payloads, remote employee/category IDs, source entry links, retry state, partial failures, and provider diagnostics. Do not process payroll or approve pays in MYOB.

## Acceptance Criteria

MYOB submissions are auditable, retryable, venue-scoped, and safe against stale previews. Partial failures are visible per employee/period. Remote Processed entries or unsupported existing state block mutation. Tests use strict local mocks rather than live MYOB calls.

