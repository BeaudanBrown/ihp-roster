{ pkgs, root ? ../../.. }:

let
    inventoryLines =
        pkgs.lib.filter (line: line != "")
            (pkgs.lib.splitString "\n" (builtins.readFile ../frontend-contract-tool-module-inventory.tsv));
    inventoryRows = map (line: pkgs.lib.splitString "\t" line) (builtins.tail inventoryLines);
    toolHaskellPaths = map builtins.head inventoryRows;
    toolHaskellPathSet = pkgs.lib.genAttrs toolHaskellPaths (_: true);
    supportFiles = pkgs.lib.genAttrs [
        "Application/Schema.sql"
        "Makefile"
    ] (_: true);
in
builtins.path {
    path = root;
    name = "ihp-roster-frontend-contract-tool-source";
    filter = path: type:
        let
            rootString = toString root;
            pathString = toString path;
            relativePath =
                if pathString == rootString
                then ""
                else pkgs.lib.removePrefix "${rootString}/" pathString;
        in
            type == "directory"
            || builtins.hasAttr relativePath toolHaskellPathSet
            || builtins.hasAttr relativePath supportFiles;
}
