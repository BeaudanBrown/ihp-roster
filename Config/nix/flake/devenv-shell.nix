{ ... }:
{
    perSystem = { pkgs, inputs', ... }:
        let
            scriptDefinitions = import ./scripts.nix { inherit pkgs; };
            projectSource = import ./project-source.nix { inherit pkgs; };
            e2eTypeScriptDependencies = pkgs.buildNpmPackage {
                pname = "ihp-roster-e2e-typescript-dependencies";
                version = "1";
                src = ../e2e-types;
                npmDepsHash = "sha256-7BcpwLy9Anvkm7kUJlOnY+MJeednbdO1so220GYaiBU=";
                dontNpmBuild = true;
                installPhase = ''
                    mkdir -p "$out/lib"
                    cp -R node_modules "$out/lib/node_modules"
                '';
            };
        in
        {
            # Custom configuration that will start with `devenv up`
            devenv.shells.default = {
                overlays = import ./overlays.nix;

                # Custom processes that don't appear in https://devenv.sh/reference/options/
                processes = scriptDefinitions.processes;

                packages = [
                    inputs'.playwright.packages.playwright-test
                    pkgs.nodejs_22
                    pkgs.esbuild
                    pkgs.typescript
                    pkgs.haskellPackages.weeder
                    pkgs.mailhog
                    pkgs.poppler-utils
                    # Verification-only spreadsheet recalculation; excluded from ihp-app/production.
                    pkgs.libreoffice
                    pkgs.k6
                    pkgs.jq
                    pkgs.gh
                    pkgs.lsof
                    pkgs.procps
                    pkgs.graphviz
                    pkgs.opentelemetry-collector-contrib
                    pkgs.tempo
                    pkgs.grafana-loki
                    pkgs.grafana
                    pkgs.stripe-cli
                ];

                files.".ghci".source = ../../../Config/ghci;

                env = {
                    IHP_TELEMETRY_DISABLED = "1";
                    IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH = "false";
                    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
                    PLAYWRIGHT_BROWSERS_PATH = "${inputs'.playwright.packages.playwright-driver.browsers}";
                    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
                    E2E_TYPESCRIPT_NODE_MODULES = "${e2eTypeScriptDependencies}/lib/node_modules";
                    SMTP_HOST = "127.0.0.1";
                    SMTP_PORT = "1025";
                    SMTP_ENCRYPTION = "Unencrypted";
                    SMTP_USER = "";
                    SMTP_PASSWORD = "";
                    MAIL_FROM = "noreply@dev.local";
                    APP_BASE_URL = "http://localhost:8000";
                };

                scripts = scriptDefinitions.scripts;
            };

            checks.frontend-drift = pkgs.runCommand "frontend-drift-check" {
                src = projectSource;
                nativeBuildInputs = [
                    pkgs.esbuild
                    pkgs.nodejs_22
                    pkgs.typescript
                ];
            } ''
                cp -R "$src" source
                chmod -R u+w source
                cd source
                tsc --project tsconfig.json --noEmit
                bash Config/nix/scripts/frontend/test
                bash Config/nix/scripts/frontend/drift-check
                touch "$out"
            '';

            checks.haskell-module-names = pkgs.runCommand "haskell-module-name-check" {
                src = projectSource;
            } ''
                cp -R "$src" source
                chmod -R u+w source
                cd source
                bash Config/nix/scripts/haskell/module-name-check
                touch "$out"
            '';
        };
}
