---
id: ir-ojl5
status: open
deps: [ir-4uuy]
links: []
created: 2026-06-16T13:45:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, javascript, htmx, interaction]
---
# Implement generic intent bus and HTMX form bridge

Add a small app-owned JavaScript runtime that normalizes interaction intents and submits matching server-declared HTMX forms.

## Design

Create focused static runtime modules without adding a bundler. The intent bus should dispatch cancelable CustomEvents such as bepis:intent and phase events for start/preview/commit/cancel/error. The HTMX bridge should find the nearest data-bepis-intent-form for an intent type, copy detail fields into matching hidden inputs, and dispatch the form's declared hx-trigger event. It must not construct domain URLs, call fetch for persistence, or mutate business DOM.

## Acceptance Criteria

Runtime can emit an intent, allow local JS listeners to observe/cancel it, fill matching hidden inputs, and trigger HTMX submission through declared form attributes; missing/unknown fields fail safely with debug-visible warnings; existing JS checks and relevant e2e coverage pass.

