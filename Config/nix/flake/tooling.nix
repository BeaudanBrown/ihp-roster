{ ... }:
{
    perSystem = { pkgs, ... }:
        let
            tooling = import ./tooling-packages.nix { inherit pkgs; };
        in
        {
            packages.bepis-tooling-core = tooling.core;
            packages.bepis-workspace-state = tooling.workspaceState;
            packages.bepis-postgres = tooling.postgres;
            packages.bepis-runtime = tooling.runtime;
            packages.bepis-epic-lifecycle = tooling.epicLifecycle;
            packages.bepis-artifacts = tooling.artifacts;
            packages.bepis-runners = tooling.runners;

            devShells.tooling = pkgs.mkShell {
                packages = [
                    pkgs.cabal-install
                    pkgs.git
                    pkgs.gh
                    tooling.ghc
                ];
                BEPIS_TOOLING_ENV = "1";
            };
        };
}
