---
id: ir-62zx
status: open
deps: [ir-7hzq]
links: []
created: 2026-06-25T13:30:47Z
type: chore
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, cleanup]
---
# Deprecate the custom profiling header spine after OTel parity

After OpenTelemetry traces/artifacts/tooling cover the existing workflow, remove or reduce the custom Server-Timing/X-Profile-Counters spine to compatibility diagnostics.

## Design

Keep `Server-Timing` only if still useful for browser devtools behind `IHP_ROSTER_PROFILING`. Remove or mark `X-Profile-Counters` as legacy once OTel summaries and agent tools support the same comparisons from trace attributes/events and local collector artifacts. Preserve production-safe defaults: normal `IHP_ROSTER_OTEL` tracing remains lightweight and sampled, while heavy component byte/counter collection remains diagnostic-only. Document the migration path for existing profile scripts.

## Acceptance Criteria

No primary profiling/reporting path depends on X-Profile-Counters; compatibility behavior is documented; obsolete deep counters are pruned or renamed as OTel attributes/metrics; typecheck, focused profile script smoke, and relevant Hspec tests pass.

