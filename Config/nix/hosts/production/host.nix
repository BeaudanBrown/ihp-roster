{ inputs }:
inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux"; # or alternatively: aarch64-linux
    specialArgs = inputs // { inherit inputs; };
    modules = [ ./configuration.nix ];
}
