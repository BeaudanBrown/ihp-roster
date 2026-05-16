---
id: ir-oln7
status: closed
deps: [ir-drby, ir-wgmx, ir-zhz1, ir-j9yz, ir-qz3z, ir-p73a]
links: []
created: 2026-05-16T01:26:40Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:docs]
---
# Delete old live-surface compatibility API and update docs

After all existing live surfaces and selected new live areas use strict typed contracts, delete or quarantine the old compatibility/manual authoring API and update durable docs.

## Design

Remove public exports for untyped surface construction and fallback authorization. Keep only internal transport codecs needed for stable browser JSON. Update Application/Helper/LiveUpdate.SPEC.md, Web/Controller/AGENTS.md, Web/View/AGENTS.md, static/AGENTS.md, and feature-local docs with the mandatory typed workflow.

## Acceptance Criteria

The forbidden-helper guard passes because old helpers are unavailable to feature code. Docs describe the strict contract as mandatory. Full final verification for live-update Hspec and Playwright suites passes. The strict workstream can be marked implemented.


## Notes

**2026-05-16T02:19:41Z**

Updated live-update/controller docs for mandatory strict typed authoring; old compatibility API is internal-only and guarded.
