---
id: ir-guto
status: open
deps: [ir-j3hy]
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, dev]
---
# Integrate frontend watch into managed dev lifecycle

Make frontend rebuilds hot with existing dev-start, dev-foreground, dev-stop, and just dev flows.

## Design

Start the Nix/devenv-provided frontend-watch alongside the IHP start process. Track the watcher PID or process group for background dev. Include watcher output in dev logs or a clear sibling log. Ensure dev-stop stops the watcher and foreground cleanup handles Ctrl-C. Keep this dev-only watcher out of production/live NixOS services.

## Acceptance Criteria

bash ./bin/in-env dev-start starts frontend watch plus the app server using Nix/devenv-provided tooling. Editing a TS file updates the generated static JS. Existing browser reload behavior sees generated JS changes. bash ./bin/in-env dev-stop cleans up watcher/app/postgres/mailhog as applicable. just dev gets the same frontend-watch behavior via dev-foreground. The production/live NixOS module does not start frontend-watch or require Node tooling.

