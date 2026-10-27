{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Bepis.Tooling.Workspace.State (Registry (..), WorkspaceIdentity (..),
                                      WorkspaceRecord (..), decodeRegistry,
                                      decodeWorkspaceIdentity, encodeRegistry,
                                      encodeWorkspaceIdentity, readWorkspaceIdentity,
                                      registryLockRelativePath, validateRegistry,
                                      writeWorkspaceIdentity)
import Bepis.Tooling.Workspace.Command (runtimeStateDirectoriesFor)
import Control.Exception (bracket, throwIO)
import Data.List (isPrefixOf)
import qualified Data.ByteString.Char8 as ByteString
import System.Directory (doesFileExist)
import System.Exit (ExitCode (ExitFailure))
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "bepis-workspace-state" $ \root -> do
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
        registry = Registry "/repo/.git" [record]
    assertEqual "v1 registry round trip" (Right registry) (decodeRegistry (encodeRegistry registry))
    assertEqual "valid registry" (Right ()) (validateRegistry "/repo/.git" registry)
    assertLeft "duplicate registry slot accepted" $ validateRegistry "/repo/.git"
        registry {workspaces = [record, WorkspaceRecord 565 "roster" "epic-565-other" "/repo-other" 4]}
    assertLeft "foreign registry owner accepted" $ validateRegistry "/other/.git" registry
    assertLeft "non-canonical registry path accepted" $ decodeRegistry $ ByteString.pack
        "{\"version\":1,\"commonGitDir\":\"/repo/.git\",\"workspaces\":[{\"epic\":564,\"targetBranch\":\"roster\",\"branch\":\"epic-564\",\"path\":\"/repo/../bad\",\"slot\":4,\"kind\":\"epic\"}]}"

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
