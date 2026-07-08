---
id: ir-dcm4
status: open
deps: [ir-81q7]
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:frontend, area:live-fragments, area:maintenance, cleanup-refactor]
---
# Split live-update and FrontendSurface runtime modules

Split the generic live-update and FrontendSurface runtime hotspots by responsibility without changing browser/server contracts.

## Design

Split frontend/ts/app-live-updates.ts into connection, subscription reconciliation, fragment refresh queue, protection/deferral, actor refresh, and debug/perf pieces. Split Application/Helper/FrontendContract/Surface/Runtime.hs by runtime concern where safe, such as field decoding, mount/lazy rendering, action attrs, interaction shell/forms, and conflict-policy serialization. Split Application/Helper/LiveUpdate/Internal.hs into protocol/types/scope constructors versus in-memory bus/versioning/broadcast helpers where safe. Link or reconcile overlap with existing ir-f2p4 rather than duplicating its intent. Do not hand-edit generated contracts or generated static JS; regenerate through project commands when TS changes.

## Acceptance Criteria

Runtime responsibilities are in focused modules. Generated contracts remain backend-owned and are not hand-edited. bash ./bin/in-env frontend-check or focused frontend checks pass for TS changes. bash ./bin/in-env typecheck passes for Haskell changes.

