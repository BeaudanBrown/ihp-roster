---
id: ir-vpmd
status: open
deps: []
links: [ir-jsyd]
created: 2026-06-25T11:56:58Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, contracts, haskell, typescript, live-updates, interaction]
---
# Generated frontend wire contracts from Haskell schemas

Replace string-embedded frontend contract declarations with Haskell-owned schema generation for every concept shared between Haskell and TypeScript, including live-update wire protocol, registered live surfaces, interaction intents/layers/sessions, and runtime validation/type guards for browser-received JSON.

## Design

Use aeson-typescript as the primary TypeScript declaration generator. Allow live-update/interaction wire encoding changes when they let Haskell ToJSON/FromJSON and generated TypeScript come from the same Haskell contract. Split static surface/interaction schema from runtime mount instances: static shared concepts are generated exhaustively; request-specific URLs, DOM ids, mount ids, HTMX actions, and targets remain Haskell-rendered runtime metadata. Add schema-generated or schema-driven TypeScript validators/type guards for JSON received from websocket/live-update boundaries. Keep the existing frontend-contracts and frontend-contracts-check commands as the workflow entrypoints.

## Acceptance Criteria

No large handwritten TypeScript declaration blocks remain for Haskell-owned frontend contracts; aeson-typescript is integrated into the project; live-update wire protocol TypeScript types are generated from Haskell wire types and JSON instances; browser-received JSON has generated/schema-driven validators or type guards; static interaction schema exposes all shared layer/session/intent/field concepts for generation; registered surfaces/fragments/intents appear in generated contracts or fail guard tests when omitted; docs state that every Haskell/TypeScript shared concept must be generated from Haskell-owned schemas; frontend-contracts-check, frontend-check, typecheck, and focused LiveSurface/LiveUpdate/Interaction tests pass.

