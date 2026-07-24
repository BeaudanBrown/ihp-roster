# Playwright agent browser tooling research — 2026-07-23

## Question

Should Bepis expose Playwright to coding agents through MCP, the newer agent-oriented
Playwright CLI, or the traditional Playwright Test CLI, and which parts should be
project-local?

## Finding

Use the **agent-oriented Playwright CLI plus project-local skill/configuration as
the default**. Add Playwright MCP only if a future workflow specifically needs a
client-native tool loop with rich, continuously returned browser structure.

Microsoft's current first-party documentation explicitly recommends the CLI for
coding agents because concise commands avoid loading MCP tool schemas and large
accessibility trees into the model context. It positions MCP for specialized
long-running exploratory, self-healing, or autonomous loops where richer
introspection is worth that context cost.

## Relevant capabilities

The standalone [`@playwright/cli`][cli-readme] already provides the interaction
loop discussed for Bepis:

- named, persistent browser sessions across shell calls
- accessibility snapshots and element references, including depth-limited and
  element-scoped snapshots
- a live [`playwright-cli show`][cli-readme] dashboard with session previews and
  interactive takeover
- screenshots, console messages, network requests, storage state, tracing,
  video, tabs, JavaScript/Playwright evaluation, and request mocking
- generated semantic Playwright TypeScript for every action
- locator generation and a documented plan/generate/heal workflow that attaches
  to a real Playwright Test seed through `--debug=cli`

The official [test-generation guide][cli-test-generation] says each CLI action
emits equivalent TypeScript which is intended as raw material for a durable test.
Assertions are added deliberately after exploration; generated actions are not a
complete regression test by themselves.

The traditional Playwright Test CLI remains useful for human-assisted work:
[`codegen`][codegen] records interactions, [UI Mode][ui-mode]/Inspector support
interactive debugging, and [Trace Viewer][trace-viewer] provides action, DOM,
screenshot, console, and network history. It is less convenient for an autonomous
coding agent because those are primarily GUI workflows rather than concise
stateful shell commands.

[Playwright MCP][mcp-readme] exposes substantially the same browser capabilities as structured
MCP tools and uses accessibility snapshots rather than requiring vision. Its
current README describes MCP as the better fit when persistent rich introspection
and iterative page reasoning outweigh token overhead. It also supports TypeScript
code generation, output files, traces, videos, isolated or persistent profiles,
and workspace-derived profile separation.

## Current Bepis state

Bepis currently pins `@playwright/test` **1.58.2** in `package.json` and pins the
Nix Playwright browser bundle to the same version in `flake.nix`. The project has
the traditional `npx playwright` commands (`codegen`, `test`, `show-trace`, and
`init-agents`), but does **not** currently install the standalone
`playwright-cli` binary.

As of this research, the standalone CLI repository reports package version
**0.1.17** and depends on a newer Playwright build. Adding it without aligning the
Nix browser revision could create incompatible browser expectations. Any adoption
should pin and verify the CLI, Playwright package, and Nix browser bundle together
rather than use `@latest`.

## Recommended ownership

Use a hybrid arrangement:

### Project-local

- pin the compatible CLI/package and browser revisions in the existing Node/Nix
  environment
- commit `.playwright/cli.config.json` with the Bepis browser, viewport, local
  origin restrictions, timeouts, output directory, and test-id convention
- commit a short agent skill/instructions file and wrapper command that starts or
  attaches through the repository's existing E2E seed/global setup
- keep generated tests under `e2e/` and run them through the existing Playwright
  configuration
- write screenshots, snapshots, traces, and temporary generated code under an
  ignored project output directory

### User or harness-level

- generic ability to invoke shell commands or optionally register an MCP server
- headed display/dashboard support
- browser process lifecycle and resource limits

Do not commit browser profiles, storage-state files containing sessions, secrets,
or recordings containing customer data. Use the disposable local E2E database
and test identities. Playwright's origin allowlists are convenience guardrails,
not a complete security boundary; client/process-level restrictions are still
required.

## Recommendation for Bepis

Start with **project-local Playwright CLI + skill**, not MCP. It fits the current
Nix-pinned CLI-oriented harness, is the first-party recommendation for coding
agents, emits the exact TypeScript skeleton desired, and gives both machine-readable
snapshots and a human-observable dashboard. Re-evaluate MCP only if the CLI loop
proves insufficient for long-running exploratory sessions or if the harness gains
first-class MCP lifecycle and permission controls.

[cli-readme]: https://github.com/microsoft/playwright-cli/blob/main/README.md
[cli-test-generation]: https://github.com/microsoft/playwright-cli/blob/main/skills/playwright-cli/references/test-generation.md
[mcp-readme]: https://github.com/microsoft/playwright-mcp/blob/main/README.md
[codegen]: https://playwright.dev/docs/codegen
[ui-mode]: https://playwright.dev/docs/test-ui-mode
[trace-viewer]: https://playwright.dev/docs/trace-viewer
