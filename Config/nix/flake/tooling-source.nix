{ root ? ../../.. }:
{
    core = builtins.path {
        path = root + /tooling/core;
        name = "bepis-tooling-core-source";
    };
    workspaceState = builtins.path {
        path = root + /tooling/workspace-state;
        name = "bepis-workspace-state-source";
    };
    runtime = builtins.path {
        path = root + /tooling/runtime;
        name = "bepis-runtime-source";
    };
    epicLifecycle = builtins.path {
        path = root + /tooling/epic-lifecycle;
        name = "bepis-epic-lifecycle-source";
    };
    postgres = builtins.path {
        path = root + /tooling/postgres;
        name = "bepis-postgres-source";
    };
}
