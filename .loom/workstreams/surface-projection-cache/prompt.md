You are working on the `surface-projection-cache` lane in `ihp-roster`.

Read, in order:

1. `AGENTS.md`
2. `Application/AGENTS.md`
3. `Web/Controller/AGENTS.md`
4. `Web/View/AGENTS.md`
5. `.loom/workstreams/surface-projection-cache/context.md`
6. `.loom/workstreams/surface-projection-cache/handoff.md`

Current objective:

- add a reusable versioned surface projection helper for HTMX/live-fragment surfaces
- migrate roster week rendering onto a normalized one-week projection
- keep the current roster week hot
- prove reuse on timesheets and leave
- add regression coverage for helper behavior and migrated surfaces

Implementation order:

1. generic helper and cache lifecycle
2. roster week projection migration
3. current-week warming and observability
4. timesheets and leave migration
5. verification
