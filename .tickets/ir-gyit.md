---
id: ir-gyit
status: open
deps: [ir-ojl5, ir-w50d, ir-95e7]
links: []
created: 2026-06-16T13:45:45Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, htmx, interaction, prototype]
---
# Prototype low-risk click/select intent surface

Prove the typed interaction golden path on a low-risk click/keyboard/touch activation before implementing drag/drop timelines.

## Design

Choose a small existing behavior during implementation where a click or keyboard activation can emit a normalized committed intent and submit a Haskell-rendered HTMX form. Avoid high-risk roster mutation semantics for this first prototype unless no simpler candidate exists. The prototype should use typed Haskell surface/mount/layer/intent definitions, generated TypeScript contracts, typed render helpers, and the generic intent bridge.

The server response remains authoritative. The client may create only disposable/local UI. Do not introduce JS-built persistence URLs, feature-specific fetches, or client-owned business state. Include a portability check where practical: the form target should be derived from the concrete mount rather than a hardcoded global id.

Candidate classes include simple select/toggle/filter actions that already round-trip server-side and can be rendered as an HTMX fragment response. The implementer should document the chosen surface and why it is low risk.

## Acceptance Criteria

- A low-risk surface declares non-empty typed interaction capability for one click/select intent.
- The view renders surface mount, disposable/server layer if needed, activation marker, and intent form through Haskell helpers.
- User activation by click and keyboard emits a committed normalized intent and submits through the generated HTMX form.
- Server response is rendered authoritatively; no client-side business mutation or JS-built URL is introduced.
- Focused regression coverage proves the golden path, including field/schema validation and successful HTMX response.
- `bash ./bin/in-env frontend-check`, `bash ./bin/in-env typecheck`, and relevant focused Hspec/Playwright checks pass.


## Notes

**2026-06-25T07:32:55Z**

Prototype note after `d643fbc3`: if the low-risk prototype touches roster row-grid shifts, target the new single editable launcher wrapper shape (`.roster-shift-unit.roster-shift-launcher`) as the activation/item boundary. Inner Start/End/Staff/Role cells are visual-only, and read-only row-grid shifts intentionally remain non-launchers. Prefer a lower-risk non-roster surface if available, but do not build against the old per-cell launcher assumption.
