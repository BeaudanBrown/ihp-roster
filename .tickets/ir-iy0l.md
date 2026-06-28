---
id: ir-iy0l
status: open
deps: [ir-fvq6]
links: []
created: 2026-06-28T12:17:09Z
type: chore
priority: 2
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, docs, lazy-loading]
---
# Document the lazy live fragment pattern

Document how future surfaces/fragments should opt into lazy loading and what conventions must be preserved.

## Design

Update the nearest living docs/specs for live surfaces and observability as appropriate. Include when to use lazy loading, how to choose triggers/placeholders, how to keep endpoints authoritative, how live updates interact with unloaded fragments, and production caveats. Reference the roster staff panel as the first example.

## Acceptance Criteria

A new agent can implement another lazy fragment by following docs; docs state that eager is default and lazy is a descriptor policy; docs mention verification commands and profile tooling.

