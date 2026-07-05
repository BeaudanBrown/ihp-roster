---
id: ir-kc10
status: closed
deps: [ir-sxo2, ir-4h3p]
links: []
created: 2026-07-05T10:20:36Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-815h
tags: [frontend-contracts, docs, guardrails]
---
# Archive stale frontend codec docs and strengthen no-return guardrails

Finish documentation cleanup after the FrontendContract-only migration.

## Design

Move or clearly mark superseded frontend-codec workstreams/spikes as historical. Update docs/workstreams index and Application.Helper.FrontendContract README/SPEC references so new contributors see only FrontendContract authoring. Strengthen guardrails to fail if Application/Helper/Frontend is recreated with .hs modules or if Application.Helper.Frontend.* imports return, while allowing historical docs/archive references.

## Acceptance Criteria

Docs describe the current authoring path without recommending FrontendCodec/DTO schema groups. Guardrails catch recreated legacy Haskell modules/imports. Historical docs are explicitly marked as archive/superseded.

