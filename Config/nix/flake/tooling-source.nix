{ root ? ../../.. }:
let
    packageSource = relative: name:
        let
            packageRoot = root + "/${relative}";
            rootText = toString packageRoot;
            hasPrefix = prefix: value:
                builtins.substring 0 (builtins.stringLength prefix) value == prefix;
        in
        builtins.path {
            path = packageRoot;
            inherit name;
            filter = path: _type:
                let
                    pathText = toString path;
                    relativePath = if pathText == rootText then "" else builtins.substring (builtins.stringLength rootText + 1) (builtins.stringLength pathText) pathText;
                in
                relativePath != "test"
                && !hasPrefix "test/" relativePath
                && relativePath != "README.md";
        };
in
{
    core = packageSource "tooling/core" "bepis-tooling-core-source";
    workspaceState = packageSource "tooling/workspace-state" "bepis-workspace-state-source";
    runtime = packageSource "tooling/runtime" "bepis-runtime-source";
    epicLifecycle = packageSource "tooling/epic-lifecycle" "bepis-epic-lifecycle-source";
    artifacts = packageSource "tooling/artifacts" "bepis-artifacts-source";
    runners = packageSource "tooling/runners" "bepis-runners-source";
    postgres = packageSource "tooling/postgres" "bepis-postgres-source";
}
