---
id: ir-jsyd
status: open
deps: []
links: []
created: 2026-06-16T13:44:46Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, htmx, interaction]
---
# Design declarative interaction intent layer

Define and implement a reusable server-declared interaction layer where generic client-side gesture code emits normalized intents and HTMX/server-rendered fragments remain authoritative.

## Design

Use data-bepis-* attributes rendered by IHP to declare surfaces, items, slots, dropzones, resize handles, and intent forms. JavaScript owns only ephemeral interaction UI and dispatches normalized intent events; HTMX submits server-declared forms; IHP validates, mutates, and returns authoritative fragments. Include pointer/touch support and coordination with live fragments.

## Acceptance Criteria

A documented architecture and initial runtime exist for declarative interaction surfaces; at least one low-risk prototype surface proves click/pointer/touch intent dispatch through HTMX without client-side business-state ownership; follow-up tickets cover timeline drag/drop and resize.

