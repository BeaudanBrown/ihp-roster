---
id: ir-pbsx
status: closed
deps: []
links: []
created: 2026-05-27T23:58:33Z
type: task
priority: 1
assignee: beaudan
parent: ir-hx3q
tags: [area:ui, area:mobile]
---
# Audit and remove explicit autofocus attributes

Remove autofocus attributes from sign-in, staff/profile, passkey setup, recovery, and any other app-owned views discovered by search.

## Design

Start from rg -i autofocus over Web/Application/static excluding vendor/prod build artifacts. Remove attributes rather than replacing them with JS.

## Acceptance Criteria

Focused source grep finds no app-owned autofocus attributes; affected views typecheck.

