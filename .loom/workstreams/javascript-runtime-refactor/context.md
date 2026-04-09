# JavaScript Runtime Refactor

## Objective

Reduce the size and risk of the app-owned JavaScript runtime by deleting stale vendor/runtime baggage, splitting shared runtime concerns out of `static/app.js`, hardening live-update failure handling, and moving feature-local behavior into clearer files.

## Settled Technical Direction

- Keep the existing browser + HTMX + live-fragment architecture.
- Do not introduce a bundler as the first move.
- Preserve `app:page-ready` as the single lifecycle contract for feature initialization.
- Remove clearly unused vendor/runtime assets before deeper extraction.
- Treat live-update refresh failure handling as a correctness issue, not just cleanup.
- Reduce global monkey-patching where feasible, especially timer and morphdom blast radius.

## Implementation Plan

1. Stale runtime/vendor removal
   - Confirm repo-wide non-usage for `jquery`, `timeago`, and stale Turbolinks-era build inputs.
   - Remove dead layout/build references without changing active runtime behavior.
2. Bootstrap/runtime split
   - Separate the current monolith into smaller app-owned files loaded explicitly from `Web/View/Layout.hs`.
   - Keep a thin bootstrap that wires shared lifecycle/runtime pieces in order.
3. Live-update hardening
   - Stop silent fragment-refresh failure swallowing.
   - Add enough error visibility or resync behavior to debug broken refresh paths safely.
4. Feature-local extraction
   - Move roster-only and smaller feature-local listeners out of the shared runtime file.
   - Keep feature init routed through `app:page-ready`.
5. Verification
   - Run targeted checks for lifecycle re-init, HTMX swaps, live fragments, overlays, and the quarter-hour picker after the split.

## Required Read Order

1. `repos/ihp-roster/AGENTS.md`
2. `repos/ihp-roster/Web/View/AGENTS.md`
3. `repos/ihp-roster/Web/View/Layout.hs`
4. `repos/ihp-roster/static/app.js`
5. `repos/ihp-roster/Makefile`

## Guardrails

- Do not fold unrelated in-progress work from the dirty tree into this lane.
- Do not introduce a bundler or framework-level rewrite as part of the first pass.
- Keep lifecycle behavior backward-compatible for HTMX swaps and OOB swaps.
- Prefer deleting dead code before extracting live code.
