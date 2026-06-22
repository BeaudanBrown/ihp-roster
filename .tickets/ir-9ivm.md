---
id: ir-9ivm
status: closed
deps: []
links: []
created: 2026-06-22T00:10:20Z
type: task
priority: 2
assignee: beaudan
tags: [agent-loop, haskell, nix, frontend, guardrail]
---
# Catch Haskell module path mismatches

Fix frontend contract generator module naming so production app-lib builds, and add a guard for path/module declaration mismatches.

## Design

Rename Application/Script/GenerateFrontendContracts to match its path, keep the direct generator executable working with -main-is, add a haskell-module-name-check script plus flake check, and call the guard from typecheck.

## Acceptance Criteria

frontend-contracts-check still passes; typecheck catches module-name mismatches; focused Nix production app build reaches app-binaries successfully; haskell-module-name flake check passes.


## Notes

**2026-06-22T00:10:27Z**

Changed Application/Script/GenerateFrontendContracts.hs from module Main to Application.Script.GenerateFrontendContracts and added run :: Script so IHP production script wrapper generation still compiles. Updated frontend contract scripts to compile the direct generator with -main-is. Added Config/nix/scripts/haskell/module-name-check, exposed it as a devenv script, wired it into typecheck, and added checks.haskell-module-names. Verified direct module-name check, frontend-contracts-check, typecheck Application/Script/GenerateFrontendContracts.hs, frontend-check, doc-drift-check, nix build .#checks.x86_64-linux.haskell-module-names, and nix build .#checks.x86_64-linux.unoptimized-prod-server.
