---
id: ir-1lor
status: open
deps: [ir-9pck]
links: []
created: 2026-06-02T07:51:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:exports, area:myob, rendering]
---
# Implement MYOB tab-separated timesheet renderer

Add a pure renderer for MYOB timesheet import files that follows the MYOB template shape instead of normal comma CSV rendering.

## Design

Render row 1 as {}, row 2 as exact MYOB headers, and rows 3+ as tab-separated fields. Format dates as DD/MM/YYYY, units with two decimals, and include Employee Co./Last Name, Employee First Name, Payroll Category, Job, Notes, Date, Units, Employee Card ID, and Start/Stop Time. Define TSV cell handling for tabs/newlines/control characters and spreadsheet formula neutralisation without using comma-CSV quoting semantics incorrectly.

## Acceptance Criteria

Golden tests can assert exact text output. The renderer never emits commas as delimiters, preserves the {} sentinel/header layout, formats MYOB dates/units correctly, handles unsafe cell contents deterministically, and documents any sanitation/truncation policy.

