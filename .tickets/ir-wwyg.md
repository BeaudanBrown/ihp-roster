---
id: ir-wwyg
status: open
deps: []
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:maintenance, analysis, cleanup-refactor]
---
# Remeasure cleanup hotspots and active-ticket overlap

Re-run the cleanup hotspot scan and route the implementation sequence against current code and open tickets.

## Design

Measure current line-count and concern hotspots across Xero, roster, live/frontend runtime, tests, and fixture/seed code. Inspect open Xero, roster, frontend/live, test, and fixture tickets for overlap. Confirm exact extraction seams, compatibility wrappers, verification commands, and any tickets that should be linked or avoided. Add notes to the epic with the final sequence before code movement starts.

## Acceptance Criteria

Current hotspot list is documented in ticket notes. Active overlap risks are listed. Next implementation tickets have clear file/module targets and verification guidance.

