# Frontend Contract Generation

This directory owns the Haskell-to-TypeScript browser boundary for Bepis.

## Contract rule

If TypeScript reads a value from generated constants, JSON script payloads,
websocket messages, event detail, `data-*` attributes, or static surface
manifests, Haskell should expose it through a `FrontendCodec` and a registered
contract group. Do not add hand-written TypeScript unions or canonical browser
strings for backend-owned concepts.

## Adding a contract

1. Define a narrow Haskell DTO/enum for the browser boundary.
2. Provide a `FrontendCodec`; use `HasFrontendCodec`/`someFrontendCodec` when
   the type has one canonical frontend representation.
3. Build schemas with `recordSchema`, `field`, `nullableField`,
   `optionalField`, `taggedUnionSchema`, and `variant` rather than hand-writing
   TypeScript.
4. Register the codecs/constants with `FrontendContractGroup` via
   `renderFrontendContractGroup`.
5. Add the declaration to `frontendContractDeclarations` in `Contracts.hs`.
6. Run:

   ```bash
   bash ./bin/in-env frontend-contracts-check
   bash ./bin/in-env frontend-check
   bash ./bin/in-env hspec-test --match "Frontend contract"
   ```

## Scope

Generate browser-boundary DTOs only. Avoid exporting broad database/domain
models unless there is a deliberately narrow frontend payload. TypeScript should
consume generated types, constants, and guards from
`frontend/ts/generated/contracts.ts` and stay generic at runtime.
