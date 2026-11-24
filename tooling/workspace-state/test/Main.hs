{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Bepis.Tooling.Workspace.State (Registry (..), RuntimeReservation (..), WorkspaceIdentity (..),
                                      WorkspaceRecord (..), decodeRegistry,
                                      decodeWorkspaceIdentity, encodeRegistry,
                                      encodeWorkspaceIdentity, readWorkspaceIdentity,
                                      registryFileRelativePath, registryLockRelativePath, runtimePorts, portConflicts, validateRegistry,
                                      writeWorkspaceIdentity)
import Bepis.Tooling.Workspace.Command (runWorkspaceCommand, runtimeStateDirectoriesFor)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, bracket, throwIO, try)
import Data.List (isPrefixOf)
import qualified Data.ByteString.Char8 as ByteString
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesFileExist, findExecutable)
import System.Environment (getArgs, getEnvironment, getExecutablePath, lookupEnv, setEnv, unsetEnv, withArgs)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = getArgs >>= run

run :: [String] -> IO ()
run ("--cli":arguments) = withArgs arguments runWorkspaceCommand
run _ = withSystemTempDirectory "bepis-workspace-state" $ \requested -> do
    root <- canonicalizePath requested
    testRuntimeDirectoryScope root
    let identity = WorkspaceIdentity {epic = 564, targetBranch = "roster", slot = 4}
        workspaceRoot = root </> "workspace"
    assertEqual "v1 round trip" (Right identity) (decodeWorkspaceIdentity (encodeWorkspaceIdentity identity))
    writeWorkspaceIdentity root workspaceRoot identity
    readBack <- readWorkspaceIdentity workspaceRoot
    lockExists <- doesFileExist (root </> registryLockRelativePath)
    assertEqual "workspace write used registry lock" True lockExists
    assertEqual "atomic identity write" (Right identity) readBack
    assertEqual "published registry lock" ("bepis" </> "epic-worktrees" </> "registry.lock") registryLockRelativePath
    assertLeft "extra v2 field accepted" $ decodeWorkspaceIdentity $ ByteString.pack
        "{\"version\":1,\"epic\":564,\"targetBranch\":\"roster\",\"slot\":4,\"kind\":\"epic\",\"name\":\"haskell-tooling\"}"
    assertLeft "v2 identity accepted" $ decodeWorkspaceIdentity $ ByteString.pack
        "{\"version\":2,\"epic\":564,\"targetBranch\":\"roster\",\"slot\":4,\"kind\":\"epic\"}"
    let record = WorkspaceRecord 564 "roster" "epic-564-haskell-tooling" "/repo-haskell-tooling" 4
        reservation = RuntimeReservation "/repo-haskell-tooling" 4 0 [] []
        registry = Registry "/repo/.git" [record] [reservation]
    assertEqual "v2 registry round trip" (Right registry) (decodeRegistry (encodeRegistry registry))
    assertEqual "valid registry" (Right ()) (validateRegistry "/repo/.git" registry)
    assertLeft "duplicate registry slot accepted" $ validateRegistry "/repo/.git"
        registry {runtime = [reservation, RuntimeReservation "/repo-other" 4 0 [] []]}
    assertLeft "foreign registry owner accepted" $ validateRegistry "/other/.git" registry
    assertLeft "non-canonical registry path accepted" $ decodeRegistry $ ByteString.pack
        "{\"version\":1,\"commonGitDir\":\"/repo/.git\",\"workspaces\":[{\"epic\":564,\"targetBranch\":\"roster\",\"branch\":\"epic-564\",\"path\":\"/repo/../bad\",\"slot\":4,\"kind\":\"epic\"}]}"

    assertLeft "v1 registry unexpectedly accepted" $ decodeRegistry "{\"version\":1,\"commonGitDir\":\"/repo/.git\",\"workspaces\":[]}"
    assertEqual "memberlist unaffected by offset" True (7950 `elem` runtimePorts 4 25)
    assertEqual "web and MailHog cross-service collision" True
        (portConflicts (RuntimeReservation "/a" 9 0 [] []) (RuntimeReservation "/b" 2 0 [] []))
    assertLeft "nested runtime ownership accepted" $ validateRegistry "/repo/.git" $
        Registry "/repo/.git" [] [RuntimeReservation "/a" 1 0 ["/state"] [], RuntimeReservation "/b" 2 0 [] ["/state/pg"]]
    configuredPath <- lookupEnv "BEPIS_WORKSPACE_TEST_PATH"
    maybe (pure ()) (setEnv "PATH") configuredPath
    git <- findExecutable "git"
    case git of
        Just _ -> isolatedCli root
        Nothing -> case configuredPath of
            Nothing -> putStrLn "isolated workspace CLI fixtures skipped (no git in test PATH)"
            Just _ -> failTest "BEPIS_WORKSPACE_TEST_PATH does not contain git"

