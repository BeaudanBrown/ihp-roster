---
id: ir-u7c6
status: open
deps: [ir-tk23]
links: []
created: 2026-04-30T06:34:47Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:exports, area:maintenance, area:architecture]
---
# Split payroll export helper into focused service modules

Reduce Application.Helper.Export by separating export orchestration, read models, report definitions, payload construction, persistence, audit details, and rendering boundaries.

## Design

Keep behavior stable first. Suggested shape: Application.Export.Service, ReadModel, Definitions, Payloads, Persistence, Audit, plus existing Render and Types modules. Remove view-layer helper imports such as isTrialStaff from export logic as part of or after shared domain-helper extraction.

## Acceptance Criteria

Export code paths are split into named modules with narrow responsibilities; Application.Helper.Export is a compatibility facade or thin orchestrator; CSV and ZIP output remain byte-for-byte compatible where practical; focused export tests and typecheck pass.
