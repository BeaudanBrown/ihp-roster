{ pkgs }:
let
    scriptBody = path:
        builtins.replaceStrings
            [
                "@mailhog@"
                "@ripgrep@"
                "@scriptsRoot@"
            ]
            [
                "${pkgs.mailhog}"
                "${pkgs.ripgrep}"
                "${../scripts}"
            ]
            (builtins.readFile path);

    script = path: {
        exec = scriptBody path;
    };
in
{
    processes = {
        mailhog = script ../scripts/dev/mailhog;
    };

    scripts = {
        dev-agent-state-dir = script ../scripts/dev/agent-state-dir;
        dev-ensure-postgres = script ../scripts/dev/ensure-postgres;
        dev-ensure-mailhog = script ../scripts/dev/ensure-mailhog;
        dev-foreground = script ../scripts/dev/foreground;
        frontend-build = script ../scripts/frontend/build;
        frontend-check = script ../scripts/frontend/check;
        frontend-contracts = script ../scripts/frontend/contracts;
        frontend-contracts-check = script ../scripts/frontend/contracts-check;
        frontend-drift-check = script ../scripts/frontend/drift-check;
        frontend-no-ts-nocheck = script ../scripts/frontend/no-ts-nocheck;
        frontend-test = script ../scripts/frontend/test;
        frontend-watch = script ../scripts/frontend/watch;
        git-install-hooks = script ../scripts/git/install-hooks;
        haskell-module-name-check = script ../scripts/haskell/module-name-check;
        typecheck = script ../scripts/haskell/typecheck;
        regen-types = script ../scripts/haskell/regen-types;
        test-db-reset = script ../scripts/db/test-db-reset;
        hspec-test = script ../scripts/haskell/hspec-test;
        hspec-coverage = script ../scripts/haskell/hspec-coverage;
        lint = script ../scripts/haskell/lint;
        format = script ../scripts/haskell/format;
        ghci-app = script ../scripts/haskell/ghci-app;
        seed-dev = script ../scripts/db/seed-dev;
        seed-profile = script ../scripts/db/seed-profile;
        profile-test-server = script ../scripts/profile/test-server;
        profile-app = script ../scripts/profile/app;
        profile-compare = script ../scripts/profile/compare;
        profile-load = script ../scripts/profile/load;
        profile-load-suite = script ../scripts/profile/load-suite;
        profile-live-invalidation = script ../scripts/profile/live-invalidation;
        profile-live-load = script ../scripts/profile/live-load;
        sync-fwc-mapd = script ../scripts/xero/sync-fwc-mapd;
        xero-pay-item-probe = script ../scripts/xero/pay-item-probe;
        test-e2e-server = script ../scripts/e2e/test-server;
        e2e = script ../scripts/e2e/e2e;
        screenshot = script ../scripts/e2e/screenshot;
        pwcli = script ../scripts/e2e/pwcli;
        pwcli-auth-save = script ../scripts/e2e/pwcli-auth-save;
        pwcli-auth-open = script ../scripts/e2e/pwcli-auth-open;
        screenshot-page = script ../scripts/e2e/screenshot-page;
        screenshot-roster-mobile = script ../scripts/e2e/screenshot-roster-mobile;
        e2e-roster-mobile-screenshots = script ../scripts/e2e/roster-mobile-screenshots;
        e2e-report = script ../scripts/e2e/report;
        dev-start = script ../scripts/dev/start;
        stripe-listen = script ../scripts/dev/stripe-listen;
        dev-start-stripe = script ../scripts/dev/start-stripe;
        dev-stop = script ../scripts/dev/stop;
        dev-status = script ../scripts/dev/status;
        dev-wait = script ../scripts/dev/wait;
    };
}
