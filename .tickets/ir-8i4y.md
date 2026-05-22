---
id: ir-8i4y
status: closed
deps: [ir-vius]
links: []
created: 2026-05-22T06:01:53Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-it5h
tags: [agent-loop, area:roster, area:live-fragments]
---
# Declare roster fragment containment and prevent overlap

Declare the current roster fragment DOM containment truth and ensure roster actor/passive refreshes emit non-overlapping refs.

## Design

In Web/RosterWeeks/LiveSurface.hs, assign containment paths for roster content, staff panel, day section, and row fragments. Before the layout split, content is the ancestor of staff panel, day sections, and rows. Confirm content+staffPanel normalizes to content, day+row normalizes to day, and sibling non-overlaps remain. Add focused tests around actor refresh headers and passive registry planning.

## Acceptance Criteria

Roster slot mutation actor refresh headers do not include both parent and child refs for the current DOM shape. Passive planning emits non-overlapping roster refs. Focused roster fragment/workflow tests cover the no-overlap invariant.


## Notes

**2026-05-22T06:21:11Z**

Implemented: roster live-surface refs now declare current DOM containment paths; content is the ancestor of staff panel/day/row while the panel is still nested. Actor refresh and passive planning now emit only roster-content for current broad roster-week changes. Discovery: existing row-related actor tests requested rows plus content; under the current DOM shape those rows must be dropped until ticket ir-6lg4 splits the panel/content boundaries. Verified with full RosterWeeksController Hspec and focused LiveSurfaceRegistry/LiveSurface tests.
