---
id: ir-1zup
status: closed
deps: [ir-53sm]
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, interaction]
---
# Promote shared interaction runtime vocabulary to Global contracts

Move reusable interaction concepts out of per-surface declarations where they are truly app/runtime vocabulary.

## Design

Define an Interaction Global root for shared sessions/layers/effects/field sets/DOM attrs/events such as drag session, drag preview layer, clone-shadow, dropzone-highlight, pointer drag fields, interaction DOM attributes, activation triggers, HTMX method/swap vocabularies as needed. Surfaces may reference globals; globals must not reference concrete surfaces.

## Acceptance Criteria

Roster drag/drop and layout-mode interactions still work using generated Global + Surface contracts. Reusable interaction declarations are no longer duplicated inside individual surface manifests except for surface-owned refs/intents/actions/conflict policies.

