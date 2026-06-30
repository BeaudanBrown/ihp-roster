---
id: ir-djtt
status: closed
deps: [ir-95yp]
links: []
created: 2026-06-30T04:48:17Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-zqp3
tags: [prototype, ihp, haskell, bepis-actions]
---
# Prototype typed Bepis ControllerSpec dispatch

Test whether a stronger typed controller spec can replace per-action raw IHP pattern bodies ergonomically.

## Design

Prototype on SessionsController or another small controller. Target shape: instance Controller X where beforeAction = runBepisBeforeAction spec; action = runBepisControllerAction spec. The spec should contain typed action descriptors, handlers, controller policy, and architecture facts. Evaluate GADT/existential complexity caused by constructors with different fields. This is exploratory; do not migrate broadly unless it is simpler than wrapper-per-action.

## Acceptance Criteria

A documented prototype decision exists: adopt, defer, or reject. If adopted, a follow-up epic/tickets are created. If rejected/deferred, wrapper-per-action remains the official pattern.

