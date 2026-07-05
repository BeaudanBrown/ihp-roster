---
id: ir-97dr
status: closed
deps: []
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, foundation]
---
# Introduce FrontendContract DSL, IR, registry, and validator

Create the neutral FrontendContract module family and define the root model, shared schema core, and validation model without migrating production contracts yet.

## Design

Add Application.Helper.FrontendContract.{DSL,IR,Registry,Reflect,Validate,TypeScript}. Define FrontendContract = Global Type [GlobalPrimitive] | Surface Type [SurfacePrimitive]. Define shared schema primitives Record, Enum, TaggedUnion, Case; Field/OptionalField/NullableField; WireText/WireInt/WireBool/WireUUID/WireDay/WireList/WireOptional/WireNullable/WireRef plus semantic WireSurfaceScope/WireSurfaceFragmentKey or equivalent. Establish fixed naming: PascalCase types, lowerCamel fields, kebab-case values, bepis: event names, data-bepis-* attrs, tag discriminator for unions. Add collision/reference diagnostics.

## Acceptance Criteria

A minimal RegisteredFrontendContracts can be reflected/lowered/validated and rendered to TypeScript for fixture contracts. Validation catches duplicate schema/global names and unresolved refs. Existing production generation remains unchanged during this ticket.