isolatedCli :: FilePath -> IO ()
isolatedCli root = do
    executable <- getExecutablePath
    inherited <- getEnvironment
    let repo = root </> "repo"
        first = root </> "first worktree"
        second = root </> "second"
        epicPath = root </> "epic"
        replacement = root </> "replacement"
        common = repo </> ".git"
        stored = common </> registryFileRelativePath
        state = root </> "services"
        pg = root </> "pg"
        controlled key = any (\prefix -> ByteString.pack prefix `ByteString.isPrefixOf` ByteString.pack key)
            ["GIT_", "BEPIS_WORKSPACE_", "DEV_POSTGRES_", "DEVENV_AGENT_STATE_DIR"]
        cli worktree pgRoot extras args = readCreateProcessWithExitCode
            (proc executable ("--cli" : args)) {cwd = Just worktree,
                env = Just (extras <> [("DEVENV_AGENT_STATE_DIR", state), ("DEV_POSTGRES_ROOT", pgRoot)]
                    <> filter (not . controlled . fst) inherited)} ""
        git worktree args = runSuccess "git" ((proc "git" args) {cwd = Just worktree})
        assertStatus label expected (status, _, err) = assertEqual (label <> " stderr=" <> err) expected status
    createDirectoryIfMissing True repo
    git repo ["init", "-q", "-b", "main"]
    git repo ["-c", "user.name=Workspace Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "--allow-empty", "-m", "fixture"]
    git repo ["worktree", "add", "-q", "-b", "first", first]
    git repo ["worktree", "add", "-q", "-b", "second", second]
    git repo ["worktree", "add", "-q", "-b", "epic-fixture", epicPath]
    cli first (pg </> "first") [] ["info", "--json"] >>= assertStatus "unallocated lookup" (ExitFailure 4)
    doesFileExist stored >>= assertEqual "lookup created registry" False
    let primaryLookup = readCreateProcessWithExitCode (proc executable ["--cli", "info", "--json"])
            {cwd = Just repo, env = Just (filter (not . controlled . fst) inherited)} ""
    primaryLookup >>= assertStatus "primary read-only lookup works before registration" ExitSuccess
    doesFileExist stored >>= assertEqual "primary lookup created registry" False
    firstResult <- newEmptyMVar
    secondResult <- newEmptyMVar
    _ <- forkIO (try (cli first (pg </> "first") [] ["runtime", "--json"]) >>= putMVar firstResult)
    _ <- forkIO (try (cli second (pg </> "second") [] ["runtime", "--json"]) >>= putMVar secondResult)
    firstRun <- takeMVar firstResult >>= either (throwIO :: SomeException -> IO (ExitCode, String, String)) pure
    secondRun <- takeMVar secondResult >>= either (throwIO :: SomeException -> IO (ExitCode, String, String)) pure
    assertStatus "concurrent first allocation" ExitSuccess firstRun
    assertStatus "concurrent second allocation" ExitSuccess secondRun
    registry <- ByteString.readFile stored >>= either failTest pure . decodeRegistry
    assertEqual "concurrent unique slots" [2, 4] (map runtimeSlot (runtime registry))
    assertEqual "separate DB roots" [[pg </> "first"], [pg </> "second"]]
        (map (\path -> concat [runtimePostgresRoots entry | entry <- runtime registry, runtimePath entry == path]) [first, second])
    cli first (pg </> "first") [] ["info", "--json"] >>= assertEqual "read-only persistence" firstRun
    cli first (pg </> "other") [] ["info", "--json"] >>= assertStatus "unreserved unsafe lookup" (ExitFailure 65)
    cli first (pg </> "second/child") [] ["runtime", "--json"] >>= assertStatus "nested managed path" (ExitFailure 65)
    cli first (pg </> "first") [("BEPIS_WORKSPACE_PORT_OFFSET", "1")] ["runtime", "--json"] >>= assertStatus "offset is pinned" (ExitFailure 65)
    cli epicPath (pg </> "epic") [] ["register", "--epic", "55", "--target", "main", "--json"] >>= assertStatus "epic shared allocation" ExitSuccess
    updated <- ByteString.readFile stored >>= either failTest pure . decodeRegistry
    assertEqual "epic reservation shares allocator" [2, 4, 6] (map runtimeSlot (runtime updated))
    assertEqual "epic metadata retained" [55] (map recordEpic (workspaces updated))
    cli first (pg </> "first") [] ["info", "--json"] >>= assertEqual "epic registration preserved plain identity" firstRun
    git first ["branch", "-m", "renamed"]
    cli first (pg </> "first") [] ["info", "--json"] >>= assertEqual "branch rename preserved runtime identity" firstRun
    let firstDirs = concat [runtimeStateDirs entry | entry <- runtime updated, runtimePath entry == first]
    case firstDirs of
        [firstDir] -> writeFile (firstDir </> "worker.pid") "ambiguous owned state remains"
        _ -> failTest "fixture did not retain exactly one state directory"
    createDirectoryIfMissing True (pg </> "first")
    writeFile (pg </> "first/retained-data") "not a cleanup target"
    git repo ["worktree", "remove", first]
    git repo ["worktree", "add", "-q", "-b", "replacement", replacement]
    cli replacement (pg </> "replacement") [] ["runtime", "--json"] >>= assertStatus "new runtime with stale evidence" ExitSuccess
    retained <- ByteString.readFile stored >>= either failTest pure . decodeRegistry
    assertEqual "stale reservation retained with runtime evidence" [2, 4, 6, 11] (map runtimeSlot (runtime retained))
    doesFileExist (pg </> "first/retained-data") >>= assertEqual "reclamation never deletes database" True
    incumbent <- case workspaces retained of
        [record] -> pure record
        _ -> failTest "fixture expected one incumbent epic"
    let legacySlot = 1
        legacy = retained
            { workspaces = [incumbent {recordSlot = legacySlot}]
            , runtime = [if runtimePath entry == epicPath then entry {runtimeSlot = legacySlot} else entry | entry <- runtime retained]
            }
    ByteString.writeFile stored (encodeRegistry legacy)
    writeWorkspaceIdentity common epicPath (WorkspaceIdentity 55 "main" legacySlot)
    let defaultLookup worktree = readCreateProcessWithExitCode (proc executable ["--cli", "info", "--json"])
            {cwd = Just worktree, env = Just (filter (not . controlled . fst) inherited)} ""
    result@(_, details, _) <- defaultLookup epicPath
    assertStatus "imported slot 1 still resolves" ExitSuccess result
    assertEqual "imported epic kept its slot" True (ByteString.isInfixOf "\"slot\":1" (ByteString.pack details))
    primaryLookup >>= assertStatus "primary baseline stays resolvable" ExitSuccess
    let newPath = root </> "after-cutover"
    git repo ["worktree", "add", "-q", "-b", "after-cutover", newPath]
    cli newPath (pg </> "after-cutover") [] ["runtime", "--json"] >>= assertStatus "allocate around imported overlaps" ExitSuccess
    afterCutover <- ByteString.readFile stored >>= either failTest pure . decodeRegistry
    let added = filter ((== newPath) . runtimePath) (runtime afterCutover)
    assertEqual "new reservation avoids every incumbent and the primary baseline" [6] (map runtimeSlot added)

runSuccess :: String -> CreateProcess -> IO ()
runSuccess label command = do
    (status, _, err) <- readCreateProcessWithExitCode command ""
    assertEqual (label <> " failed: " <> err) ExitSuccess status

-- Exercise the discovery function used by epic preflight, not a test-only
-- path filter. Inherited caller state must not become target-epic stale state.
testRuntimeDirectoryScope :: FilePath -> IO ()
testRuntimeDirectoryScope root = withSavedEnvironment $ do
    let caller = root </> "caller"
        target = root </> "target"
        explicit = root </> "caller-runtime"
        shared = root </> "shared-runtime"
    setEnv "DEVENV_AGENT_STATE_DIR" explicit
    setEnv "BEPIS_WORKSPACE_REPO_ROOT" caller
    setEnv "BEPIS_WORKSPACE_STATE_ROOT" shared
    foreignDirectories <- runtimeStateDirectoriesFor target
    assertEqual "foreign explicit runtime directory excluded" False (explicit `elem` foreignDirectories)
    assertEqual "target legacy directory retained" True ((target </> ".devenv/agent") `elem` foreignDirectories)
    assertEqual "target configured-root discovery retained" True
        (any (isPrefixOf (shared </> "workspace-")) foreignDirectories)
    ownDirectories <- runtimeStateDirectoriesFor caller
    assertEqual "own explicit runtime directory retained" True (explicit `elem` ownDirectories)
    unsetEnv "BEPIS_WORKSPACE_REPO_ROOT"
    unboundDirectories <- runtimeStateDirectoriesFor target
    assertEqual "unbound explicit runtime directory excluded" False (explicit `elem` unboundDirectories)
  where
    keys = ["DEVENV_AGENT_STATE_DIR", "BEPIS_WORKSPACE_REPO_ROOT", "BEPIS_WORKSPACE_STATE_ROOT"]
    withSavedEnvironment action = bracket
        (mapM (\key -> (,) key <$> lookupEnv key) keys)
        (mapM_ (\(key, value) -> maybe (unsetEnv key) (setEnv key) value))
        (const action)

assertEqual :: (Eq value, Show value) => String -> value -> value -> IO ()
assertEqual label expected actual =
    if actual == expected then pure () else failTest (label <> ": expected " <> show expected <> ", got " <> show actual)

assertLeft :: Show value => String -> Either String value -> IO ()
assertLeft _ (Left _)   = pure ()
assertLeft label actual = failTest (label <> ": " <> show actual)

failTest :: String -> IO a
failTest message = do
    ByteString.putStrLn (ByteString.pack message)
    throwIO (ExitFailure 1)
