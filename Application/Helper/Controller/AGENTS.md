# Controller Helper Agent Notes

Read this before editing shared controller helper modules.

## Local Rules

- Keep request-derived input parsing total.
- Treat HTML `required`, hidden inputs, and select options as client hints only.
- Pair `fill` with explicit required-param checks for required fields.
- Validate venue/tenant scope after parsing ids and before mutation.
- Keep audit writes inside the same transaction as the sensitive mutation where
  feasible.

## Shared Boundaries

- Input normalization belongs in `Application/Helper/Controller/Input.hs` or a
  feature-specific controller helper.
- Access helpers belong in `ControllerAccess.hs` or `ControllerSupport.hs`.
- Request context helpers belong in `ControllerContext.hs`.
- Export, Xero, roster, and timesheet domain decisions should live in their
  focused modules rather than generic controller helpers.

## Verification

Add focused Hspec for missing params, malformed typed values, oversized text,
whitespace-only text, cross-venue ids, and suspicious payloads when changing an
input boundary.
