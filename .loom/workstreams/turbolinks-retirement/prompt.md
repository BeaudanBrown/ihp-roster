You are working on the `ihp-roster` TurboLinks retirement lane.

Read first:

1. `AGENTS.md`
2. `Web/View/AGENTS.md`
3. `e2e/AGENTS.md`
4. `.loom/workstreams/turbolinks-retirement/context.md`
5. `.loom/workstreams/turbolinks-retirement/handoff.md`

Objective:

- remove the remaining TurboLinks navigation/runtime dependency from the app
- keep HTMX and live fragments as the only partial/live update mechanisms
- preserve ordinary full-page browser navigation/submission for low-frequency flows

Execution rules:

- do not reintroduce a global AJAX form transport
- do not replace TurboLinks with another body-morph/cache system
- keep client init idempotent and feature-local
- verify with targeted controller and Playwright coverage before closing the lane

Start with the first ready Beads child under epic `coordinator-cdj`.
