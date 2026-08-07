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
            excludedRoots = [
                "IHP"
                "build"
                ".devenv"
                ".direnv"
                ".claude"
                "notes"
                "output"
            ];
            isUnderExcludedRoot = excludedRoot:
                relativePath == excludedRoot || pkgs.lib.hasPrefix "${excludedRoot}/" relativePath;
            isHaskellSource = pkgs.lib.hasSuffix ".hs" relativePath;
            isInventoriedProductionHaskell = builtins.hasAttr relativePath productionHaskellPathSet;
        in
            !(pkgs.lib.any isUnderExcludedRoot excludedRoots)
            && (!isHaskellSource || isInventoriedProductionHaskell);
}
