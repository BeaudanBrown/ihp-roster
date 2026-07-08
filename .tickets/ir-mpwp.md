---
id: ir-mpwp
status: open
deps: [ir-zi2e]
links: []
created: 2026-07-08T07:20:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jvjj
tags: [frontend-contracts, typescript, htmx]
---
# Promote generated manifest and HTMX scaffolds into Haskell contract IR

Move HtmxActionOptions, FrontendSurfaceActionManifest, AppShellActionManifest, and related validators from handwritten TypeScript string blocks into Haskell-declared schema/IR output.

## Design

Represent manifest records and nested custom HTMX records in the DSL/IR or a generated built-in schema set. The TypeScript renderer should use generic schema/codec rendering plus manifest data rendering, not bespoke exported type strings.

## Acceptance Criteria

Generated manifest type definitions and validators are derived from Haskell schema declarations; Surface/AppShell manifests keep current wire shape; frontend-check and Frontend contract specs pass.

