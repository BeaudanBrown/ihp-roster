{ ihp, lib }:

let
    source = builtins.readFile "${ihp}/NixSupport/default.nix";
    packageInventoryCommand =
        "ALL_PKG_NAMES=$(ghc-pkg list --simple-output | tr ' ' '\\n' | sed 's/-[0-9].*//' | sort -u | grep -v '^$' | grep -v '^z-')";
    productionPackageInventoryCommand =
        "ALL_PKG_NAMES=$(ghc-pkg list --simple-output | tr ' ' '\\n' | sed 's/-[0-9].*//' | sort -u | grep -v '^$' | grep -v '^z-' | grep -Ev '^(QuickCheck($|-.*)|quickcheck-.*|hspec($|-.*)|ihp-hspec($|-.*))$')";
    replacements = builtins.length (lib.splitString packageInventoryCommand source) - 1;
in
if replacements != 1
then throw "IHP NixSupport production package inventory seam changed; expected exactly one generated Cabal package command"
else builtins.toFile "ihp-production-nix-support.nix" (
    builtins.replaceStrings [ packageInventoryCommand ] [ productionPackageInventoryCommand ] source
)
