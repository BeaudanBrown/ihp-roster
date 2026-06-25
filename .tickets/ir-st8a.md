---
id: ir-st8a
status: open
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

Introduce Application.Helper.Telemetry or equivalent as the standard abstraction. profileActionSpan/profileActionSpanWithDetail/respondHtmlProfiled/profileHtmlComponent should create OTel child spans when OTel is enabled. Component byte details should become typed attributes such as html.bytes rather than string-encoded desc values. Keep Server-Timing generation only under IHP_ROSTER_PROFILING.

## Acceptance Criteria

Roster traces show nested render spans for full shell/layout/content/grid/body/respond_html; html.bytes is visible on component/response spans; existing profile headers and profile-load reports still work when IHP_ROSTER_PROFILING=1; tests or smoke tooling verify both enabled and disabled modes.

