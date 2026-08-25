# ADR 0010: Typed application outcome boundaries

Date: 2026-08-25

## Context

Operation failures previously crossed service, request, job, and transaction
boundaries through unrelated exceptions and textual errors. Treating every
unsuccessful workflow state as failure also obscured trustworthy states that a
caller can render or persist normally.

## Decision

Request-, workflow-, and job-facing operations use `AppResult`, with focused
closed domain errors projected exhaustively into payload-free `AppError`
values. Known trustworthy state—including blockers and warnings that are part
of that state—remains in `Right`; `Left` means the operation could not be
performed or its result could not be determined.

Validation, authorization and not-found masking, IHP response control, and
non-blocking domain warnings remain separate boundaries. Error codes derive
from qualified error type and constructor metadata. Only the registered safe
code, severity, recovery, and message cross the browser boundary; retry policy,
identifiers, domain values, exceptions, and technical context do not.

Synchronous exceptions are converted only at an outer operation boundary.
Response control, record-not-found masking, and asynchronous cancellation pass
through unchanged. A typed `Left` inside a transaction is translated to a
private, immediately caught rollback exception.

## Consequences

Domain additions must extend an exhaustive safe projection and the registered
browser code set. Callers can select recovery and retry policy without parsing
text, and expected blockers no longer mark outages. Boundary adapters add some
explicit orchestration, while unexpected exceptions still retain one final
safe fallback.

## Alternatives Considered

- Retain `Either Text`: compact, but neither exhaustive nor safely classifiable.
- Store existential domain errors in `AppError`: preserves detail but permits
  technical payloads and unstable wire behavior to escape.
- Represent every blocker as `Left`: conflates known state with inability to
  perform or determine an operation.

## Links

- Tickets: #432, #433
- Living docs: `Application/Helper/FrontendContract/README.md`
