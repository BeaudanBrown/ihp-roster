{ pkgs, root ? ../../.. }:

let
    inventoryLines =
        pkgs.lib.filter (line: line != "")
            (pkgs.lib.splitString "\n" (builtins.readFile ../production-module-inventory.tsv));
    inventoryRows = map (line: pkgs.lib.splitString "\t" line) (builtins.tail inventoryLines);
    productionHaskellPaths =
        map builtins.head
            (builtins.filter (row: builtins.elemAt row 1 == "production") inventoryRows);
    productionHaskellPathSet = pkgs.lib.genAttrs productionHaskellPaths (_: true);
    retainedTrees = [
        # Deployed database history and one-off cutover SQL are runtime inputs.
        "Application/Deployment"
        "Application/Migration"
        # Checked-in browser output is the production static authority.
        "static"
        # Deployment evaluation owns these modules outside the app package too;
        # retaining them here keeps the production source self-describing.
        "Config/nix/hosts"
        "Config/nix/modules"
    ];
    retainedFiles = [
        "Application/Schema.sql"
        # IHP model/app packaging reads these during production builds.
        "Config/nix/production-package-dependency-inventory.tsv"
        "Makefile"
    ];
in
builtins.path {
    path = root;
    name = "ihp-roster-source";
    filter =
        path: type:
        let
            rootString = toString root;
            pathString = toString path;
            relativePath =
                if pathString == rootString
                then ""
                else pkgs.lib.removePrefix "${rootString}/" pathString;
            isPathOrDescendantOf = parent:
                relativePath == parent || pkgs.lib.hasPrefix "${parent}/" relativePath;
            isDirectoryLeadingTo = retainedPath:
                relativePath == ""
                || relativePath == retainedPath
                || pkgs.lib.hasPrefix "${relativePath}/" retainedPath;
            isInRetainedTree = pkgs.lib.any isPathOrDescendantOf retainedTrees;
            leadsToRetainedTree = pkgs.lib.any isDirectoryLeadingTo retainedTrees;
            isRetainedFile = builtins.elem relativePath retainedFiles;
            leadsToRetainedFile = pkgs.lib.any isDirectoryLeadingTo retainedFiles;
            isInventoriedProductionHaskell = builtins.hasAttr relativePath productionHaskellPathSet;
            leadsToProductionHaskell = pkgs.lib.any isDirectoryLeadingTo productionHaskellPaths;
        in
            if type == "directory"
            then isInRetainedTree || leadsToRetainedTree || leadsToRetainedFile || leadsToProductionHaskell
            else isInRetainedTree || isRetainedFile || isInventoriedProductionHaskell;
}
