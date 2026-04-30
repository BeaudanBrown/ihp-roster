---
id: ir-2vyr
status: closed
deps: [ir-wipd]
links: [ir-9f7z]
created: 2026-04-30T01:11:05Z
type: task
priority: 2
assignee: beaudan
parent: ir-6vvh
tags: [area:view, area:live-fragments, area:maintenance, source:2026-04-30-health-scan]
---
# Standardize optional OOB fragment rendering

Provide one helper path for rendering the same fragment with or without hx-swap-oob so paired normal/OOB renderers do not drift.

## Design

Several views keep paired renderers where the only difference is
`hx-swap-oob`. Add a small view helper after the `Application.Helper.View` split
has a stable module home.

Candidate API ideas:

- `renderWithOptionalOob :: Maybe Text -> Html -> Html` when the caller already
  owns the container.
- `oobAttrs :: Maybe Text -> [(Text, Text)]` or a small config record when HSX
  needs attributes inline.
- section-specific wrappers may remain where they improve naming, but they
  should call the shared optional-OOB helper.

Initial adoption targets:

- Xero mapping counts and Xero admin fragments after `ir-8yyg`.
- toast/dialog mount swaps where the only variable is OOB behavior.
- live-fragment helper paths that currently have `renderX` plus `renderXOob`
  variants.

Guardrails:

- Do not make a generic HTML DSL; keep the helper limited to OOB attribute
  plumbing.
- Preserve exact DOM ids and `hx-swap-oob` values.
- Add the helper in the narrowest focused view helper module that exists after
  `ir-wipd`; do not put new implementations back into
  `Application.Helper.View`.

## Acceptance Criteria

- At least one normal/OOB renderer pair is collapsed into one helper path.
- Tests or focused assertions cover both normal and OOB output for the migrated
  fragment.
- No call site changes visible markup outside the `hx-swap-oob` attribute.
