---
id: ir-1nps
status: open
deps: [ir-9t94]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, xero, shell, frontend-surface]
---
# Migrate Xero connection and reference-sync actor responses

Move broad Xero shell-changing success responses to actor-local semantic invalidation plus extras.

## Design

Connection/start/disconnect/reference-sync responses that change shell-level state should commit and report touched resources through existing mutation paths, return toasts/dialog extras as needed, and emit actor-local semantic invalidation for the shell or normalized affected fragments. They should not return `renderCurrentVenueXeroSectionFragmentOob` or other authoritative business OOB HTML on success.

## Acceptance Criteria

Shell-level successful actor responses contain no bespoke business OOB Xero section HTML. They use the shared actor-local invalidation helper. Passive Xero websocket invalidation remains intact. Focused Xero specs pass.
