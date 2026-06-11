{ self, inputs, ... }:
{
    flake.nixosModules.default = import ../modules/ihp-roster.nix {
        inherit self;
        ihp = inputs.ihp;
    };

    # Adding the new NixOS configuration for "production"
    # See https://ihp.digitallyinduced.com/Guide/deployment.html#deploying-with-deploytonixos for more info
    # Used to deploy the IHP application
    flake.nixosConfigurations."production" = import ../hosts/production/host.nix { inherit inputs; };
}
