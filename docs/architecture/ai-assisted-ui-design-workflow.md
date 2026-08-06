# AI-Assisted UI Design Decision

AI design tools may propose and compare visual changes, but checked-in Haskell
helpers, semantic CSS, typed frontend contracts, and deterministic browser tests
remain authoritative. This decision supports the UI work linked from GitHub
issue [#117](https://github.com/BeaudanBrown/ihp-roster/issues/117); GitHub owns
its scope and status.

## Existing Boundary

Bepis is server-rendered IHP/HSX. Shared markup belongs in
`Application/Helper/View/`, browser contracts are generated from Haskell, app
TypeScript owns generic browser mechanics, and CSS is app-owned under `static/`.
Playwright exercises production rendering against deterministic fixtures.
Generated React, Tailwind, Vite, or standalone HTML scaffolds do not preserve
those authorization, routing, HTMX, Surface, or helper boundaries and must not
be merged as production architecture.

For current source-derived structure, use `architecture_query` with
`generated-contracts`, inspect `Web/View/Layout.hs`, and run:

```bash
bash ./bin/in-env frontend-check
bash ./bin/in-env ./bin/style-audit
bash ./bin/in-env e2e
```

Do not retain generated contract counts, CSS inventories, or screenshot status
in this document.

## Recommended Workflow

1. Explore a seeded local page with the repository's Nix-pinned Playwright Agent
   CLI (`bash ./bin/in-env pwcli`). Never use production/customer data.
2. Treat screenshots, design frames, and generated HTML as proposals.
3. Translate approved intent into the narrowest production owner: semantic
   token, Haskell helper, shared CSS, or feature CSS.
4. Verify normal and edge states in the real app with structural Playwright
   assertions; use small stable screenshots only where visual comparison is the
   intended contract.
5. Keep accessibility, authorization, generated contracts, responsive behavior,
   and browser interaction under their existing deterministic gates.

A future component gallery should render real production Haskell helpers and
CSS, not duplicate them in Storybook. It should cover normal, empty, loading,
error, disabled, read-only, validation, long-content, keyboard, and narrow
viewport states using synthetic data.

## Design-Tool Boundary

Choose at most one collaborative design authority for a pilot:

- **Figma MCP plus Code Connect** when collaboration and mature component
  tooling justify the service/seat requirements. Map components to Haskell
  helper examples rather than invented React components.
- **Pencil** when Linux and Git-native design files are more valuable. Prove
  merge behavior, CLI stability, and one contained handoff before retaining
  `.pen` files.
- **Penpot** is a self-hostable alternative when that operational requirement
  outweighs its additional plugin/server setup.

Generative app builders may produce disposable concepts only. Networked design
services, hosted visual review, and credentials must remain opt-in development
inputs, never production or hermetic build dependencies.

If shared visual constants later need tool synchronization, prefer Git-owned
DTCG tokens feeding deterministic CSS generation and one selected design tool.
Do not make a design service the build-time source of truth.

## Durable Sources

Primary external references retained for future tool evaluation:

- [Playwright Agent CLI](https://playwright.dev/agent-cli/introduction) and
  [visual comparisons](https://playwright.dev/docs/test-snapshots)
- [Figma MCP](https://developers.figma.com/docs/figma-mcp-server/) and
  [Code Connect](https://github.com/figma/code-connect)
- [W3C Design Tokens format](https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/)
  and [Style Dictionary DTCG support](https://styledictionary.com/info/dtcg/)
- [Pencil Git-friendly files](https://docs.pencil.dev/core-concepts/pen-files)
  and [CLI](https://docs.pencil.dev/for-developers/pencil-cli)
- [Penpot MCP](https://help.penpot.app/mcp/)

Revisit the selected tool only through a ticket that identifies the workflow
problem, one bounded pilot, repository/Nix integration, data-handling boundary,
and deterministic acceptance evidence.
