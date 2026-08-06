# Release Readiness

Epic: [#60](https://github.com/BeaudanBrown/ihp-roster/issues/60).
Related unresolved work:
[#45](https://github.com/BeaudanBrown/ihp-roster/issues/45),
[#99](https://github.com/BeaudanBrown/ihp-roster/issues/99),
[#116](https://github.com/BeaudanBrown/ihp-roster/issues/116), and
[#8](https://github.com/BeaudanBrown/ihp-roster/issues/8).
GitHub owns status and dependencies.

## Intended Contract

- First-client acceptance criteria are explicit, testable, and aligned with the
  implemented product.
- Critical role-specific journeys have deterministic Hspec/E2E evidence without
  making browser tests the only safety boundary.
- Session/auth behavior, security headers, and local asset delivery meet the
  reviewed production posture.
- Customer terms, privacy, operational, and support documents describe only
  available behavior and have named human approval where required.
- Release evidence distinguishes automated checks from operator/legal approval.

## Integration Points

- `specs/09-testing-and-acceptance.md`.
- `specs/10-au-saas-security-privacy-compliance/` and
  `specs/11-first-client-document-pack/`.
- `e2e/AGENTS.md`, canonical verification commands, and deployment runbooks.

## Exit Criteria

- First-client acceptance and critical-path sweeps pass.
- Production security/session/asset findings are resolved.
- Customer/compliance documents are reviewed against current behavior.
- Remaining product gaps have explicit successor issues rather than hidden
  release-checklist prose.
