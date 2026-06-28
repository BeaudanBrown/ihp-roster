---
id: ir-6io4
status: closed
deps: [ir-st8a]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, metrics, profiling]
---
# Move roster render counters into OTel attributes events and stable metrics

Replace the request-counter spine for roster grid/render diagnostics with OpenTelemetry trace attributes/events and a small stable metric set.

## Design

Request-shape counters such as grid cells, shift launchers, launcher attr bundles, hx attrs, data attrs, editable/read-only cells, and conflict attrs should attach to the relevant roster render span, especially slots_grid_body/component, when diagnostic profiling is enabled. Lightweight production OTel should avoid doing extra render-counter work unless the relevant data is already cheaply available.

Promote only stable low-cardinality signals to metrics once the tracing spine is in place: response bytes, component bytes, render duration, grid cell count, shift launcher count. Metrics are not the first milestone; do not block initial WAI/action tracing on metric export. Labels should be route/action/component/layout/week_status/editable_state only.

## Acceptance Criteria

A future editable row-grid trace exposes launcher_attr_bundle=210, launcher_hx_attr=840, launcher_data_attr=1050, and component bytes on the appropriate span; a read-only trace exposes no launcher attrs; stable metrics can be queried without high-cardinality labels; X-Profile-Counters remains compatibility-only or is clearly marked diagnostic.


## Notes

**2026-06-28T02:10:27Z**

Implemented diagnostic render-counter bridging: profileHtmlComponent now opens a thread-local nested counter scope, profileRenderCounter aggregates into all active render spans, and each diagnostic span emits matching OTel attributes plus a bepis.render.counters event. This keeps counter collection under IHP_ROSTER_PROFILING while making slots_grid_body/components expose existing low-cardinality render counters.
