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
                        hlint
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
                        # Usage: test [hspec-args...]
                        test.exec = ''
                            set -euo pipefail
                            BASE_TEST_DATABASE_NAME="''${TEST_DATABASE_NAME:-app_test}"
                            export TEST_DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"

                            detect_cpu_count() {
                                if command -v getconf >/dev/null 2>&1; then
                                    getconf _NPROCESSORS_ONLN 2>/dev/null && return 0
                                fi
                                if command -v nproc >/dev/null 2>&1; then
                                    nproc && return 0
                                fi
                                printf '1\n'
                            }

                            detect_test_shards() {
                                if [ -n "''${TEST_SHARDS:-}" ]; then
                                    printf '%s\n' "$TEST_SHARDS"
                                    return 0
                                fi

                                if [ "$#" -gt 0 ]; then
                                    printf '1\n'
                                    return 0
                                fi

                                detect_cpu_count
                            }

                            TEST_SHARDS="$(detect_test_shards "$@")"
                            case "$TEST_SHARDS" in
                                ""|*[!0-9]*)
                                    echo "TEST_SHARDS must be a positive integer, got: $TEST_SHARDS" >&2
                                    exit 1
                                    ;;
                            esac
                            if [ "$TEST_SHARDS" -lt 1 ]; then
                                echo "TEST_SHARDS must be at least 1" >&2
                                exit 1
                            fi

                            GHC_OPTS=$(make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
                              | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')
                            mkdir -p build/Test
                            ghc $GHC_OPTS -iTest -main-is Main Test/Main.hs -o build/Test/Main -odir build/Test -hidir build/Test

                            if [ "$TEST_SHARDS" -eq 1 ]; then
                                export TEST_DATABASE_NAME="$BASE_TEST_DATABASE_NAME"
                                export DATABASE_URL="postgresql:///$TEST_DATABASE_NAME?host=$TEST_DB_SOCKET"
                                test-db-reset
                                exec build/Test/Main "$@"
                            fi

                            RUN_ID="''${TEST_RUN_ID:-$(date +%s)-$$-$RANDOM}"
                            STATE_ROOT="$PWD/.devenv/test"
                            STATE_DIR="$STATE_ROOT/$RUN_ID"
                            mkdir -p "$STATE_DIR"
                            ln -sfn "$STATE_DIR" "$STATE_ROOT/latest"

                            shard_pids=()
                            shard_statuses=()

                            run_test_shard() {
                                local shard_index="$1"
                                shift
                                local shard_db_name="''${BASE_TEST_DATABASE_NAME}_''${RUN_ID}_shard_''${shard_index}"
                                local shard_log="$STATE_DIR/shard-$shard_index.log"

                                (
                                    export TEST_SHARD_INDEX="$shard_index"
                                    export TEST_SHARD_TOTAL="$TEST_SHARDS"
                                    export TEST_DATABASE_NAME="$shard_db_name"
                                    export DATABASE_URL="postgresql:///$TEST_DATABASE_NAME?host=$TEST_DB_SOCKET"

                                    cleanup() {
                                        if [ "''${TEST_KEEP_DATABASES:-0}" = "1" ]; then
                                            return 0
                                        fi

                                        psql -h "$TEST_DB_SOCKET" -d postgres -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DROP DATABASE IF EXISTS "$TEST_DATABASE_NAME" WITH (FORCE);
SQL
                                    }
                                    trap cleanup EXIT INT TERM

                                    test-db-reset
                                    build/Test/Main "$@"
                                    exit $?
                                ) >"$shard_log" 2>&1 &

                                shard_pids+=("$!")
                            }

                            for shard_index in $(seq 1 "$TEST_SHARDS"); do
                                run_test_shard "$shard_index" "$@"
                            done

                            failed=0
                            for shard_offset in "''${!shard_pids[@]}"; do
                                if wait "''${shard_pids[$shard_offset]}"; then
                                    shard_statuses[$shard_offset]=0
                                else
                                    shard_statuses[$shard_offset]=$?
                                    failed=1
                                fi
                            done

                            if [ "$failed" -ne 0 ]; then
                                echo "Parallel hspec run failed; shard logs are under $STATE_DIR" >&2
                                for shard_index in $(seq 1 "$TEST_SHARDS"); do
                                    status="''${shard_statuses[$((shard_index - 1))]:-1}"
                                    if [ "$status" -ne 0 ]; then
                                        echo >&2
                                        echo "===== hspec shard $shard_index/$TEST_SHARDS failed (exit $status) =====" >&2
                                        tail -n 120 "$STATE_DIR/shard-$shard_index.log" >&2 || true
                                    fi
                                done
                                exit 1
                            fi

                            echo "Parallel hspec run completed across $TEST_SHARDS shards"
                            echo "Shard logs: $STATE_DIR"
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
                        # Usage: seed-dev [app|app_test] [--force] [seed-options...]
                        seed-dev.exec = ''
                            set -euo pipefail

                            DB_NAME="app"
                            RESET_MODE=""
                            SCRIPT_ARGS=()
                            DB_SOCKET="''${DEV_FIXTURE_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"

                            while [ "$#" -gt 0 ]; do
                                case "$1" in
                                    app|app_test)
                                        DB_NAME="$1"
                                        shift
                                        ;;
                                    --force)
                                        RESET_MODE="$1"
                                        shift
                                        ;;
                                    *)
                                        SCRIPT_ARGS+=("$1")
                                        shift
                                        ;;
                                esac
                            done

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
                                    echo "Usage: seed-dev [app|app_test] [--force] [seed-options...]" >&2
                                    exit 1
                                    ;;
                            esac

                            if [ -n "$RESET_MODE" ] && [ "$RESET_MODE" != "--force" ]; then
                                echo "Unsupported flag: $RESET_MODE" >&2
                                echo "Usage: seed-dev [app|app_test] [--force] [seed-options...]" >&2
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
                            exec build/Script/SeedDev "''${SCRIPT_ARGS[@]}"
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

                        # Run Playwright end-to-end tests against isolated shard-local DBs + servers.
                        # Usage: e2e [playwright-args...]
                        e2e.exec = ''
                            set -euo pipefail
                            export TEST_DB_SOCKET="''${TEST_DB_SOCKET:-''${PGHOST:-$PWD/build/db}}"
                            export MAILHOG_BASE_URL="''${MAILHOG_BASE_URL:-http://127.0.0.1:8025}"
                            BASE_E2E_DATABASE_NAME="''${TEST_DATABASE_NAME:-app_e2e}"
                            export E2E_RUN_ID="''${E2E_RUN_ID:-$(date +%s)-$$-$RANDOM}"

                            detect_cpu_count() {
                                if command -v getconf >/dev/null 2>&1; then
                                    getconf _NPROCESSORS_ONLN 2>/dev/null && return 0
                                fi
                                if command -v nproc >/dev/null 2>&1; then
                                    nproc && return 0
                                fi
                                printf '1\n'
                            }

                            detect_e2e_shards() {
                                if [ -n "''${E2E_SHARDS:-}" ]; then
                                    printf '%s\n' "$E2E_SHARDS"
                                    return 0
                                fi

                                for arg in "$@"; do
                                    case "$arg" in
                                        --ui|--headed|--debug|--list)
                                            printf '1\n'
                                            return 0
                                            ;;
                                        --project=*|--grep=*|--grep-invert=*|--reporter=*|--workers=*|--shard=*)
                                            printf '1\n'
                                            return 0
                                            ;;
                                        --project|--grep|--grep-invert|--reporter|--workers|--shard)
                                            printf '1\n'
                                            return 0
                                            ;;
                                        -*)
                                            ;;
                                        *)
                                            printf '1\n'
                                            return 0
                                            ;;
                                    esac
                                done

                                local detected_cpu_count
                                detected_cpu_count="$(detect_cpu_count)"
                                if [ "$detected_cpu_count" -gt 2 ]; then
                                    printf '2\n'
                                else
                                    printf '%s\n' "$detected_cpu_count"
                                fi
                            }

                            E2E_SHARDS="$(detect_e2e_shards "$@")"
                            case "$E2E_SHARDS" in
                                ""|*[!0-9]*)
                                    echo "E2E_SHARDS must be a positive integer, got: $E2E_SHARDS" >&2
                                    exit 1
                                    ;;
                            esac
                            if [ "$E2E_SHARDS" -lt 1 ]; then
                                echo "E2E_SHARDS must be at least 1" >&2
                                exit 1
                            fi

                            STATE_ROOT="$PWD/.devenv/e2e"
                            STATE_DIR="$STATE_ROOT/$E2E_RUN_ID"
                            MERGED_BLOB_DIR="$STATE_DIR/blob-report"
                            MERGED_HTML_DIR="$STATE_DIR/playwright-report"
                            mkdir -p "$STATE_DIR" "$MERGED_BLOB_DIR"

                            if ! curl -fsS "$MAILHOG_BASE_URL/api/v2/messages" >/dev/null 2>&1; then
                                MAILHOG_LOG="$STATE_DIR/mailhog.log"
                                ${pkgs.mailhog}/bin/MailHog \
                                    -smtp-bind-addr 127.0.0.1:1025 \
                                    -ui-bind-addr 127.0.0.1:8025 \
                                    -api-bind-addr 127.0.0.1:8025 \
                                    >>"$MAILHOG_LOG" 2>&1 &
                                MAILHOG_PID="$!"
                                MAILHOG_STARTED=1
                            else
                                MAILHOG_STARTED=0
                            fi

                            cleanup_parent() {
                                if [ "''${MAILHOG_STARTED:-0}" = "1" ] && [ -n "''${MAILHOG_PID:-}" ]; then
                                    kill "$MAILHOG_PID" 2>/dev/null || true
                                fi
                            }
                            trap cleanup_parent EXIT

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

                            shard_pids=()
                            shard_statuses=()

                            run_e2e_shard() {
                                local shard_index="$1"
                                shift
                                local shard_dir="$STATE_DIR/shard-$shard_index"
                                local shard_db_name="''${BASE_E2E_DATABASE_NAME}_''${E2E_RUN_ID}_shard_''${shard_index}"
                                local shard_log="$shard_dir/run.log"
                                local shard_blob_dir="$shard_dir/blob-report"
                                local shard_output_dir="$shard_dir/test-results"
                                local shard_pid_file="$shard_dir/server.pid"

                                mkdir -p "$shard_dir"

                                (
                                    export TEST_DATABASE_NAME="$shard_db_name"
                                    export DATABASE_URL="postgresql:///$TEST_DATABASE_NAME?host=$TEST_DB_SOCKET"
                                    export PLAYWRIGHT_OUTPUT_DIR="$shard_output_dir"
                                    export PLAYWRIGHT_BLOB_REPORT_DIR="$shard_blob_dir"
                                    export PLAYWRIGHT_WORKERS=1
                                    export PLAYWRIGHT_FULLY_PARALLEL=0

                                    cleanup() {
                                        if [ -f "$shard_pid_file" ]; then
                                            local pid
                                            pid=$(cat "$shard_pid_file")
                                            kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
                                            rm -f "$shard_pid_file"
                                        fi

                                        if [ "''${TEST_KEEP_DATABASES:-0}" != "1" ]; then
                                            psql -h "$TEST_DB_SOCKET" -d postgres -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DROP DATABASE IF EXISTS "$TEST_DATABASE_NAME" WITH (FORCE);
SQL
                                        fi
                                    }
                                    trap cleanup EXIT INT TERM

                                    test-db-reset

                                    setsid test-e2e-server </dev/null >>"$shard_log" 2>&1 &
                                    local server_pid="$!"
                                    echo "$server_pid" > "$shard_pid_file"

                                    for _ in $(seq 1 120); do
                                        if E2E_BASE_URL=$(detect_e2e_base_url "$server_pid"); then
                                            export E2E_BASE_URL
                                            echo "E2E shard $shard_index/$E2E_SHARDS app server ready at $E2E_BASE_URL"
                                            echo "E2E database: $TEST_DATABASE_NAME"
                                            node ./node_modules/@playwright/test/cli.js test --shard="$shard_index/$E2E_SHARDS" "$@"
                                            exit $?
                                        fi

                                        if ! kill -0 "$server_pid" 2>/dev/null; then
                                            echo "E2E shard $shard_index/$E2E_SHARDS app server failed to start" >&2
                                            tail -n 80 "$shard_log" >&2 || true
                                            exit 1
                                        fi

                                        sleep 1
                                    done

                                    echo "Timed out waiting for E2E shard $shard_index/$E2E_SHARDS app server" >&2
                                    tail -n 80 "$shard_log" >&2 || true
                                    exit 1
                                ) &

                                shard_pids+=("$!")
                            }

                            for shard_index in $(seq 1 "$E2E_SHARDS"); do
                                run_e2e_shard "$shard_index" "$@"
                            done

                            failed=0
                            for shard_offset in "''${!shard_pids[@]}"; do
                                if wait "''${shard_pids[$shard_offset]}"; then
                                    shard_statuses[$shard_offset]=0
                                else
                                    shard_statuses[$shard_offset]=$?
                                    failed=1
                                fi
                            done

                            for shard_index in $(seq 1 "$E2E_SHARDS"); do
                                if [ -d "$STATE_DIR/shard-$shard_index/blob-report" ]; then
                                    cp "$STATE_DIR/shard-$shard_index"/blob-report/* "$MERGED_BLOB_DIR"/ 2>/dev/null || true
                                fi
                            done

                            if [ -n "$(find "$MERGED_BLOB_DIR" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)" ]; then
                                node ./node_modules/@playwright/test/cli.js merge-reports \
                                    --reporter html \
                                    --config playwright.config.ts \
                                    "$MERGED_BLOB_DIR" >/dev/null
                                rm -rf "$MERGED_HTML_DIR"
                                if [ -d "$PWD/playwright-report" ]; then
                                    mv "$PWD/playwright-report" "$MERGED_HTML_DIR"
                                fi
                                ln -sfn "$MERGED_HTML_DIR" "$STATE_ROOT/latest-report"
                            fi

                            if [ "$failed" -ne 0 ]; then
                                echo "Parallel Playwright run failed; shard logs are under $STATE_DIR" >&2
                                for shard_index in $(seq 1 "$E2E_SHARDS"); do
                                    status="''${shard_statuses[$((shard_index - 1))]:-1}"
                                    if [ "$status" -ne 0 ]; then
                                        echo >&2
                                        echo "===== e2e shard $shard_index/$E2E_SHARDS failed (exit $status) =====" >&2
                                        tail -n 120 "$STATE_DIR/shard-$shard_index/run.log" >&2 || true
                                    fi
                                done
                                exit 1
                            fi

                            echo "Parallel Playwright run completed across $E2E_SHARDS shards"
                            echo "E2E artifacts: $STATE_DIR"
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
                        # Run `seed-dev app` first so the dev-role accounts exist.
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
                        # Defaults target the `seed-dev app` dev-manager credentials.
                        # Usage: screenshot-page <path-or-url> <output.png> [--selector <css>] [--email <email>] [--password <password>] [--no-login]
                        screenshot-page.exec = ''
                            exec node ./e2e/screenshot-page.mjs "$@"
                        '';

                        # Capture a deterministic set of authenticated roster screenshots against the running dev app.
                        # Run `seed-dev app` first when you want the standard dev manager dataset.
                        # Usage: screenshot-roster-mobile [output-dir] [path]
                        screenshot-roster-mobile.exec = ''
                            set -euo pipefail

                            OUT_DIR="''${1:-output/playwright/roster-mobile/latest}"
                            TARGET_PATH="''${2:-/RosterWeeks}"
                            mkdir -p "$OUT_DIR"

                            capture_device() {
                                local slug="$1"
                                local device="$2"

                                screenshot-page "$TARGET_PATH" "$OUT_DIR/$slug-full.png" \
                                    --device "$device" \
                                    --selector '#roster-week-shell' \
                                    --navigation-timeout-ms 120000 \
                                    --selector-timeout-ms 120000

                                screenshot-page "$TARGET_PATH" "$OUT_DIR/$slug-shell.png" \
                                    --device "$device" \
                                    --selector '#roster-week-shell' \
                                    --clip-selector '#roster-week-shell' \
                                    --navigation-timeout-ms 120000 \
                                    --selector-timeout-ms 120000

                                screenshot-page "$TARGET_PATH" "$OUT_DIR/$slug-table.png" \
                                    --device "$device" \
                                    --selector 'table.roster-grid' \
                                    --clip-selector '.table-responsive' \
                                    --navigation-timeout-ms 120000 \
                                    --selector-timeout-ms 120000
                            }

                            capture_device pixel-7 "Pixel 7"
                            capture_device iphone-13 "iPhone 13"
                            capture_device ipad-mini "iPad Mini"

                            screenshot-page "$TARGET_PATH" "$OUT_DIR/galaxy-s9-plus-full.png" \
                                --viewport 360x740 \
                                --selector '#roster-week-shell' \
                                --navigation-timeout-ms 120000 \
                                --selector-timeout-ms 120000

                            screenshot-page "$TARGET_PATH" "$OUT_DIR/galaxy-s9-plus-shell.png" \
                                --viewport 360x740 \
                                --selector '#roster-week-shell' \
                                --clip-selector '#roster-week-shell' \
                                --navigation-timeout-ms 120000 \
                                --selector-timeout-ms 120000

                            echo "Roster mobile screenshots saved under $OUT_DIR"
                        '';

                        # Run the roster mobile visual diagnostic suite and attach screenshots/metrics to the report.
                        # Usage: e2e-roster-mobile-screenshots [extra playwright args...]
                        e2e-roster-mobile-screenshots.exec = ''
                            export E2E_INCLUDE_SCREENSHOTS=1
                            exec e2e \
                                --project=mobile-chromium \
                                --project=galaxy-s9-plus \
                                --project=tablet-chromium \
                                e2e/roster-mobile-screenshots.spec.ts \
                                "$@"
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
                            POSTGRES_PID_FILE="$STATE_DIR/postgres.pid"
                            LOG_FILE="$STATE_DIR/devenv.log"
                            DB_SOCKET="''${PGHOST:-$PWD/build/db}"

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
                            if ! psql -h "$DB_SOCKET" -d postgres -c "select 1" >/dev/null 2>&1; then
                                if [ -f "$POSTGRES_PID_FILE" ]; then
                                    PG_PID=$(cat "$POSTGRES_PID_FILE")
                                    if ! kill -0 "$PG_PID" 2>/dev/null; then
                                        rm -f "$POSTGRES_PID_FILE"
                                    fi
                                fi

                                if [ ! -f "$POSTGRES_PID_FILE" ]; then
                                    echo "[dev-start] launching start-postgres (socket=$DB_SOCKET)" >>"$LOG_FILE"
                                    setsid nohup start-postgres </dev/null >>"$LOG_FILE" 2>&1 &
                                    PG_PID=$!
                                    echo "$PG_PID" > "$POSTGRES_PID_FILE"
                                    disown "$PG_PID" 2>/dev/null || true
                                fi
                            fi

                            for _ in $(seq 1 20); do
                                if psql -h "$DB_SOCKET" -d postgres -c "select 1" >/dev/null 2>&1; then
                                    break
                                fi
                                sleep 1
                            done

                            if ! psql -h "$DB_SOCKET" -d postgres -c "select 1" >/dev/null 2>&1; then
                                echo "devenv postgres failed to start; recent log output:"
                                tail -n 60 "$LOG_FILE" || true
                                exit 1
                            fi

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
                            POSTGRES_PID_FILE="$STATE_DIR/postgres.pid"

                            stop_tracked_process() {
                                local pid_file="$1"
                                local label="$2"

                                if [ ! -f "$pid_file" ]; then
                                    return 0
                                fi

                                local tracked_pid
                                tracked_pid=$(cat "$pid_file")

                                if ! kill -0 "$tracked_pid" 2>/dev/null; then
                                    rm -f "$pid_file"
                                    return 0
                                fi

                                kill -TERM -"$tracked_pid" 2>/dev/null || kill -TERM "$tracked_pid" 2>/dev/null || true

                                for _ in $(seq 1 20); do
                                    if ! kill -0 "$tracked_pid" 2>/dev/null; then
                                        rm -f "$pid_file"
                                        return 0
                                    fi
                                    sleep 1
                                done

                                kill -KILL -"$tracked_pid" 2>/dev/null || kill -KILL "$tracked_pid" 2>/dev/null || true
                                rm -f "$pid_file"
                            }

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

                            stop_tracked_process "$PID_FILE" "devenv"
                            stop_tracked_process "$POSTGRES_PID_FILE" "postgres"
                            echo "devenv stopped"
                        '';

                        # Check health of background devenv server.
                        # Usage: dev-status
                        dev-status.exec = ''
                            set -euo pipefail
                            STATE_DIR="$(dev-agent-state-dir)"
                            PID_FILE="$STATE_DIR/devenv.pid"
                            SOCKET_FILE="$STATE_DIR/pc.sock"
                            DB_SOCKET="''${PGHOST:-$PWD/build/db}"
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
                            if DB_ERR=$(psql -h "$DB_SOCKET" -d app -c "select 1" 2>&1); then
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
