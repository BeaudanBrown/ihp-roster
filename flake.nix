{
    inputs = {
        ihp.url = "git+https://github.com/digitallyinduced/ihp.git?rev=71b7bb685d2a60b20cd19c8a810c8931369e5efb&submodules=1";
        nixpkgs.follows = "ihp/nixpkgs";
        # Keep Tempo's storage/retention protocol stable during the IHP upgrade.
        # Deliberately source only Tempo from the previous package set (#540).
        nixpkgs-tempo = {
            url = "github:NixOS/nixpkgs/0590cd39f728e129122770c029970378a79d076a";
            flake = false;
        };
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
                ./Config/nix/flake/android-emulator.nix
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
