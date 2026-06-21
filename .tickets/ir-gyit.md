---
id: ir-gyit
status: open
deps: [ir-ojl5, ir-w50d]
links: []
created: 2026-06-16T13:45:45Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, htmx, interaction, prototype]
---
# Prototype low-risk click/select intent surface

Prove the interaction golden path on a low-risk behavior before implementing drag/drop timelines.

## Design

Choose a small existing page interaction where a click or keyboard activation can emit a normalized intent and submit an HTMX form. Use the generic intent bus and HTMX bridge, not feature-specific persistence JS. Server response should remain authoritative. Include keyboard and touch/click parity where applicable.

## Acceptance Criteria

A prototype surface emits a normalized intent from user activation, submits through a declared HTMX form, receives a server-rendered fragment response, and has focused regression coverage; no client-side business mutation or JS-built persistence URL is introduced.

