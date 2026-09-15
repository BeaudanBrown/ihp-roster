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
    postgres = builtins.path {
        path = root + /tooling/postgres;
        name = "bepis-postgres-source";
    };
}
