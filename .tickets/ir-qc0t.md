---
id: ir-qc0t
status: closed
deps: [ir-63go, ir-nl8k]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 3
assignee: Beaudan Brown
parent: ir-zqp3
tags: [observability, opentelemetry, bepis-actions]
---
# Add OTel attributes from Bepis wrappers

Make runtime traces line up with static Bepis architecture facts.

## Design

Emit low-cardinality OTel attributes/spans from Bepis wrappers: bepis.controller, bepis.action, bepis.action.kind, bepis.response.kind, bepis.scope.kind, bepis.mutation.audit_policy, bepis.mutation.realtime_policy, bepis.live.surface where available. Ensure attributes are cheap, safe, and avoid PII/high cardinality values.

## Acceptance Criteria

A profile-load trace for a migrated action contains Bepis action/controller/kind attributes. request-flow or trace architecture queries can correlate runtime spans with static wrapper facts.


## Notes

**2026-06-30T05:26:32Z**

Implemented wrapper-side low-cardinality OTel attributes on root/current span plus child action spans. Verification: bash ./bin/in-env typecheck passed. Runtime profile trace verification remains to be done before closing.

**2026-06-30T07:11:15Z**

Runtime OTel verification passed. profile-load --otel run output/profile-load/otel-qc0t-1782802978 produced 9 traces/410 spans. Trace 564e9e0107a7840e7f55b8ff3f37906e for CreateSessionAction contains Bepis wrapper attributes on both WAI root span and bepis.action child span: bepis.action=CreateSessionAction, bepis.action.kind=mutation, bepis.response.kinds=redirect,htmx-fragment, mutation audit/realtime/scope policy labels. Also fixed local profile collector port conflicts and trace query parsing for collector NDJSON exports.
