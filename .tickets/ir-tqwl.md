---
id: ir-tqwl
status: closed
deps: [ir-lxkv, ir-3wwj, ir-qd8e, ir-fgtz]
links: []
created: 2026-05-15T02:27:34Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:migration, area:docs]
---
# Migrate live surfaces to the typed contract

Move existing live sections onto the typed live surface contract and document the new add-a-fragment workflow.

## Design

Migrate in slices: first a simple support/admin surface, then leave or timesheets, then roster. Keep wire compatibility while migrating. Move durable rules into the live-update SPEC and local AGENTS docs, and update the workstream as old manual helpers disappear.

## Acceptance Criteria

Support/admin, leave or timesheets, and roster all use the typed contract or have explicit follow-up tickets; manual fragment-ref and surface-config boilerplate is reduced; docs show the new local workflow for adding a live fragment.

