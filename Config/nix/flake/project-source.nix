{ pkgs, root ? ../../.. }:

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
        in
            !(pkgs.lib.any isUnderExcludedRoot excludedRoots);
}
