---
id: ir-wqa4
status: closed
deps: [ir-myld]
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:protocol]
---
# Rename internal live fragment wire primitives

Make remaining transport primitives clearly internal wire types instead of legacy authoring concepts.

## Design

Rename LiveFragmentRef and mkLiveFragmentRef in internal modules to transport-oriented names such as LiveUpdateWireFragment and mkLiveUpdateWireFragment, or document any retained name with a strong reason. Update tests and helper names accordingly while preserving JSON keys unless the protocol ticket changes them.

## Acceptance Criteria

Raw wire fragment names no longer look like feature authoring APIs. Guard tests still pass. JSON round-trip tests prove browser payload compatibility unless superseded by a protocol migration ticket.


## Notes

**2026-05-16T03:43:18Z**

Renamed the internal fragment transport type to LiveUpdateWireFragment and constructor to mkLiveUpdateWireFragment. JSON field names remain unchanged; browser protocol is unchanged.
