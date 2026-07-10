---
id: ir-gvfb
status: open
deps: [ir-g9m6]
links: []
created: 2026-07-10T05:30:28Z
type: feature
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:roster, area:leave, area:live-fragments]
---
# Make roster quick-view unavailability reset through surface refetch

Regular staff roster quick-view unavailability submit saves successfully but does not clear notes/dates because success only actor-invalidates roster content.

## Design

Ensure the roster staff quick-view unavailability form is a refetchable roster surface fragment or sub-fragment. On success, save the unavailable period, emit touched resources, actor-invalidate roster content/conflict state and the quick-view form fragment, and return toast extras only. Reset uses existing sensible defaults, normally today/tomorrow or the current roster/venue operational-day default helper. Validation failures still rerender the local form directly.

## Acceptance Criteria

Successful submit clears notes and resets dates to defaults via fragment refetch. Relevant roster/live state still refreshes through actor/passive invalidation. No authoritative form/business OOB is returned on success. Focused Hspec and browser coverage prove the form reset.

