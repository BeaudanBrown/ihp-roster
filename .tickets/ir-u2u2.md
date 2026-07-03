---
id: ir-u2u2
status: open
deps: [ir-rwi8]
links: []
created: 2026-07-03T02:45:01Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, admin, xero, surfaces]
---
# Optionally add Admin Xero page parent surface

If smooth after the Admin page pilot, add a page-level parent surface for the Xero page that contains AdminXeroSurface.

## Design

Add AdminXeroPageSurface or equivalent with a content fragment containing AdminXeroSurface. Keep dialog/modal lane independent. If it complicates the first pass, document deferral and create a follow-up note/ticket instead of forcing it.

## Acceptance Criteria

If implemented, generated topology shows Xero page parent -> AdminXero child and Xero tests pass. If deferred, docs/ticket notes explain why and identify follow-up work.

