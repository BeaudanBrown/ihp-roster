---
id: ir-v4vw
status: closed
deps: []
links: []
created: 2026-05-27T06:16:31Z
type: feature
priority: 2
assignee: Beaudan Brown
tags: [roster, mobile, agent-loop]
---
# Iterate roster phone snap release timing

Refine phone roster snapping so day-row rail width stays consistent with end times and JS snapping waits for finger/pointer release.

## Design

Use consistent phone day-row rail width and per-slot full-width groups in both end-time modes. Defer JS snap while pointer/touch scroll is active, then snap after release.

## Acceptance Criteria

Phone day-row day rail width is consistent when end times are enabled or disabled; end-time slot groups snap as full groups; snapping does not trigger while active touch/drag is still in progress; focused e2e coverage passes.

