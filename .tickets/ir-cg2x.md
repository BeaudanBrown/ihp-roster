---
id: ir-cg2x
status: in_progress
deps: [ir-hnpv]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 2
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, admin, low-risk]
---
# Migrate venue settings invites and exports fragments

Move the simplest admin single-fragment surfaces to shared OOB actor responses.

## Design

For venue settings, invites, and exports: keep existing fragment contracts, set successful HTMX forms/toggles to hx-swap=none where appropriate, and respond with OOB fragment plus toast/errors using the shared helper.

## Acceptance Criteria

Controller/config specs show OOB fragment responses; direct successful hx-target outerHTML paths are removed for these sections; focused checks pass.

