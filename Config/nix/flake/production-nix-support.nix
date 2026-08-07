{ ihp, lib }:

let
    source = builtins.readFile "${ihp}/NixSupport/default.nix";
    packageInventoryComment =
        "# Get all registered package names from the GHC environment\n            # This includes ihp and ALL its transitive deps (aeson, bytestring, lens, etc.)\n            # Filter out internal sub-libraries (z-* prefixed names) as they are private";
    productionPackageInventoryComment =
        "# Load only reviewed packages required by reachable production imports\n            # and validate every module-to-package mapping against the production GHC environment.";
    packageInventoryCommand =
        "ALL_PKG_NAMES=$(ghc-pkg list --simple-output | tr ' ' '\\n' | sed 's/-[0-9].*//' | sort -u | grep -v '^$' | grep -v '^z-')";
    productionPackageInventoryCommand = ''
        DEPENDENCY_INVENTORY="''${projectPath}/Config/nix/production-package-dependency-inventory.tsv"
        if [ ! -r "$DEPENDENCY_INVENTORY" ]; then
            echo "app-lib dependency inventory is unreadable: $DEPENDENCY_INVENTORY" >&2
            exit 1
        fi
        EXPECTED_HEADER="$(printf 'module\tpackage\treason')"
        if [ "$(head -n 1 "$DEPENDENCY_INVENTORY")" != "$EXPECTED_HEADER" ]; then
            echo "app-lib dependency inventory has an invalid header: $DEPENDENCY_INVENTORY" >&2
            exit 1
        fi
        ALL_PKG_NAMES=$(tail -n +2 "$DEPENDENCY_INVENTORY" | cut -f 2 | LC_ALL=C sort -u)
        if [ -z "$ALL_PKG_NAMES" ]; then
            echo "app-lib dependency inventory contains no packages: $DEPENDENCY_INVENTORY" >&2
            exit 1
        fi
        while IFS="$(printf '\t')" read -r imported_module declared_package reason; do
            [ "$imported_module" = "module" ] && continue
            package_ids="$(ghc-pkg find-module "$imported_module" --simple-output)"
            if [ -z "$package_ids" ]; then
                echo "app-lib dependency inventory: module $imported_module is not exposed by the production package set (declared package $declared_package)" >&2
                exit 1
            fi
            matched=false
            available_packages=""
            for package_id in $package_ids; do
                candidate="$(ghc-pkg field "$package_id" name --simple-output)"
                available_packages="$available_packages $candidate"
                if [ "$candidate" = "$declared_package" ]; then
                    matched=true
                fi
            done
            if [ "$matched" != true ]; then
                echo "app-lib dependency inventory: module $imported_module maps to $declared_package but production exposes:$available_packages" >&2
                exit 1
            fi
        done < "$DEPENDENCY_INVENTORY"
    '';
    registeredPackagesComment = "# Add all registered packages as build-depends";
    reviewedPackagesComment = "# Add reviewed production packages as build-depends";
    sharedAppLibraryStart =
        "    appLibPackage = pkgs.haskell.lib.disableLibraryProfiling (pkgs.haskell.lib.dontHaddock (";
    staticOnlyAppLibraryStart =
        "    # Production executables are non-dynamic, so retain the vanilla static\n"
        + "    # library and interfaces without producing an unused shared app library.\n"
        + "    appLibPackage = pkgs.haskell.lib.disableSharedLibraries (pkgs.haskell.lib.disableLibraryProfiling (pkgs.haskell.lib.dontHaddock (";
    sharedAppLibraryEnd = "        }) {}\n    ));\n\n    allHaskellPackagesWithAppLib";
    staticOnlyAppLibraryEnd = "        }) {}\n    )));\n\n    allHaskellPackagesWithAppLib";
    executableGhcOptions = "                    $(make print-ghc-options)";
    # Production executables consume static app-lib object interfaces. Remove
    # IHP's development byte-code mode and isolate any Template Haskell loading
    # in the external interpreter instead of requesting app-lib's dynamic way.
    staticExecutableGhcOptions = "                    $(make print-ghc-options | sed 's/-fbyte-code//g') -fexternal-interpreter";
    commandReplacements = builtins.length (lib.splitString packageInventoryCommand source) - 1;
    commentReplacements = builtins.length (lib.splitString packageInventoryComment source) - 1;
    loopCommentReplacements = builtins.length (lib.splitString registeredPackagesComment source) - 1;
    sharedStartReplacements = builtins.length (lib.splitString sharedAppLibraryStart source) - 1;
    sharedEndReplacements = builtins.length (lib.splitString sharedAppLibraryEnd source) - 1;
    executableOptionReplacements = builtins.length (lib.splitString executableGhcOptions source) - 1;
in
if commandReplacements != 1 || commentReplacements != 1 || loopCommentReplacements != 1
    || sharedStartReplacements != 1 || sharedEndReplacements != 1 || executableOptionReplacements != 3
then throw "IHP NixSupport production seam changed; expected exact dependency, shared-library, and three executable option markers"
else builtins.toFile "ihp-production-nix-support.nix" (
    builtins.replaceStrings
        [
            packageInventoryComment
            packageInventoryCommand
            registeredPackagesComment
            sharedAppLibraryStart
            sharedAppLibraryEnd
            executableGhcOptions
        ]
        [
            productionPackageInventoryComment
            productionPackageInventoryCommand
            reviewedPackagesComment
            staticOnlyAppLibraryStart
            staticOnlyAppLibraryEnd
            staticExecutableGhcOptions
        ]
        source
)
