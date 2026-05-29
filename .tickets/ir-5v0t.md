---
id: ir-5v0t
status: open
deps: [ir-jtmv]
links: []
created: 2026-05-29T03:16:08Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, admin, live-fragments]
---
# Migrate admin single-fragment surfaces to unified actor OOB responses

Convert low-risk admin config sections with one live fragment each to the shared fragment response helper.

## Design

Venue settings, invites, exports, roster groups, and shift types should stop using direct hx-target outerHTML for successful mutations and instead use hx-swap=none plus shared OOB fragment responses; keep focus protection for editable lists.

## Acceptance Criteria

All targeted admin sections have one fragment renderer/contract used by live GETs and actor OOB responses; tests cover response shapes; focus-protection behavior remains intact.

