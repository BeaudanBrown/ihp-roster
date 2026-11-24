{ pkgs }:
let
    projectCommandRunner = pkgs.writeShellScript "bepis-project-command" ''
        set -euo pipefail

        relative_path="$1"
        shift

        repo_root="''${FRONTEND_REPO_ROOT:-}"
        repo_root_is_explicit=false
        if [ -n "$repo_root" ]; then
            repo_root_is_explicit=true
        else
            repo_root="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
        fi

        project_marker="$repo_root/Config/nix/flake/scripts.nix"
        if [ -n "$repo_root" ] && { [ "$repo_root_is_explicit" = true ] || [ -f "$project_marker" ]; }; then
            if [[ "$repo_root" == *$'\n'* || "$repo_root" == *$'\r'* ]]; then
                echo "devenv project command: checkout paths containing newlines are unsupported" >&2
                exit 64
            fi
            scripts_root="$repo_root/Config/nix/scripts"
            selected_script="$scripts_root/$relative_path"
            if [ ! -f "$selected_script" ]; then
                echo "devenv project command: missing working-tree script $selected_script" >&2
                exit 66
            fi
        else
            scripts_root=${../scripts}
            selected_script="$scripts_root/$relative_path"
            echo "devenv project command: no project checkout found; using packaged snapshot for $relative_path" >&2
        fi

        # Preserve compiler discovery while nested runtime/test commands change PATH.
        export BEPIS_TOOLING_BUILD_PATH="''${BEPIS_TOOLING_BUILD_PATH:-$PATH}"
        export BEPIS_SCRIPTS_ROOT="$scripts_root"
        export BEPIS_MAILHOG_ROOT=${pkgs.mailhog}
        export BEPIS_RIPGREP_ROOT=${pkgs.ripgrep}
        exec ${pkgs.bash}/bin/bash "$selected_script" "$@"
    '';

    script = path:
        let
            relativePath = pkgs.lib.removePrefix "${toString ../scripts}/" (toString path);
        in
        {
            exec = ''
                exec ${projectCommandRunner} ${pkgs.lib.escapeShellArg relativePath} "$@"
            '';
        };
