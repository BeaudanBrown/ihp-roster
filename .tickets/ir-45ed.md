---
id: ir-45ed
status: open
deps: [ir-8ubs]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, corrections]
---
# Implement MYOB correction and update workflow

Define and implement explicit correction/update behavior for MYOB timesheets after submission.

## Design

Mark submitted runs stale when included source entries change. Permit explicit update only when remote MYOB entries are unprocessed and the user confirms. Require manual correction when entries are processed or provider state cannot be reconciled. Preserve previous request/response payloads and source-entry links.

## Acceptance Criteria

MYOB never silently mutates submitted payroll periods. Users can explicitly update safe unprocessed remote timesheets. Processed or ambiguous remote state shows manual correction requirements. Historical audit payloads remain immutable.

