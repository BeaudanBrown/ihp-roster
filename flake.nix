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

    outputs = inputs@{ self, nixpkgs, ihp, flake-parts, systems, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {

            systems = import systems;
            imports = [ ihp.flakeModules.default ];

            perSystem = { pkgs, inputs', ... }:
                let
                    projectSource =
                        builtins.path {
                            path = ./.;
                            name = "ihp-roster-source";
                            filter =
                                path: type:
                                let
                                    root = toString ./.;
                                    pathStr = toString path;
                                    rel =
                                        if pathStr == root
                                        then ""
                                        else pkgs.lib.removePrefix "${root}/" pathStr;
                                    excluded =
                                        rel == "IHP"
                                        || pkgs.lib.hasPrefix "IHP/" rel
                                        || rel == "build"
                                        || pkgs.lib.hasPrefix "build/" rel
                                        || rel == ".devenv"
                                        || pkgs.lib.hasPrefix ".devenv/" rel
                                        || rel == ".direnv"
                                        || pkgs.lib.hasPrefix ".direnv/" rel
                                        || rel == ".claude"
                                        || pkgs.lib.hasPrefix ".claude/" rel
                                        || rel == "notes"
                                        || pkgs.lib.hasPrefix "notes/" rel
                                        || rel == "output"
                                        || pkgs.lib.hasPrefix "output/" rel;
                                in
                                    !excluded;
                        };
                in {
                ihp = {
                    appName = "app"; # Change this to your project name
                    enable = true;
                    withHoogle = true;
                    # Use a filtered project source so local dev artifacts do not leak into
                    # production packaging or generated app-lib.cabal module discovery.
                    projectPath = projectSource;
                    packages = with pkgs; [
                        # Native dependencies, e.g. imagemagick
                    ];
                    haskellPackages = p: with p; [
                        # Haskell dependencies go here
                        p.ihp
                        p.ihp-mail
                        p.ihp-hspec
                        base64-bytestring
                        base
                        ip
                        wai
                        text
                        zip-archive
                        hspec
                    ];
                    devHaskellPackages = p: with p; [
                        stylish-haskell
                    ];
                };

                # Custom configuration that will start with `devenv up`
                devenv.shells.default = {
                    # Custom processes that don't appear in https://devenv.sh/reference/options/
                    processes = {
                        mailhog.exec = ''
                            exec ${pkgs.mailhog}/bin/MailHog \
                                -smtp-bind-addr 127.0.0.1:1025 \
                                -ui-bind-addr 127.0.0.1:8025 \
                                -api-bind-addr 127.0.0.1:8025
                        '';

                        # Uncomment if you use tailwindcss.
                        # tailwind.exec = "tailwindcss -c tailwind/tailwind.config.js -i ./tailwind/app.css -o static/app.css --watch=always";
                    };

                    packages = [
                        inputs'.playwright.packages.playwright-test
                        pkgs.nodejs_22
                        pkgs.mailhog
                    ];

                    env = {
                        IHP_TELEMETRY_DISABLED = "1";
                        IHP_DEV_CHECKOUT = "/home/beau/documents/projects/ihp";
                        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
                        PLAYWRIGHT_BROWSERS_PATH = "${inputs'.playwright.packages.playwright-driver.browsers}";
                        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
                        SMTP_HOST = "127.0.0.1";
                        SMTP_PORT = "1025";
                        SMTP_ENCRYPTION = "Unencrypted";
                        SMTP_USER = "";
                        SMTP_PASSWORD = "";
                        MAIL_FROM = "noreply@dev.local";
                        APP_BASE_URL = "http://localhost:8000";
                    };

                    scripts = {
                        # Resolve a per-machine state dir for volatile dev wrapper files.
                        # Prefer XDG runtime state so synced working trees do not race on pid/socket files.
                        dev-agent-state-dir.exec = ''
                            set -euo pipefail
                            if [ -n "''${DEVENV_AGENT_STATE_DIR:-}" ]; then
                                printf '%s\n' "$DEVENV_AGENT_STATE_DIR"
                            elif [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
                                printf '%s\n' "$XDG_RUNTIME_DIR/ihp-roster-dev"
                            else
                                printf '%s\n' "$PWD/.devenv/agent"
                            fi
                        '';

                        # Start the app server in the foreground with MailHog alongside it.
                        # Usage: dev-foreground
                        dev-foreground.exec = ''
                            set -euo pipefail

                            MAILHOG="$(command -v MailHog || command -v mailhog)"
                            "$MAILHOG" \
                                -smtp-bind-addr 127.0.0.1:1025 \
                                -ui-bind-addr 127.0.0.1:8025 \
                                -api-bind-addr 127.0.0.1:8025 &
                            MAILHOG_PID=$!
                            APP_PID=""

                            cleanup() {
                                if [ -n "$APP_PID" ]; then
                                    kill "$APP_PID" 2>/dev/null || true
                                fi
                                kill "$MAILHOG_PID" 2>/dev/null || true
                            }
                            trap cleanup EXIT INT TERM

                            if curl -fsS http://127.0.0.1:8000 >/dev/null 2>&1; then
                                echo "App server already running; MailHog available at http://127.0.0.1:8025"
                                wait "$MAILHOG_PID"
                            else
                                echo "Starting app server and MailHog..."
                                start &
                                APP_PID=$!
                                wait "$APP_PID"
                            fi
                        '';

                        # Fast typecheck (~2-3s) without producing binaries.
                        # Usage: typecheck [file]  (default: Main.hs)
                        typecheck.exec = ''
                            set -euo pipefail
                            TARGET="''${1:-Main.hs}"
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
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

                        # Rebuild the isolated automation database from schema + fixtures.
                        # Usage: test-db-reset
                        test-db-reset.exec = ''
                            set -euo pipefail
                            DB_NAME="''${TEST_DATABASE_NAME:-app_test}"
                            DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"
                            LOAD_E2E_FIXTURES="''${TEST_DB_LOAD_E2E_FIXTURES:-0}"
                            SYSTEM_SCHEMA="''${IHP_DEV_CHECKOUT:-$PWD/IHP}/ihp-ide/data/IHPSchema.sql"

                            if [ ! -f "$SYSTEM_SCHEMA" ]; then
                                if [ -n "''${IHP:-}" ] && [ -f "$IHP/lib/IHP/IHPSchema.sql" ]; then
                                    SYSTEM_SCHEMA="$IHP/lib/IHP/IHPSchema.sql"
                                elif [ -f "''${IHP_LIB:-}/IHPSchema.sql" ]; then
                                    SYSTEM_SCHEMA="$IHP_LIB/IHPSchema.sql"
                                else
                                    echo "Could not locate IHPSchema.sql" >&2
                                    exit 1
                                fi
                            fi

                            if ! psql -h "$DB_SOCKET" -d postgres -c "select 1" >/dev/null 2>&1; then
                                echo "Test database reset requires the local postgres socket at $DB_SOCKET" >&2
                                echo "Start the local environment first (e.g. bash ./bin/in-env dev-start or devenv up)." >&2
                                exit 1
                            fi

                            psql -h "$DB_SOCKET" -d postgres -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS "$DB_NAME" WITH (FORCE);
CREATE DATABASE "$DB_NAME";
SQL

                            psql -v ON_ERROR_STOP=1 -h "$DB_SOCKET" -d "$DB_NAME" < "$SYSTEM_SCHEMA"
                            psql -v ON_ERROR_STOP=1 -h "$DB_SOCKET" -d "$DB_NAME" < Application/Schema.sql
                            psql -v ON_ERROR_STOP=1 -h "$DB_SOCKET" -d "$DB_NAME" < Application/Fixtures.sql

                            if [ "$LOAD_E2E_FIXTURES" = "1" ]; then
                                psql -v ON_ERROR_STOP=1 -h "$DB_SOCKET" -d "$DB_NAME" < e2e/fixtures/seed.sql
                            fi
                        '';

                        # Run the hspec test suite.
                        # Usage: test
                        test.exec = ''
                            set -euo pipefail
                            export TEST_DATABASE_NAME="''${TEST_DATABASE_NAME:-app_test}"
                            export TEST_DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"
                            export DATABASE_URL="postgresql:///$TEST_DATABASE_NAME?host=$TEST_DB_SOCKET"
                            test-db-reset
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
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
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            exec ghci $GHC_OPTS Main.hs "$@"
                        '';

                        # Seed a general-purpose development fixture surface into a freshly reset database for manual exploration.
                        # Usage: seed-dev [app|app_test] [--force]
                        seed-dev.exec = ''
                            set -euo pipefail

                            DB_NAME="''${1:-app}"
                            RESET_MODE="''${2:-}"
                            DB_SOCKET="''${DEV_FIXTURE_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"

                            if ! psql -h "$DB_SOCKET" -d postgres -c "select 1" >/dev/null 2>&1; then
                                echo "Dev fixture seeding requires the local postgres socket at $DB_SOCKET" >&2
                                echo "Start the local environment first (e.g. dev-start or devenv up)." >&2
                                exit 1
                            fi

                            case "$DB_NAME" in
                                app_test)
                                    export TEST_DATABASE_NAME="$DB_NAME"
                                    export TEST_DB_SOCKET="$DB_SOCKET"
                                    test-db-reset
                                    ;;
                                app)
                                    make db
                                ;;
                                *)
                                    echo "Unsupported database target: $DB_NAME" >&2
                                    echo "Usage: seed-dev [app|app_test] [--force]" >&2
                                    exit 1
                                    ;;
                            esac

                            if [ -n "$RESET_MODE" ] && [ "$RESET_MODE" != "--force" ]; then
                                echo "Unsupported flag: $RESET_MODE" >&2
                                echo "Usage: seed-dev [app|app_test] [--force]" >&2
                                exit 1
                            fi

                            export DATABASE_URL="postgresql:///$DB_NAME?host=$DB_SOCKET"
                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            mkdir -p build/Script
                            cat > build/Script/SeedDevMain.hs <<'EOF'
import qualified Application.Script.SeedDev as Script
import qualified Config
import IHP.ScriptSupport

main = runScript Config.config Script.run
EOF
                            ghc $GHC_OPTS -iTest -main-is Main build/Script/SeedDevMain.hs \
                                -o build/Script/SeedDev \
                                -odir build/Script \
                                -hidir build/Script
                            exec build/Script/SeedDev
                        '';

                        # Launch a dedicated app server for isolated E2E runs.
                        # Usage: test-e2e-server
                        test-e2e-server.exec = ''
                            set -euo pipefail
                            export TEST_DATABASE_NAME="''${TEST_DATABASE_NAME:-app_e2e}"
                            export TEST_DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"
                            export DATABASE_URL="postgresql:///$TEST_DATABASE_NAME?host=$TEST_DB_SOCKET"
                            export IHP_BROWSER="echo"
                            exec RunDevServer
                        '';

                        # Run Playwright end-to-end tests against the isolated test DB + server.
                        # Usage: e2e [playwright-args...]
                        e2e.exec = ''
                            set -euo pipefail
                            export TEST_DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"
                            export MAILHOG_BASE_URL="''${MAILHOG_BASE_URL:-http://127.0.0.1:8025}"
                            export E2E_RUN_ID="''${E2E_RUN_ID:-$(date +%s)-$$-$RANDOM}"
                            export TEST_DATABASE_NAME="''${TEST_DATABASE_NAME:-app_e2e_$E2E_RUN_ID}"

                            STATE_ROOT="$PWD/.devenv/e2e"
                            STATE_DIR="$STATE_ROOT/$E2E_RUN_ID"
                            PID_FILE="$STATE_DIR/server.pid"
                            LOG_FILE="$STATE_DIR/server.log"
                            MAILHOG_PID_FILE="$STATE_DIR/mailhog.pid"
                            export PLAYWRIGHT_OUTPUT_DIR="$STATE_DIR/test-results"
                            export PLAYWRIGHT_HTML_REPORT_DIR="$STATE_DIR/playwright-report"

                            cleanup() {
                                if [ -n "''${PID_FILE:-}" ] && [ -f "$PID_FILE" ]; then
                                    PID=$(cat "$PID_FILE")
                                    kill -TERM -"$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
                                    rm -f "$PID_FILE"
                                fi

                                if [ -n "''${MAILHOG_PID_FILE:-}" ] && [ -f "$MAILHOG_PID_FILE" ]; then
                                    MAILHOG_PID=$(cat "$MAILHOG_PID_FILE")
                                    kill "$MAILHOG_PID" 2>/dev/null || true
                                    rm -f "$MAILHOG_PID_FILE"
                                fi

                                psql -h "$TEST_DB_SOCKET" -d postgres -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DROP DATABASE IF EXISTS "$TEST_DATABASE_NAME" WITH (FORCE);
SQL
                            }
                            trap cleanup EXIT

                            test-db-reset

                            mkdir -p "$STATE_DIR"
                            : > "$LOG_FILE"

                            if ! curl -fsS "$MAILHOG_BASE_URL/api/v2/messages" >/dev/null 2>&1; then
                                ${pkgs.mailhog}/bin/MailHog \
                                    -smtp-bind-addr 127.0.0.1:1025 \
                                    -ui-bind-addr 127.0.0.1:8025 \
                                    -api-bind-addr 127.0.0.1:8025 \
                                    >>"$LOG_FILE" 2>&1 &
                                echo "$!" > "$MAILHOG_PID_FILE"
                            fi

                            process_group_pids() {
                                local pgid="$1"
                                pgrep -g "$pgid" 2>/dev/null | tr '\n' ' ' || true
                            }

                            detect_e2e_base_url() {
                                local pgid="$1"
                                local pids ports port
                                pids=$(process_group_pids "$pgid")
                                if [ -z "$pids" ]; then
                                    return 1
                                fi

                                ports=$(
                                    lsof -Pan -iTCP -sTCP:LISTEN $(printf ' -p %s' $pids) 2>/dev/null \
                                        | awk 'NR > 1 { split($9, parts, ":"); print parts[length(parts)] }' \
                                        | sort -n -u
                                )

                                for port in $ports; do
                                    if curl -fsS "http://127.0.0.1:$port/NewSession" >/dev/null 2>&1; then
                                        printf 'http://127.0.0.1:%s\n' "$port"
                                        return 0
                                    fi
                                done

                                return 1
                            }

                            setsid nohup test-e2e-server </dev/null >>"$LOG_FILE" 2>&1 &
                            PID=$!
                            echo "$PID" > "$PID_FILE"
                            disown "$PID" 2>/dev/null || true

                            for _ in $(seq 1 120); do
                                if E2E_BASE_URL=$(detect_e2e_base_url "$PID"); then
                                    export E2E_BASE_URL
                                    ln -sfn "$PLAYWRIGHT_HTML_REPORT_DIR" "$STATE_ROOT/latest-report"
                                    echo "E2E app server ready at $E2E_BASE_URL"
                                    echo "E2E run id: $E2E_RUN_ID"
                                    echo "E2E database: $TEST_DATABASE_NAME"
                                    echo "E2E artifacts: $STATE_DIR"
                                    node ./node_modules/@playwright/test/cli.js test "$@"
                                    exit $?
                                fi

                                if ! kill -0 "$PID" 2>/dev/null; then
                                    echo "E2E app server failed to start; recent log output:" >&2
                                    tail -n 80 "$LOG_FILE" >&2 || true
                                    exit 1
                                fi

                                sleep 1
                            done

                            echo "Timed out waiting for isolated E2E app server to become ready" >&2
                            tail -n 80 "$LOG_FILE" >&2 || true
                            exit 1
                        '';

                        # Take a screenshot of a page using Playwright.
                        # Usage: screenshot <url> <output.png>
                        screenshot.exec = ''
                            exec playwright screenshot "$@"
                        '';

                        # Run the Playwright CLI for exploratory browser automation.
                        # Usage: pwcli <playwright-cli-args...>
                        pwcli.exec = ''
                            set -euo pipefail
                            export PWCLI_VERSION="''${PWCLI_VERSION:-0.1.4}"
                            STATE_DIR="$PWD/.devenv/playwright-cli"
                            CONFIG_FILE="$STATE_DIR/cli.config.json"
                            mkdir -p "$STATE_DIR"
                            mkdir -p "$PWD/.playwright"

                            PWCLI_BROWSER="$(
                                find "$PLAYWRIGHT_BROWSERS_PATH" -maxdepth 3 -path '*/chrome-linux64/chrome' | head -n 1
                            )"

                            if [ -z "$PWCLI_BROWSER" ]; then
                                echo "Could not locate Chromium inside PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH" >&2
                                exit 1
                            fi

                            cat >"$CONFIG_FILE" <<EOF
{
  "browser": {
    "browserName": "chromium",
    "launchOptions": {
      "executablePath": "$PWCLI_BROWSER"
    }
  }
}
EOF

                            HAS_CONFIG=false
                            for arg in "$@"; do
                                if [ "$arg" = "--config" ] || [ "''${arg#--config=}" != "$arg" ]; then
                                    HAS_CONFIG=true
                                    break
                                fi
                            done

                            if [ "$HAS_CONFIG" = true ]; then
                                exec npx --yes --package "@playwright/cli@$PWCLI_VERSION" playwright-cli "$@"
                            fi

                            exec npx --yes --package "@playwright/cli@$PWCLI_VERSION" playwright-cli --config "$CONFIG_FILE" "$@"
                        '';

                        # Save authenticated Playwright CLI storage state for a seeded dev role.
                        # Usage: pwcli-auth-save <manager|worker|admin|support> [output-file]
                        pwcli-auth-save.exec = ''
                            exec node ./e2e/pwcli-auth-state.mjs "$@"
                        '';

                        # Open a Playwright CLI session with preloaded authenticated state.
                        # Usage: pwcli-auth-open <manager|worker|admin|support> [path-or-url]
                        pwcli-auth-open.exec = ''
                            set -euo pipefail

                            ROLE="''${1:-}"
                            TARGET="''${2:-/RosterWeeks}"
                            BASE_URL="''${PWCLI_BASE_URL:-http://127.0.0.1:8000}"

                            if [ -z "$ROLE" ]; then
                                echo "Usage: pwcli-auth-open <manager|worker|admin|support> [path-or-url]" >&2
                                exit 1
                            fi

                            STATE_FILE="$PWD/.devenv/playwright-cli/$ROLE-state.json"
                            SESSION_NAME="ihp-$ROLE"

                            if [ ! -f "$STATE_FILE" ]; then
                                echo "Missing auth state at $STATE_FILE" >&2
                                echo "Run: bash ./bin/in-env pwcli-auth-save $ROLE" >&2
                                exit 1
                            fi

                            case "$TARGET" in
                                http://*|https://*)
                                    TARGET_URL="$TARGET"
                                    ;;
                                *)
                                    case "$TARGET" in
                                        /*) ;;
                                        *) TARGET="/$TARGET" ;;
                                    esac
                                    TARGET_URL="$BASE_URL$TARGET"
                                    ;;
                            esac

                            pwcli -s="$SESSION_NAME" open "$BASE_URL"
                            pwcli -s="$SESSION_NAME" state-load "$STATE_FILE"
                            exec pwcli -s="$SESSION_NAME" goto "$TARGET_URL"
                        '';

                        # Take a screenshot of an authenticated page with reusable login/navigation flow.
                        # Usage: screenshot-page <path-or-url> <output.png> [--selector <css>] [--email <email>] [--password <password>] [--no-login]
                        screenshot-page.exec = ''
                            exec node ./e2e/screenshot-page.mjs "$@"
                        '';

                        # Open the Playwright HTML test report.
                        # Usage: e2e-report
                        e2e-report.exec = ''
                            REPORT_DIR="''${PLAYWRIGHT_HTML_REPORT_DIR:-$PWD/.devenv/e2e/latest-report}"
                            exec playwright show-report "$REPORT_DIR"
                        '';

                        # Start devenv processes in background for automation.
                        # Usage: dev-start
                        dev-start.exec = ''
                            set -euo pipefail
                            STATE_DIR="$(dev-agent-state-dir)"
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

                        # Stop background devenv processes started by dev-start.
                        # Usage: dev-stop
                        dev-stop.exec = ''
                            set -euo pipefail
                            STATE_DIR="$(dev-agent-state-dir)"
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

                        # Check health of background devenv server.
                        # Usage: dev-status
                        dev-status.exec = ''
                            set -euo pipefail
                            STATE_DIR="$(dev-agent-state-dir)"
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
                            elif echo "$DB_ERR" | ${pkgs.ripgrep}/bin/rg -qi "operation not permitted|permission denied"; then
                                DB_BLOCKED=true
                            fi

                            HTTP_OK=false
                            HTTP_BLOCKED=false
                            HTTP_ERR=""
                            if HTTP_ERR=$(curl -fsS "http://127.0.0.1:8000" 2>&1); then
                                HTTP_OK=true
                            elif echo "$HTTP_ERR" | ${pkgs.ripgrep}/bin/rg -qi "operation not permitted|permission denied"; then
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

                            # Consider the app "running" if it's reachable via DB+HTTP,
                            # even when it was started outside of dev-start (no pid/socket file).
                            if [ "$DB_OK" = true ] && [ "$HTTP_OK" = true ]; then
                                RUNNING=true
                            fi

                            echo "running=$RUNNING managed=$MANAGED socket_ok=$SOCKET_OK pid=''${PID:-none} db_ok=$DB_OK http_ok=$HTTP_OK db_blocked=$DB_BLOCKED http_blocked=$HTTP_BLOCKED"

                            if [ "$DB_OK" = true ] && [ "$HTTP_OK" = true ]; then
                                exit 0
                            fi

                            # In restricted sandbox environments network/socket checks can be blocked.
                            # In that case, treat a running process as healthy enough for automation.
                            if [ "$RUNNING" = true ] && [ "$CHECKS_BLOCKED" = true ]; then
                                exit 0
                            fi

                            exit 1
                        '';

                        # Wait for background devenv server to become healthy.
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
                                    tail -n 80 "$(dev-agent-state-dir)/devenv.log" || true
                                    exit 1
                                fi

                                sleep 1
                            done
                        '';
                    };
                };
            };

            flake.nixosModules.default = import ./Config/nix/modules/ihp-roster.nix {
                inherit self;
                ihp = inputs.ihp;
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
