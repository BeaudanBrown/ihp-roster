{
    inputs = {
        ihp.url = "git+https://github.com/digitallyinduced/ihp.git?rev=df3922d1a7166b131674efa3d3555ed7195ddf70&submodules=1";
        nixpkgs.follows = "ihp/nixpkgs";
        flake-parts.follows = "ihp/flake-parts";
        devenv.follows = "ihp/devenv";
        systems.follows = "ihp/systems";
        devenv-root = {
            url = "file+file:///dev/null";
            flake = false;
        };
        playwright.url = "github:pietdevries94/playwright-web-flake/1.58.2";
    };

    outputs = inputs@{ ihp, flake-parts, systems, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {
            systems = import systems;
            imports = [
                ihp.flakeModules.default
                ./Config/nix/flake/ihp-app.nix
                ./Config/nix/flake/devenv-shell.nix
                ./Config/nix/flake/exports.nix
            ];
        };

    # Use the devenv, Cachix, and Digitally Induced binary caches.
    nixConfig = {
        extra-substituters = [
            "https://devenv.cachix.org"
            "https://cachix.cachix.org"
            "https://digitallyinduced.cachix.org"
        ];
        extra-trusted-public-keys = [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
            "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
        ];
    };
}
