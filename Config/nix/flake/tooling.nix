{ ... }:
{
    perSystem = { pkgs, ... }:
        let
            tooling = import ./tooling-packages.nix { inherit pkgs; };
        in
        {
            packages.bepis-tooling-core = tooling.core;
            packages.bepis-workspace-state = tooling.workspaceState;

            devShells.tooling = pkgs.mkShell {
                packages = [
                    pkgs.cabal-install
                    tooling.ghc
                ];
                BEPIS_TOOLING_ENV = "1";
            };
        };
}
