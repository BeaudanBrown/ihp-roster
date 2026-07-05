---
id: ir-uvf9
status: open
deps: [ir-04af]
links: []
created: 2026-07-05T10:20:36Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-815h
tags: [frontend-contracts, hardening, live-update, wire]
---
# Validate live-update carrier instances at every carrier boundary

Remove remaining manual-parser blind spots in FrontendContract.Wire.LiveUpdate.

## Design

Review Application.Helper.FrontendContract.Wire.LiveUpdate. Direct FromJSON instances such as SurfaceFragmentProtection and FocusedFieldProtectionConfig currently parse manually and may not reject unknown fields unless nested in a larger validated schema. Route every carrier FromJSON through validateContractValue or an exact-object helper where a DSL schema exists, and add tests for unknown extra fields and invalid nested payloads on each carrier type. Add representative outbound checks that toJSON for every constructor validates against Wire.Json.

## Acceptance Criteria

Direct decoding of each live-update carrier rejects unknown/malformed fields consistently with generated TypeScript guards. Tests prove every constructor's toJSON validates against registeredFrontendContractIR.

