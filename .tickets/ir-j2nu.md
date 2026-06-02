---
id: ir-j2nu
status: open
deps: [ir-5o52, ir-1lor]
links: []
created: 2026-06-02T07:51:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:exports, area:payroll, area:myob]
---
# Build MYOB approved-timesheet import payload

Convert approved Bepis payroll facts into MYOB timesheet import rows.

## Design

Use approved timesheet entries and pay-versioned pay segments, resolve MYOB mappings, and aggregate rows by employee/date/payroll category/job where safe. Preserve source entry ids and pay version manifests in export metadata/notes where possible. Use MYOB payroll categories from mappings rather than Xero earnings-rate names. Exclude trial/inactive staff according to existing payroll export rules unless explicitly mapped and approved by the bridge contract.

## Acceptance Criteria

Payload generation produces deterministic MYOB rows from approved source data, blocks when preflight fails, records source entry ids and version manifests in export metadata, and does not depend on MYOB API tables or Xero-specific mappings.

