---
id: ir-94fn
status: closed
deps: []
links: []
created: 2026-07-04T12:31:43Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, wire]
---
# Implement FrontendContract JSON wire interpreter

Add the canonical Haskell JSON interpreter/checker for FrontendContract IR.

## Design

Create Application.Helper.FrontendContract.Wire.Json. It should resolve declarations from registeredFrontendContractIR and validate/parse/render Aeson values for the IR primitives used by browser contracts: records, enums/literal enums, tagged unions/discriminators, arrays, nullable/optional fields, refs, UUID/text/int/bool/number, surface scope records, and fragment payload records. This interpreter is the Haskell wire authority; typed carrier modules may delegate to it but must not re-declare contract shape.

## Acceptance Criteria

Generic wire tests cover success/failure for records, enums, tagged unions, refs, optional/nullable fields, and surface scope/fragment payloads. No production caller uses FrontendCodec for live-update/browser wire validation.

