---
id: ir-o7ml
status: open
deps: [ir-j2nu, ir-sfod]
links: []
created: 2026-06-02T07:51:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:exports, area:myob, ui]
---
# Register MYOB Timesheets Import TXT export job

Expose MYOB import-file generation through the existing export job lifecycle.

## Design

Add an export type/report action for MYOB Timesheets Import TXT. Persist scope metadata, row counts, source entry counts, mapping completeness, version manifest, file name, text/plain or compatible content type, utf8 encoding, expiry/download audit fields, and download action through export_jobs. Keep existing exports unchanged.

## Acceptance Criteria

Admins can request and download a MYOB timesheet import .txt for a selected approved date range. Export jobs show ready/blocker state consistently with existing exports. Downloaded files have MYOB-specific filenames, UTF-8 text encoding, and auditable metadata.

