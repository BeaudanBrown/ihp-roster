---
id: ir-dj54
status: open
deps: [ir-gaxt, ir-dhl7]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, docs, interaction]
---
# Document final interaction and surface architecture

Update living docs after implementation to describe the final helper layers and surface vocabulary.

## Design

Update Application/Helper/FrontendSurface README/SPEC and interaction SPEC to show: generated contract source of truth, helper layers, browser-owned runtime responsibilities, allowed low-level primitives, and migration guidance. Include guardrail expectations and examples.

## Acceptance Criteria

Docs explain how to add a new interactive surface without using stale LiveSurface concepts or raw marker wiring; docs match implemented APIs and tests.

