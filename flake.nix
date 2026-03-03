{
    inputs = {
        self.submodules = true;
        ihp.url = ./IHP;
        # ihp.url = "github:digitallyinduced/ihp/v1.4";
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

    outputs = inputs@{ self, nixpkgs, ihp, flake-parts, systems, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {

            systems = import systems;
            imports = [ ihp.flakeModules.default ];

            perSystem = { pkgs, inputs', ... }: {
                ihp = {
                    appName = "app"; # Change this to your project name
                    enable = true;
                    withHoogle = true;
                    projectPath = ./.;
                    packages = with pkgs; [
                        # Native dependencies, e.g. imagemagick
                    ];
                    haskellPackages = p: with p; [
                        # Haskell dependencies go here
                        p.ihp
                        cabal-install
                        base
                        wai
                        text
                        hlint
                        stylish-haskell
                        hspec
                        # ihp-mail
                        # See https://ihp.digitallyinduced.com/Guide/mail.html
                    ];
                };

                # Custom configuration that will start with `devenv up`
                devenv.shells.default = {
                    # Start Mailhog on local development to catch outgoing emails
                    # services.mailhog.enable = true;

                    # Custom processes that don't appear in https://devenv.sh/reference/options/
                    processes = {
                        # Uncomment if you use tailwindcss.
                        # tailwind.exec = "tailwindcss -c tailwind/tailwind.config.js -i ./tailwind/app.css -o static/app.css --watch=always";
                    };

                    packages = [
                        inputs'.playwright.packages.playwright-test
                        pkgs.nodejs_22
                    ];

                    env = {
                        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
                        PLAYWRIGHT_BROWSERS_PATH = "${inputs'.playwright.packages.playwright-driver.browsers}";
                        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
                    };

                    scripts = {
                        # Fast typecheck (~2-3s) without producing binaries.
                        # Usage: typecheck [file]  (default: Main.hs)
                        typecheck.exec = ''
                            set -euo pipefail
                            TARGET="''${1:-Main.hs}"
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS=${"''"} 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            exec ghc -fno-code $GHC_OPTS "$TARGET"
                        '';

                        # Regenerate Haskell types from Application/Schema.sql.
                        # Run after any schema change.
                        regen-types.exec = ''
                            set -euo pipefail
                            mkdir -p build/Generated
                            build-generated-code
                            echo "Types regenerated in build/Generated/"
                        '';

                        # Run the hspec test suite.
                        # Usage: test
                        test.exec = ''
                            set -euo pipefail
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS=${"''"} 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            mkdir -p build/Test
                            ghc $GHC_OPTS -iTest -main-is Main Test/Main.hs -o build/Test/Main -odir build/Test -hidir build/Test
                            exec build/Test/Main "$@"
                        '';

                        # Run hlint on app source files.
                        # Usage: lint [file_or_dir]  (default: all app sources)
                        lint.exec = ''
                            set -euo pipefail
                            if [ $# -gt 0 ]; then
                                exec hlint "$@"
                            fi
                            hlint Main.hs Web/ Application/Helper/ Config/
                        '';

                        # Format Haskell files with stylish-haskell.
                        # Usage: format [file ...]  (default: all app sources)
                        format.exec = ''
                            set -euo pipefail
                            if [ $# -gt 0 ]; then
                                exec stylish-haskell -i "$@"
                            fi
                            find . -name '*.hs' \
                                -not -path './IHP/*' \
                                -not -path './build/*' \
                                -not -path './.devenv/*' \
                                -not -path './.direnv/*' \
                                -exec stylish-haskell -i {} +
                            echo "Formatted all app sources."
                        '';

                        # Launch GHCi with the full app loaded.
                        # Usage: ghci-app
                        ghci-app.exec = ''
                            set -euo pipefail
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS=${"''"} 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            exec ghci $GHC_OPTS Main.hs "$@"
                        '';

                        # Run Playwright end-to-end tests.
                        # Usage: e2e [playwright-args...]
                        e2e.exec = ''
                            exec npx playwright test "$@"
                        '';

                        # Take a screenshot of a page using Playwright.
                        # Usage: screenshot <url> <output.png>
                        screenshot.exec = ''
                            exec npx playwright screenshot "$@"
                        '';

                        # Open the Playwright HTML test report.
                        # Usage: e2e-report
                        e2e-report.exec = ''
                            exec npx playwright show-report
                        '';
                    };
                };
            };

            # Adding the new NixOS configuration for "production"
            # See https://ihp.digitallyinduced.com/Guide/deployment.html#deploying-with-deploytonixos for more info
            # Used to deploy the IHP application
            flake.nixosConfigurations."production" = import ./Config/nix/hosts/production/host.nix { inherit inputs; };
        };

    # The following configuration speeds up build times by using the devenv, cachix and digitallyinduced binary caches
    # You can add your own cachix cache here to speed up builds. For that uncomment the following lines and replace `CHANGE-ME` with your cachix cache name
    nixConfig = {
        extra-substituters = [
            "https://devenv.cachix.org"
            "https://cachix.cachix.org"
            "https://digitallyinduced.cachix.org"
            # "https://CHANGE-ME.cachix.org"
        ];
        extra-trusted-public-keys = [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
            "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
            # "CHANGE-ME.cachix.org-1:CHANGE-ME-PUBLIC-KEY"
        ];
    };
}
