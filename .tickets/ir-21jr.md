---
id: ir-21jr
status: open
deps: []
links: [ir-cfcr, ir-osr3, ir-jsyd]
created: 2026-06-29T13:12:15Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, frontend, live-fragments, htmx, lazy-loading, architecture]
---
# Declarative UI region capabilities for fragments, lazy loading, and transitions

Introduce a Haskell-owned, declarative UI region capability model so reusable frontend behaviours like lazy loading, retry/error handling, and transitions are applied through server-rendered/generated contracts rather than feature-specific TypeScript.

## Design

A UI region is a server-declared DOM ownership unit. Capabilities are independent opt-ins rather than a strict hierarchy: replaceable fragment identity, lazy loading, retry/error handling, transition profile, live-update participation, focus protection, interaction conflict policy, and disposable interaction layers. Initial implementation focuses on Haskell-rendered attrs, generated TypeScript vocabulary for allowed browser-boundary values, a thin HTMX-to-Bepis adapter for opted-in regions only, generic lazy retry/error handling, generic transition profiles, and the roster staff panel proof. Raw HTMX outside declared regions keeps current behaviour. TypeScript remains thin and must not own feature semantics, URLs, target ids, routes, or fragment names.

## Acceptance Criteria

Haskell owns UI region capability vocabulary and generates matching TypeScript unions/guards; server helpers render data-bepis attrs for declared UI regions; a small TypeScript adapter translates relevant HTMX lifecycle events into Bepis region events only for marked regions; lazy retry/error uses Bepis region events; opt-in transition profiles exist and respect reduced motion; roster staff panel lazy loading uses the declarative region/capability system; docs explain capability boundaries and when not to mark ordinary HTMX as a region; typecheck, frontend-check, and focused helper/runtime tests pass.

