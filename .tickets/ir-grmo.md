---
id: ir-grmo
status: closed
deps: []
links: []
created: 2026-06-28T12:17:09Z
type: feature
priority: 1
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, live-surfaces, lazy-loading]
---
# Add live fragment load policy metadata

Extend the typed live surface model so every live fragment descriptor has an explicit load policy: eager by default, lazy when opted in.

## Design

Add FragmentLoadPolicy and LazyFragmentConfig types near LiveFragmentDescriptor in Application.Helper.LiveSurface.Internal. Preserve existing behavior by defaulting descriptors to FragmentEager. Add chainable helpers such as liveFragmentDescriptorWithLazyLoad, liveFragmentDescriptorWithEagerLoad, and accessors for a descriptor/ref policy. Lazy config should include trigger, placeholder kind, accessible label, optional CSS classes, and maybe delay. Keep it metadata-only in this ticket; do not change view rendering yet.

## Acceptance Criteria

Existing live surface definitions compile unchanged; new helpers are exported from Application.Helper.LiveSurface; unit/type-level usage is straightforward for a descriptor; no behavior changes occur before renderer adoption.


## Notes

**2026-06-28T12:56:13Z**

Implemented eager-by-default FragmentLoadPolicy/LazyFragmentConfig metadata on live fragment descriptors/contracts with lazy/eager helpers and type-level coverage. Verification attempt: bash ./bin/in-env typecheck is currently blocked before these modules by missing OpenTelemetry.* packages in the project environment.
