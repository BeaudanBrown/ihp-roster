---
id: ir-st8a
status: closed
deps: [ir-myon]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, opentelemetry, profiling]
---
# Bridge custom profiling spans to OpenTelemetry child spans

Make the existing semantic span helpers emit OpenTelemetry child spans while preserving current diagnostic headers under IHP_ROSTER_PROFILING.

## Design

Introduce `Application.Helper.Telemetry` or equivalent as the standard abstraction. `profileActionSpan` and `profileActionSpanWithDetail` should create cheap OTel child spans when OTel is enabled, while preserving the current diagnostic headers under `IHP_ROSTER_PROFILING`.

Do not make production/lightweight OTel force HTML rendering or byte measurement. `respondHtmlProfiled` and `profileHtmlComponent` currently render to bytes to measure payload/component size; that cost should stay behind `IHP_ROSTER_PROFILING=1` or a similarly explicit diagnostic gate. In diagnostic/profile runs, component byte details should become typed OTel attributes such as `html.bytes` rather than string-encoded `desc` values. Keep `Server-Timing` generation only under `IHP_ROSTER_PROFILING`.

## Acceptance Criteria

Roster traces show nested cheap spans for action/render boundaries under `IHP_ROSTER_OTEL=1`; diagnostic profile traces under `IHP_ROSTER_PROFILING=1` expose full shell/layout/content/grid/body/respond_html spans plus `html.bytes` on component/response spans; existing profile headers and profile-load reports still work when `IHP_ROSTER_PROFILING=1`; tests or smoke tooling verify off, lightweight OTel, and diagnostic profiling modes.


## Notes

**2026-06-28T00:47:12Z**

Bridged profiling helpers into OTel: profileActionSpan/profileActionSpanWithDetail now run inside lightweight child spans; diagnostic profileHtmlComponent/respondHtmlProfiled spans add html.bytes and diagnostic attributes while keeping existing Server-Timing/X-Profile headers behind IHP_ROSTER_PROFILING. Verified with typecheck and TEST_SHARDS=1 hspec-test --match Profiling.
