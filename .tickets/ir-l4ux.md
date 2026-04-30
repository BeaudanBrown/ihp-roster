---
id: ir-l4ux
status: closed
deps: []
links: []
created: 2026-04-30T06:29:32Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5rhn
tags: [area:security, area:exports, area:tests]
---
# Neutralize spreadsheet injection in CSV exports

Harden export CSV rendering so user-controlled cells cannot execute as formulas in spreadsheet software. Applies to approved timesheet CSV, staff-hours CSV, hourly breakdown CSVs, payroll earnings CSV, and ZIP-contained CSVs.

## Design

Centralize CSV cell escaping/neutralization in Application.Helper.Export.Render. Preserve RFC-style quoting for commas, quotes, and newlines, and additionally prefix or otherwise neutralize cells beginning with spreadsheet formula trigger characters after leading whitespace.

## Acceptance Criteria

CSV golden/controller tests cover cells beginning with =, +, -, @, tab/space-prefixed formula text, quotes, commas, and newlines; exported files remain parseable and formulas are not active when opened in common spreadsheets.

## Notes

**2026-04-30T07:54:33Z**

Centralized spreadsheet formula neutralization in Application.Helper.Export.Render.csvCell; cells with formula prefixes after whitespace or leading control whitespace are apostrophe-prefixed before CSV quoting. Added regression coverage.
