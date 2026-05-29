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
tags: [agent-loop, xero, shell]
---
# Migrate Xero connection and reference-sync actor responses

Move broad Xero shell-changing actor responses to shared OOB fragments.

## Design

Connection/start/disconnect/reference-sync responses that change shell-level state should return the shell fragment through the helper plus toasts/dialog clears.

## Acceptance Criteria

Shell-level actor responses no longer use bespoke renderCurrentVenueXeroSectionFragmentOob; Xero specs pass.

