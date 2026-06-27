---
id: ir-0qiq
status: closed
deps: [ir-0dyi, ir-3npt]
links: []
created: 2026-06-27T09:16:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lcpr
tags: [agent-loop, live-surface, interaction]
---
# Migrate timesheets and roster to descriptor-shaped registrations

Adapt the complex timesheets and roster surfaces to the golden registration pathway without relying on projection as a required core concept.

## Design

Keep dynamic fragments, containment, interaction capability, and custom candidate-fragment logic explicit; use adapters if full descriptor migration is too risky.

## Acceptance Criteria

Roster and timesheets expose canonical registration objects; registry no longer has bespoke raw registration paths except documented infrastructure adapters.


## Notes

**2026-06-27T09:43:22Z**

Completed by the registered catalog work: timesheets and roster now have context-free ForVenue typed definitions for manifest/planning samples, and the registry consumes them through RegisteredLiveSurface entries. Roster interaction remains attached to the request-context typed definition, while the ForVenue adapter preserves the static interaction schema for manifest generation. Projection remains outside the core registered surface abstraction.
