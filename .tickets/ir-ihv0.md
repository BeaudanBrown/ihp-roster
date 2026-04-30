---
id: ir-ihv0
status: closed
deps: [ir-yi7u, ir-gj4q]
links: [ir-f2p4, ir-jooi]
created: 2026-04-30T06:35:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:live-fragments, area:frontend, area:maintenance, area:architecture]
---
# Centralize live-update scope identity and projection surface definitions

Finish centralizing live-update protocol ownership by relying on server-provided scopeKey values and moving projection-backed live-surface definitions out of views/controllers into feature modules.

## Design

After timesheet and leave feature modules exist, define their LiveSurfaceDefinition and fragment refs in feature-owned modules. Keep JS using message/config scopeKey and remove or quarantine buildScopeKey fallback once every server message and surface config carries scopeKey. Preserve compatibility events only while tests still require them.

## Acceptance Criteria

static/app-live-updates.js no longer mirrors Haskell scope-key constructors for normal operation; timesheet and leave views consume feature-owned surface configs instead of rebuilding refs locally; live-update Hspec and focused Playwright coverage pass.
