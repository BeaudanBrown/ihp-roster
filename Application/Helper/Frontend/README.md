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
6. Add or update a focused guard/parity test when the boundary is important:
   - generated source contains the expected type/constant;
   - production Haskell JSON round-trips for websocket/script payloads;
   - frontend runtime imports generated constants/guards instead of hardcoding
     canonical strings.
7. Run:

   ```bash
   bash ./bin/in-env typecheck
   bash ./bin/in-env frontend-contracts-check
   bash ./bin/in-env frontend-check
   bash ./bin/in-env hspec-test --match "Frontend contract"
   ```

## Adoption checklist

Use this checklist before adding browser-facing behavior to a live surface or
interaction runtime:

- Is the value server-owned? If yes, model it as a closed Haskell DTO/enum first.
- Is TypeScript only choosing generic behavior from generated data? If not,
  move feature semantics back to Haskell.
- Is there exactly one registered `FrontendContractGroup` for the schema module?
- Are canonical DOM attrs, event names, ids, and manifest keys generated or
  rendered by Haskell helpers?
- Does a test fail if runtime TypeScript hardcodes those canonical strings?
- Does a real browser/E2E test cover any lifecycle behavior that unit tests
  cannot prove, such as HTMX event adaptation, swaps, focus, or transitions?

## Scope

Generate browser-boundary DTOs only. Avoid exporting broad database/domain
models unless there is a deliberately narrow frontend payload. TypeScript should
consume generated types, constants, and guards from
`frontend/ts/generated/contracts.ts` and stay generic at runtime.