in
{
    processes = {
        # Replace IHP's static devenv processes so `devenv up` receives the
        # same workspace-specific ports as dev-start and dev-foreground.
        web = pkgs.lib.mkForce (script ../scripts/dev/web);
        worker = pkgs.lib.mkForce (script ../scripts/dev/worker);
        hoogle = pkgs.lib.mkForce {
            exec = ''
                repo_root="$(git rev-parse --show-toplevel)"
                . "$repo_root/Config/nix/scripts/lib/workspace.sh"
                bepis_workspace_start
                exec hoogle server --local -p "$IHP_HOOGLE_PORT" --no-security-headers
            '';
        };
        mailhog = script ../scripts/dev/mailhog;
    };

    scripts = {
        pi = script ../scripts/dev/pi;
        workspace-pi-test = script ../scripts/dev/pi-test;
        dev-agent-state-dir = script ../scripts/dev/agent-state-dir;
        dev-worker = script ../scripts/dev/worker;
        dev-workspace-info = script ../scripts/dev/workspace-info;
        dev-workspace-test = script ../scripts/dev/workspace-test;
        in-env-test = script ../scripts/dev/in-env-test;
        dev-runtime-isolation-test = script ../scripts/dev/runtime-isolation-test;
        runtime-lifecycle-test = script ../scripts/dev/runtime-lifecycle-test;
        devenv-script-freshness-check = script ../scripts/dev/script-freshness-check;
        dev-ensure-postgres = script ../scripts/dev/ensure-postgres;
        dev-ensure-mailhog = script ../scripts/dev/ensure-mailhog;
        dev-foreground = script ../scripts/dev/foreground;
        dev-foreground-stripe-tunnel = script ../scripts/dev/foreground-stripe-tunnel;
        dev-observability-start = script ../scripts/dev/observability-start;
        dev-observability-stop = script ../scripts/dev/observability-stop;
        dev-observability-status = script ../scripts/dev/observability-status;
        dev-start-otel = script ../scripts/dev/start-otel;
        frontend-build = script ../scripts/frontend/build;
        frontend-check = script ../scripts/frontend/check;
        frontend-contracts = script ../scripts/frontend/contracts;
        frontend-contracts-check = script ../scripts/frontend/contracts-check;
        frontend-generated-ensure = script ../scripts/frontend/generated-ensure;
        frontend-generated-state-test = script ../scripts/frontend/generated-state-test;
        frontend-generated-sync = script ../scripts/frontend/generated-sync;
        frontend-generated-watch = script ../scripts/frontend/generated-watch;
        frontend-drift-check = script ../scripts/frontend/drift-check;
        frontend-no-ts-nocheck = script ../scripts/frontend/no-ts-nocheck;
        frontend-surface-guardrails = script ../scripts/frontend/surface-guardrails;
        frontend-surface-compile-fail-check = script ../scripts/frontend/surface-compile-fail-check;
        frontend-surface-adapters = script ../scripts/frontend/surface-adapters;
        frontend-surface-adapters-check = script ../scripts/frontend/surface-adapters-check;
        frontend-test = script ../scripts/frontend/test;
        frontend-watch = script ../scripts/frontend/watch;
        git-pre-commit-check = script ../scripts/git/pre-commit-check;
        epic-worktree = script ../scripts/epic/worktree;
        epic-worktree-test = script ../scripts/epic/worktree-test;
        epic-worktree-orientation-test = script ../scripts/epic/orientation-test;
        epic-worktree-manage = script ../scripts/epic/manage;
        epic-worktree-manage-test = script ../scripts/epic/manage-test;
        epic-worktree-concurrency-test = script ../scripts/epic/concurrency-test;
        epic-worktree-workflow-acceptance-test = script ../scripts/epic/workflow-acceptance-test;
        epic-worktree-provision = script ../scripts/epic/provision;
        epic-worktree-provision-test = script ../scripts/epic/provision-test;
        email-transport-check = script ../scripts/verification/email-transport-check;
        fixture-reset-manifest-test = script ../scripts/verification/fixture-reset-manifest-test;
        haskell-module-name-check = script ../scripts/haskell/module-name-check;
        typecheck = script ../scripts/haskell/typecheck;
        enum-authority-check = script ../scripts/haskell/enum-authority-check;
        typed-contract-authority-check = script ../scripts/haskell/typed-contract-authority-check;
        frontend-contract-warnings = script ../scripts/haskell/frontend-contract-warnings;
        application-warnings = script ../scripts/haskell/application-warnings;
        typed-error-boundary-check = script ../scripts/haskell/typed-error-boundary-check;
        weeder-check = script ../scripts/haskell/weeder-check;
        weeder-policy-test = script ../scripts/haskell/weeder-policy-test;
        regen-types = script ../scripts/haskell/regen-types;
        haskell-generated-ensure = script ../scripts/haskell/generated-ensure;
        haskell-generated-ensure-test = script ../scripts/haskell/generated-ensure-test;
        generated-code-sync = script ../scripts/haskell/generated-code-sync;
        hie-bios-test = script ../scripts/haskell/hie-bios-test;
        hls-lsp = script ../scripts/haskell/hls-lsp;
        hls-cache = script ../scripts/haskell/hls-cache;
        hls-cache-test = script ../scripts/haskell/hls-cache-test;
        compiler-tmp-test = script ../scripts/haskell/compiler-tmp-test;
        test-db-reset = script ../scripts/db/test-db-reset;
        test-postgres = script ../scripts/db/test-postgres;
        migration-enum-commit-boundary-check = script ../scripts/db/migration-enum-commit-boundary-check;
        migration-enum-commit-boundary-real-runner-test = script ../scripts/db/migration-enum-commit-boundary-real-runner-test;
        migration-rehearsal = script ../scripts/db/migration-rehearsal;
        migration-rehearsal-test = script ../scripts/db/migration-rehearsal-test;
        hspec-test = script ../scripts/haskell/hspec-test;
        hspec-pure = script ../scripts/haskell/hspec-pure;
        hspec-db = script ../scripts/haskell/hspec-db;
        hspec-coverage = script ../scripts/haskell/hspec-coverage;
        verify-fast = script ../scripts/verification/fast;
        verify-full = script ../scripts/verification/full;
        tooling-foundation-test = script ../scripts/verification/tooling-foundation-test;
        runner-lifecycle-test = script ../scripts/verification/runner-lifecycle-test;
        verify-tooling = script ../scripts/verification/verify-tooling;
        date-native-roster-readiness-test = script ../scripts/verification/date-native-roster-readiness-test;
        billing-production-readiness = script ../scripts/verification/billing-production-readiness;
        billing-contract-check = script ../scripts/verification/billing-contract-check;
        deployment-module-check = script ../scripts/verification/deployment-module-check;
        ihp-compatibility-check = script ../scripts/verification/ihp-compatibility-check;
        observability-production-check = script ../scripts/verification/observability-production-check;
        observability-backend-smoke = script ../scripts/verification/observability-backend-smoke;
        otel-recent = script ../scripts/observability/recent;
        otel-trace = script ../scripts/observability/trace;
        otel-logs = script ../scripts/observability/logs;
        otel-compare = script ../scripts/observability/compare;
        http-polling-policy-check = script ../scripts/verification/http-polling-policy;
        http-polling-policy-test = script ../scripts/verification/http-polling-policy-test;
        http-repository-check = script ../scripts/verification/http-repository-check;
        production-manifest-check = script ../scripts/verification/production-manifest-check;
        production-inventory-check = script ../scripts/verification/production-inventory;
        production-source-repository-check = script ../scripts/verification/production-source-repository-check;
        production-source-boundary-check = script ../scripts/verification/production-source-boundary;
        production-package-smoke = script ../scripts/verification/production-package-smoke;
        glue-compatibility-test = script ../scripts/verification/glue-compatibility-test;
        tooling-hls-test = script ../scripts/verification/tooling-hls-test;
        frontend-runtime-check = script ../scripts/verification/frontend-runtime-check;
        repository-wiring-check = script ../scripts/verification/repository-wiring-check;
        frontend-request-closure-check = script ../scripts/verification/frontend-request-closure-check;
        documentation-repository-check = script ../scripts/verification/documentation-repository-check;
        frontend-contract-package-check = script ../scripts/verification/frontend-contract-package;
        lint = script ../scripts/haskell/lint;
        format = script ../scripts/haskell/format;
        ghci-app = script ../scripts/haskell/ghci-app;
        ghci-config-test = script ../scripts/haskell/ghci-config-test;
        dev-db-reset = script ../scripts/db/reset-dev;
        dev-db-maintenance-test = script ../scripts/db/dev-maintenance-test;
        postgres-lifecycle-test = script ../scripts/db/postgres-lifecycle-test;
        seed-dev = script ../scripts/db/seed-dev;
        seed-profile = script ../scripts/db/seed-profile;
        profile-test-server = script ../scripts/profile/test-server;
        profile-app = script ../scripts/profile/app;
        otel-browser = script ../scripts/profile/otel-browser;
        otel-summary = script ../scripts/profile/otel-summary;
        telemetry-boundary-probe = script ../scripts/profile/telemetry-boundary-probe;
        profile-compare = script ../scripts/profile/compare;
        production-build-profile = script ../scripts/profile/production-build;
        production-build-profile-test = script ../scripts/profile/production-build-test;
        profile-load = script ../scripts/profile/load;
        profile-load-suite = script ../scripts/profile/load-suite;
        profile-live-load = script ../scripts/profile/live-load;
        sync-fwc-mapd = script ../scripts/xero/sync-fwc-mapd;
        xero-pay-item-probe = script ../scripts/xero/pay-item-probe;
        test-e2e-server = script ../scripts/e2e/test-server;
        e2e-postgres = script ../scripts/db/e2e-postgres;
        e2e-postgres-lifecycle-test = script ../scripts/e2e/postgres-lifecycle-test;
        dev-postgres = script ../scripts/db/dev-postgres;
        e2e-runtime = script ../scripts/e2e/runtime;
        e2e.exec = ''
            export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }}
            ${(script ../scripts/e2e/e2e).exec}
        '';
        e2e-fast = script ../scripts/e2e/e2e-fast;
        e2e-support-import-check = script ../scripts/e2e/support-import-check;
        e2e-typecheck = script ../scripts/e2e/typecheck;
        e2e-typecheck-test = script ../scripts/e2e/typecheck-test;
        pwcli = script ../scripts/e2e/pwcli;
        pwcli-auth-save = script ../scripts/e2e/pwcli-auth-save;
        pwcli-auth-open = script ../scripts/e2e/pwcli-auth-open;
        screenshot-page = script ../scripts/e2e/screenshot-page;
        e2e-report = script ../scripts/e2e/report;
        dev-start = script ../scripts/dev/start;
        stripe-listen = script ../scripts/dev/stripe-listen;
        stripe-sandbox-contract-parity = script ../scripts/stripe/sandbox-contract-parity;
        dev-start-stripe = script ../scripts/dev/start-stripe;
        dev-stop = script ../scripts/dev/stop;
        dev-status = script ../scripts/dev/status;
        dev-wait = script ../scripts/dev/wait;
    };
}
