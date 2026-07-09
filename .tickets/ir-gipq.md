---
id: ir-gipq
status: closed
deps: [ir-jjf5]
links: []
created: 2026-07-07T03:54:41Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-6rnm
tags: [agent-loop, roster, timeline, frontend]
---
# Render roster day timeline lanes, shifts, dropzones, and overlap tracks

Render the server-owned timeline DOM and attach generated interaction refs.

## Design

Build a timeline render model from existing roster read data. Outer lanes are active RosterWeekSlotDefinition records ordered by sort_order/created_at. Compute visual-only inner tracks per lane by interval overlap. Render the operational day horizontally from 06:00 through 05:45 next day, 15-minute dropzones per lane, and shift cards positioned by normalized operational minutes. Editable draft shifts receive generated source refs with opaque source keys; editable lane ticks receive generated dropzone refs with opaque target keys. Read-only timelines render no mutation affordances. Add scoped CSS under the roster feature stylesheet.

## Acceptance Criteria

The timeline shows a single roster day across the operational window with slot-definition lanes and visually stacked overlapping shifts. Editable draft timelines emit generated source/dropzone refs through Haskell helpers; read-only/staff/live timelines do not expose mutation refs. Closed days render a closed/read-only state without dropzones. Focused render/contract checks pass.

