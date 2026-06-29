---
id: ir-oj76
status: open
deps: [ir-nx3u, ir-fp76, ir-vgwk, ir-5dd9, ir-a02h, ir-t4g3, ir-pbuf, ir-agmx]
links: []
created: 2026-06-29T13:12:16Z
type: chore
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, docs, ui-regions, frontend]
---
# Update living docs for declarative UI region capabilities

Update living docs for the declarative UI region capability model and server/frontend boundaries.

## Design

Update LiveUpdate.SPEC, LiveSurface.COOKBOOK, Interaction.SPEC if needed, and frontend/AGENTS if durable rules change. Document UI region capabilities, generated TS vocabulary, HTMX-to-Bepis adapter, lazy/retry/transition behaviour, ownership boundaries, non-goals, and anti-patterns.

## Acceptance Criteria

A future agent can add a declarative region from docs; docs explicitly prohibit TypeScript from inventing routes, target ids, fragment names, or business semantics; verification commands are listed.

