---
id: ir-blxm
status: open
deps: [ir-5v0t]
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-3y9k
tags: [agent-loop, research, confirmation]
---
# Confirm profile content fragment behavior after leave migration

Research profile content paths after the leave/profile leave epic and confirm active-section behavior before changing profile update responses.

## Design

Inspect Web.Controller.Profiles, Web.Profiles.LiveUpdates, profile view renderers, and completed leave migration notes. Confirm whether only successful profile update responses change and whether security/RSA sections remain resync-only/direct.

## Acceptance Criteria

Ticket note records chosen scope, active-section behavior, validation failure behavior, and any changed assumptions; no production behavior changes are made.

