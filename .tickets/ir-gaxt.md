---
id: ir-gaxt
status: closed
deps: [ir-729e]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, guardrails]
---
# Migrate remaining interaction call sites and add guardrails

Move all remaining production interaction usage off old semantic marker helpers and protect the generated-ref path.

## Design

Audit production imports/usages of `Application.Helper.Interaction`, `renderInteraction*Marker`, `withInteraction*Marker`, and old semantic `data-bepis-*` interaction attrs. Migrate remaining production call sites to generated refs/helpers. Add guardrails or an allowlist for low-level marker/runtime usage. Keep low-level attrs only in generated/runtime modules, tests/fixtures, or explicitly documented internals.

## Acceptance Criteria

- Production feature views do not hand-wire old semantic interaction markers.
- Guardrails fail if old semantic marker APIs are used outside allowlisted modules.
- Remaining low-level usage is documented and intentionally internal/transitional.
- Tests cover the guardrail.
