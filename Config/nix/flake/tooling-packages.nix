{ pkgs, root ? ../../.. }:
let
    sources = import ./tooling-source.nix { inherit root; };
    haskellPackages = pkgs.haskellPackages.override {
        overrides = self: _super: {
            bepis-tooling-core = self.callCabal2nix "bepis-tooling-core" sources.core { };
            bepis-workspace-state = self.callCabal2nix "bepis-workspace-state" sources.workspaceState { };
            bepis-postgres = self.callCabal2nix "bepis-postgres" sources.postgres { };
        };
    };
in
{
    inherit sources;
    core = haskellPackages.bepis-tooling-core;
    workspaceState = haskellPackages.bepis-workspace-state;
    postgres = haskellPackages.bepis-postgres;
    ghc = haskellPackages.ghcWithPackages (p: [ p.aeson p.temporary ]);
}
