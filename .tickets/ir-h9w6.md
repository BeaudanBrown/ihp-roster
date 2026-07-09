---
id: ir-h9w6
status: closed
deps: [ir-zcue]
links: []
created: 2026-07-09T05:06:02Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, interaction, docs]
---
# Add ergonomic multi-source drag/drop helper aliases and docs

Add reusable helper aliases and authoring docs for declaring multiple drag source/dropzone refs on a surface.

## Design

Add helper aliases/types in Application.Helper.FrontendContract.Surface.Interaction or a nearby module for source ref + source field + intent, dropzone ref + target field, source/dropzone compatibility, and optional modifier variants/effects. Update the interaction spec and FrontendContract Surface authoring docs with a concise multi-source example and the roster staff-drag pattern.

## Acceptance Criteria

Future surfaces can declare multiple drag/drop behaviors without hand-assembling low-level primitives. Docs include a multi-source/multi-dropzone example. Existing guardrails remain intact and doc-drift-check passes when docs are touched.

