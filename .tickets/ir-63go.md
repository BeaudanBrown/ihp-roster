---
id: ir-63go
status: open
deps: [ir-orax]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [haskell, ihp, bepis-actions]
---
# Introduce Application.Bepis action and controller wrapper modules

Add the first thin Bepis wrapper modules with no behavior change.

## Design

Create Application/Bepis/Action.hs, Controller.hs, Response.hs, Mutation.hs, Realtime.hs, Architecture.hs, and Prelude.hs as needed. Define BepisActionKind, BepisResponseKind, BepisActionInfo, BepisControllerPolicy, and initial wrappers such as bepisPageAction, bepisFragmentAction, bepisDialogAction, bepisMutationAction, bepisBeforeAction. Wrappers should initially run the underlying IHP controller action body and optionally annotate/record enough structure for later scanning, without changing behavior.

## Acceptance Criteria

Project typechecks. Wrappers are documented and imported from a small Bepis prelude. Existing behavior is unchanged. Wrapper implementations internally call/compose IHP-native primitives rather than replacing IHP lifecycle.

