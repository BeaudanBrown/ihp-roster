---
id: ir-tbyl
status: closed
deps: []
links: []
created: 2026-07-08T06:53:50Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, interaction, htmx]
---
# Deduplicate InteractionContract HTMX method and swap vocabulary

Remove duplicated interaction-local HTMX method/swap schemas and reuse the shared generated HTMX metadata vocabulary.

## Design

Make IntentFormContract method/swap fields reference or derive from the shared HTMX model introduced for Surface/AppShell request metadata. Keep the emitted wire values stable unless a direct consumer update is part of the same change.

## Acceptance Criteria

InteractionContract no longer maintains independent HtmxMethod/HtmxSwap definitions; intent form method/swap validation still works; generated TS has a single HTMX vocabulary source; frontend/typecheck/focused interaction tests pass.

