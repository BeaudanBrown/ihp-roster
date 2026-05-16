---
id: ir-rp8v
status: closed
deps: []
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:architecture]
---
# Inventory live-update runtime compatibility seams

Audit the post-strict-overhaul internal live-update/runtime surface and decide which compatibility pieces can be deleted, renamed, or intentionally retained as transport.

## Design

List each remaining old primitive, its callers, whether it is feature-facing, and the safest removal path. Identify wire-shape compatibility risks before code changes.

## Acceptance Criteria

Workstream doc has an up-to-date inventory of remaining primitives, caller categories, deletion/rename decisions, and required tests. No implementation ticket starts without this classification.


## Notes

**2026-05-16T03:37:40Z**

Inventory complete in docs/workstreams/live-update-runtime-simplification.md. Feature code has no remaining use of the untyped surface builders; pre-protocol cleanup will preserve browser JSON and only rename/delete Haskell compatibility seams.
