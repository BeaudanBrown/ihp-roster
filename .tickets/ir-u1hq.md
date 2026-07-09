---
id: ir-u1hq
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3txn
tags: [agent-loop, fwc, ops]
---
# Audit FWC MAPD refresh scheduling

Document current automatic award-rate refresh behavior and EOFY expectations.

## Design

Inspect NixOS timer defaults, FwcMapdRefreshSweep, job dedupe behavior, support/admin visibility, and recent sync status surfaces. Capture current monthly day-2 schedule and the desired prompt annual-rate behavior before changing defaults.

## Acceptance Criteria

Current FWC MAPD timer, job, dedupe, and visibility behavior is documented in the appropriate living doc or ticket note. Any missing operator visibility is identified before implementation.

