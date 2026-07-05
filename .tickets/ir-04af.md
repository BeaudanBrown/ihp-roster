---
id: ir-04af
status: open
deps: []
links: []
created: 2026-07-05T10:20:36Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-815h
tags: [frontend-contracts, hardening, wire]
---
# Expand Wire.Json validation semantics and tests

Exercise and tighten the generic FrontendContract IR JSON interpreter.

## Design

Extend Test.FrontendContractsSpec or a focused Wire.Json spec for records, enums, literal enums, tagged unions, nested refs, unknown fields, missing fields, nullable vs optional field presence, WireOptional vs OptionalFieldPresence semantics, arrays, surface scope, surface fragment key, and WireSurfaceWireFragment. Add strict UUID and Day textual validation if product/runtime expectations allow it; if not, explicitly document that WireUUID/WireDay are currently string-shaped wire contracts only.

## Acceptance Criteria

Wire.Json has focused positive and negative tests for all supported WireIR constructors and field-presence modes. UUID/day behavior is either enforced or documented by tests.

