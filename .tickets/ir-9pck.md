---
id: ir-9pck
status: open
deps: []
links: []
created: 2026-06-02T07:51:44Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:docs, area:exports, area:myob]
---
# Document MYOB timesheet import file contract

Record the external MYOB timesheet import-file requirements as the source of truth for this bridge export.

## Design

Update the nearest export/payroll docs with the MYOB support URL, row structure, mandatory fields, field limits, tab-separated requirement despite CSV/TXT wording, date/unit formatting decisions, and how this bridge differs from direct MYOB API integration. Include non-goals and any assumptions that should be verified against a live MYOB import later.

## Acceptance Criteria

Docs identify the exact MYOB import contract: {} sentinel in A1, MYOB header row, tab-separated data rows, mandatory Employee Co./Last Name, Payroll Category, Date, Units, Employee Card ID fields, relevant length limits, and bridge scope/non-goals. The docs link this epic and the broader provider epic ir-huug.

