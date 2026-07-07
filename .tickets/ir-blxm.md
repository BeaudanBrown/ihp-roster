---
id: ir-blxm
status: open
deps: [ir-rfyw]
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-3y9k
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm profile content semantic invalidation behavior

Research profile content paths and confirm active-section behavior before changing profile update responses.

## Design

Inspect `Web.Controller.Profiles`, profile live surface helpers, profile view renderers, and completed leave/profile migration notes. Confirm which successful profile update responses should emit actor-local semantic invalidation, which fragment represents the active/open section, and whether security/RSA sections remain resync-only/direct. Validation/preference errors remain direct-rendered at the local target.

## Acceptance Criteria

Ticket note records chosen scope, active-section behavior, duplicate-mount implications, validation failure behavior, resync-only/direct exceptions, and any changed assumptions. No production behavior changes are made.
