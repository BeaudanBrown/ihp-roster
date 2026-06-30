---
id: ir-zqp3
status: open
deps: []
links: [ir-f2p4, ir-cfcr, ir-jsyd, ir-jooi, ir-p008, ir-62zx]
created: 2026-06-30T04:48:17Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, ihp, bepis-actions, agent-loop]
---
# Typed Bepis action boundary over IHP

Refactor the app toward a clean boundary where IHP remains the framework shell and controllers/actions delegate through small Bepis-owned typed wrappers. The goal is stronger compiler/test guarantees, simpler app conventions, and architecture facts/diagrams derived from implementation structures instead of naming heuristics.

## Design

IHP remains responsible for Web/Types.hs action constructors, Web/Routes.hs AutoRoute, Web/FrontController.hs mounting, Controller instances, beforeAction lifecycle, request context, params, rendering, HSX, QueryBuilder, generated DB types, and framework middleware. Bepis owns app invariants: controller policies, venue/support scope, action kind, response kind, mutation effects, audit policy, realtime/live freshness, generated frontend contracts, and architecture facts. Target shape: normal IHP Controller instances call Bepis wrappers immediately inside beforeAction/action. Longer-term, prototype typed ControllerSpec dispatch if ergonomic. Architecture scanner order should become typed Bepis wrappers/specs > app live/contract registries > static scan > naming fallback.

## Acceptance Criteria

Epic is complete when new controller actions normally use Bepis wrappers; raw IHP action bodies are detected by a convention check; controller/action diagrams report typed-wrapper facts and confidence; mutation actions declare audit/realtime/scope policy; realtime coverage/flow diagrams distinguish mechanism and coverage; OTel spans can correlate runtime traces to static Bepis action metadata; IHP remains the visible framework boundary rather than being replaced by a hidden parallel framework.

