{ pkgs, root ? ../../.. }:
let
    sources = import ./tooling-source.nix { inherit root; };
    haskellPackages = pkgs.haskellPackages.override {
        overrides = self: _super: {
            bepis-tooling-core = self.callCabal2nix "bepis-tooling-core" sources.core { };
            bepis-workspace-state = self.callCabal2nix "bepis-workspace-state" sources.workspaceState { };
            bepis-postgres = self.callCabal2nix "bepis-postgres" sources.postgres { };
            bepis-runtime = self.callCabal2nix "bepis-runtime" sources.runtime { };
        };
    };
in
{
    inherit sources;
    core = haskellPackages.bepis-tooling-core;
    workspaceState = haskellPackages.bepis-workspace-state;
    postgres = haskellPackages.bepis-postgres;
    runtime = haskellPackages.bepis-runtime;
    ghc = haskellPackages.ghcWithPackages (p: [ p.aeson p.temporary ]);
}
