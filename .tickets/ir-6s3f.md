---
id: ir-6s3f
status: closed
deps: []
links: []
created: 2026-04-30T06:56:50Z
type: task
priority: 1
assignee: beaudan
parent: ir-hw2v
tags: [area:timesheets, area:exports, area:xero]
---
# Add approval export and Xero locking gates

Make approval, export generation, and Xero submission explicit locking gates for historical payroll records.

## Design

Approval stores selected pay version ids. Export generation records included entry ids/version ids and prevents silent destructive edits of included approved entries. Xero preview/submission records included entry/version ids and blocks or correction-flows later edits. Define unapprove/edit behavior for exported/submitted entries.

## Acceptance Criteria

Controller/domain tests prove approved entries carry version ids, exported/submitted entries cannot be silently mutated, unapprove/edit behavior is explicit, and audit/export metadata shows the locked version context.


## Notes

**2026-04-30T07:28:58Z**

Approval now locks selected pay versions; exports record export_job_entries provenance; Xero preview/submission stores staff/shift pay version ids; edit/delete/unapprove gates block entries that already have export or Xero provenance.
