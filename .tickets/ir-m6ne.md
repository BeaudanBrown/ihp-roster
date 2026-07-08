---
id: ir-m6ne
status: closed
deps: [ir-9yr7]
links: []
created: 2026-07-08T09:28:50Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:roster, area:payroll, agent-loop]
---
# Align roster wage prediction and Haskell pay lookups

Make Haskell-side award-rate lookups use the same venue-effective resolution as canonical pay calculation.

## Design

Update Application/Helper/RosterWagePrediction.hs and any other Haskell latestEffective award-rate lookup discovered during implementation. Avoid parallel sorting by raw operative_from when the lookup is venue/date-sensitive.

## Acceptance Criteria

Prediction or helper tests match SQL behavior around a mid-week FWC operative date and next venue-week rollover.

