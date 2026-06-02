---
id: ir-ubhj
status: open
deps: []
links: [ir-huug]
created: 2026-06-02T07:51:44Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, area:exports, area:payroll, area:myob, bridge]
---
# MYOB tab-separated timesheet import exports

Build an interim MYOB timesheet import-file export path using Bepis approved payroll facts and the existing export job audit/download lifecycle. This bridge lets venues use MYOB before direct API/OAuth/cftoken work is finalised.

## Design

Target the MYOB Business timesheet import contract: .TXT or .CSV upload, tab-separated, row 1/cell A1 contains {}, row 2 contains MYOB headers, rows 3+ contain one timesheet entry per staff/date/payroll category/job. Mandatory MYOB fields are Employee Co./Last Name, Payroll Category, Date, Units, and Employee Card ID. Store venue-owned manual mappings for staff to MYOB Employee Card ID and Bepis pay buckets to MYOB Payroll Category; optionally support MYOB Job codes. Non-goals: direct MYOB API calls, OAuth, cftoken/company-file credential handling, payroll processing, MYOB Team, Desktop/EXO/AccountEdge-specific exports, and replacing the broader provider-abstraction epic.

## Acceptance Criteria

Venue owners/admins can configure MYOB import mappings, generate an audited MYOB timesheet import TXT from approved Bepis timesheet/pay data, download a file that matches MYOB's tab-separated template shape, and see actionable blockers for missing/invalid mappings or field limits before export. Existing export flows continue to work and the bridge epic is linked to but not blocked by the direct API/provider abstraction epic.

