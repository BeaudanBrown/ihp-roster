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
                                exec hlint -XQuasiQuotes "$@"
                            fi
                            hlint -XQuasiQuotes Main.hs Web/ Application/Helper/ Config/
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

                        screenshot-page.exec = ''
                            exec node ./e2e/screenshot-page.mjs "$@"
                        '';

                        # Start IHP in background for automation.
                        # Usage: dev-start
                        dev-start.exec = ''
                            set -euo pipefail
                            STATE_DIR="$PWD/.devenv/agent"
                            PID_FILE="$STATE_DIR/devenv.pid"
                            LOG_FILE="$STATE_DIR/devenv.log"

                            mkdir -p "$STATE_DIR"

                            if dev-status >/dev/null 2>&1; then
                                echo "devenv already healthy"
                                exit 0
                            fi

                            if [ -f "$PID_FILE" ]; then
                                PID=$(cat "$PID_FILE")
                                if kill -0 "$PID" 2>/dev/null; then
                                    echo "devenv already running (pid=$PID)"
                                    exit 0
                                fi
                                rm -f "$PID_FILE"
                            fi

                            : > "$LOG_FILE"
                            # In restricted sandboxes ~/.cache can be read-only, which makes
                            # nix/direnv evaluation fail while writing fetcher cache.
                            export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-/tmp/nix-cache}"
                            mkdir -p "$XDG_CACHE_HOME"
                            echo "[dev-start] launching start (XDG_CACHE_HOME=$XDG_CACHE_HOME)" >>"$LOG_FILE"
                            setsid nohup start </dev/null >>"$LOG_FILE" 2>&1 &
                            PID=$!
                            echo "$PID" > "$PID_FILE"
                            disown "$PID" 2>/dev/null || true

                            # Surface startup failures immediately (e.g. missing dependencies)
                            for _ in $(seq 1 3); do
                                sleep 1
                                if ! kill -0 "$PID" 2>/dev/null; then
                                    echo "devenv failed to start; recent log output:"
                                    tail -n 60 "$LOG_FILE" || true
                                    rm -f "$PID_FILE"
                                    exit 1
                                fi
                            done

                            echo "devenv started (pid=$PID, log=$LOG_FILE)"
                        '';

                        # Stop background server started by dev-start.
                        # Usage: dev-stop
                        dev-stop.exec = ''
                            set -euo pipefail
                            STATE_DIR="$PWD/.devenv/agent"
                            PID_FILE="$STATE_DIR/devenv.pid"

                            if [ ! -f "$PID_FILE" ]; then
                                if dev-status >/dev/null 2>&1; then
                                    echo "devenv is healthy but unmanaged (no pid file); not stopping"
                                    exit 0
                                fi
                                echo "devenv not running (no pid file)"
                                exit 0
                            fi

                            PID=$(cat "$PID_FILE")
                            if ! kill -0 "$PID" 2>/dev/null; then
                                rm -f "$PID_FILE"
                                if dev-status >/dev/null 2>&1; then
                                    echo "devenv is healthy but unmanaged (stale pid file removed); not stopping"
                                    exit 0
                                fi
                                echo "devenv not running (stale pid file removed)"
                                exit 0
                            fi

                            kill -TERM -"$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true

                            for _ in $(seq 1 20); do
                                if ! kill -0 "$PID" 2>/dev/null; then
                                    rm -f "$PID_FILE"
                                    echo "devenv stopped"
                                    exit 0
                                fi
                                sleep 1
                            done

                            kill -KILL -"$PID" 2>/dev/null || kill -KILL "$PID" 2>/dev/null || true
                            rm -f "$PID_FILE"
                            echo "devenv force-stopped"
                        '';

                        # Check health of background server.
                        # Usage: dev-status
                        dev-status.exec = ''
                            set -euo pipefail
                            STATE_DIR="$PWD/.devenv/agent"
                            PID_FILE="$STATE_DIR/devenv.pid"
                            SOCKET_FILE="$STATE_DIR/pc.sock"
                            PID=""

                            if [ -f "$PID_FILE" ]; then
                                PID=$(cat "$PID_FILE")
                                if ! kill -0 "$PID" 2>/dev/null; then
                                    rm -f "$PID_FILE"
                                    PID=""
                                fi
                            fi

                            RUNNING=false
                            if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                                RUNNING=true
                            fi

                            SOCKET_OK=false
                            if [ -S "$SOCKET_FILE" ] && lsof "$SOCKET_FILE" >/dev/null 2>&1; then
                                SOCKET_OK=true
                                RUNNING=true
                            fi

                            DB_OK=false
                            DB_BLOCKED=false
                            DB_ERR=""
                            if DB_ERR=$(psql -h "$PWD/build/db" -d app -c "select 1" 2>&1); then
                                DB_OK=true
                            elif echo "$DB_ERR" | rg -qi "operation not permitted|permission denied"; then
                                DB_BLOCKED=true
                            fi

                            HTTP_OK=false
                            HTTP_BLOCKED=false
                            HTTP_ERR=""
                            if HTTP_ERR=$(curl -fsS "http://127.0.0.1:8000" 2>&1); then
                                HTTP_OK=true
                            elif echo "$HTTP_ERR" | rg -qi "operation not permitted|permission denied"; then
                                HTTP_BLOCKED=true
                            fi

                            CHECKS_BLOCKED=false
                            if { [ "$DB_OK" = true ] || [ "$DB_BLOCKED" = true ]; } \
                                && { [ "$HTTP_OK" = true ] || [ "$HTTP_BLOCKED" = true ]; }; then
                                CHECKS_BLOCKED=true
                            fi

                            MANAGED=false
                            if [ -n "$PID" ] || [ "$SOCKET_OK" = true ]; then
                                MANAGED=true
                            fi

                            if [ "$DB_OK" = true ] && [ "$HTTP_OK" = true ]; then
                                RUNNING=true
                            fi

                            echo "running=$RUNNING managed=$MANAGED socket_ok=$SOCKET_OK pid=''${PID:-none} db_ok=$DB_OK http_ok=$HTTP_OK db_blocked=$DB_BLOCKED http_blocked=$HTTP_BLOCKED"

                            if [ "$DB_OK" = true ] && [ "$HTTP_OK" = true ]; then
                                exit 0
                            fi

                            if [ "$RUNNING" = true ] && [ "$CHECKS_BLOCKED" = true ]; then
                                exit 0
                            fi

                            exit 1
                        '';

                        # Wait for background server to become healthy.
                        # Usage: dev-wait [timeout-seconds]
                        dev-wait.exec = ''
                            set -euo pipefail
                            TIMEOUT="''${1:-90}"
                            START_TS=$(date +%s)

                            while true; do
                                if dev-status >/dev/null 2>&1; then
                                    dev-status
                                    exit 0
                                fi

                                NOW_TS=$(date +%s)
                                if [ $((NOW_TS - START_TS)) -ge "$TIMEOUT" ]; then
                                    echo "Timed out waiting for devenv health after ''${TIMEOUT}s"
                                    dev-status || true
                                    echo "--- recent devenv log ---"
                                    tail -n 80 "$PWD/.devenv/agent/devenv.log" || true
                                    exit 1
                                fi

                                sleep 1
                            done
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
