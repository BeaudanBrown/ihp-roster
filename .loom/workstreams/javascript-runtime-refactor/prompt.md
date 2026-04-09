You are working on the `javascript-runtime-refactor` lane in `ihp-roster`.

Read, in order:

1. `AGENTS.md`
2. `Web/View/AGENTS.md`
3. `.loom/workstreams/javascript-runtime-refactor/context.md`
4. `.loom/workstreams/javascript-runtime-refactor/handoff.md`

Current objective:

- remove stale JS/runtime baggage
- split `static/app.js` into smaller app-owned runtime files
- harden live-update fragment refresh behavior
- move feature-local behavior out of the shared runtime layer
- add verification for the refactor

Implementation order:

1. stale runtime/vendor removal
2. bootstrap/runtime file split
3. live-update hardening
4. feature-local extraction
5. verification
