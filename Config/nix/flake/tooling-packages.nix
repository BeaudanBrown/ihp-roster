{ pkgs, root ? ../../.. }:
let
    sources = import ./tooling-source.nix { inherit root; };
    haskellPackages = pkgs.haskellPackages.override {
        overrides = self: _super: {
            bepis-tooling-core = self.callCabal2nix "bepis-tooling-core" sources.core { };
            bepis-workspace-state = self.callCabal2nix "bepis-workspace-state" sources.workspaceState { };
        };
    };
in
{
    inherit sources;
    core = haskellPackages.bepis-tooling-core;
    workspaceState = haskellPackages.bepis-workspace-state;
    ghc = haskellPackages.ghcWithPackages (p: [ p.aeson p.temporary ]);
}
