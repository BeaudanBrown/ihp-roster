# Architecture Decision Records

ADRs explain why durable architecture decisions were made. They are not task
plans and should stay short.

Use an ADR when:

- there are multiple reasonable technical directions
- a decision constrains future work
- a later agent would otherwise rediscover the same tradeoff
- an old plan is being superseded by a living contract

Use `docs/templates/adr.md` for new ADRs.

## Index

- `0001-documentation-operating-model.md` - documentation, workstreams, and
  local agent instructions.
- `0002-haskell-owns-browser-business-authority.md` - Haskell owns browser-facing
  business meaning while TypeScript owns reusable presentation mechanics.
- `0003-frontend-contract-runtime-authority.md` - reflection-backed contract,
  runtime, wire, target-ID, and browser-authority ownership.
- `0004-complete-hspec-is-the-protected-test-gate.md` - complete Hspec remains
  the protected gate; partial metadata selections are additive diagnostics.
- `0005-explicit-roster-shift-assignment-state.md` - roster shifts use an explicit
  staff/Open assignment state rather than interpreting missing staff as Open.
- `0006-operation-local-frontend-contract-evidence.md` - generated request callers
  use compact nominal operation evidence while whole-Surface proofs stay private.
- `0007-explicit-production-haskell-package-boundary.md` - production source,
  dependency, tooling, and artifact ownership is explicit and fail-closed.
- `0008-date-native-roster-windows.md` - explicit Operational and Roster days
  replace offset-based week identity while seven-day windows remain projections.
