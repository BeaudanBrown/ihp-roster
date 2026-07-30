{ root }:
let
  rootPath = toString root;
  ignoredTopLevelEntries = [
    ".DS_Store"
    ".bepis-epic-worktree.json"
    ".codex"
    ".devenv"
    ".direnv"
    ".env"
    ".ghci"
    ".idea"
    ".loom"
    ".pi"
    ".playwright-cli"
    "IHP"
    "build"
    "del"
    "devenv.local.nix"
    "dist"
    "dist-newstyle"
    "gen"
    "node_modules"
    "notes"
    "output"
    "playwright-report"
    "result"
    "test-results"
    "tmp"
  ];
  ignoredExactPaths = [
    "${rootPath}/Config/client_session_key.aes"
  ];
  ignoredDirectoryRoots = [
    "${rootPath}/Test/Fixtures/private/rsa"
  ];
  hasPathPrefix = prefix: path:
    path == prefix
    || builtins.substring 0 (builtins.stringLength prefix + 1) path == "${prefix}/";
  hasTextPrefix = prefix: value:
    builtins.substring 0 (builtins.stringLength prefix) value == prefix;
  isIgnoredTopLevel = path:
    builtins.dirOf path == rootPath
    && (builtins.elem (builtins.baseNameOf path) ignoredTopLevelEntries
      || hasTextPrefix ".devenv" (builtins.baseNameOf path));
  isIgnoredGeneratedFile = path:
    builtins.match ".*\\.(dyn_hi|dyn_o|hi|iml|o)" path != null
    || builtins.match ".*/static/prod\\..*" path != null;
in
builtins.path {
  path = root;
  name = "ihp-roster-verification-source";
  filter = path: _type:
    !(isIgnoredTopLevel path
      || builtins.elem path ignoredExactPaths
      || builtins.any (prefix: hasPathPrefix prefix path) ignoredDirectoryRoots
      || isIgnoredGeneratedFile path);
}
