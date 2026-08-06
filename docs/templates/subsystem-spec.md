# Subsystem Name Specification

Code, schema, generated contracts, and tests own implemented detail. Record only
durable cross-module or externally observable contracts that are hard to infer.
Future intent belongs in a linked workstream.

## Invariants

State authority, history, transition, or fail-closed rules that must survive
implementation refactors.

## Observable Contract

State behavior relied on outside one module.

## Extension Constraints

State what future changes must preserve or explicitly supersede.

## Authority

Link owning production modules and focused tests; do not list every action,
field, helper, asset, or test.
