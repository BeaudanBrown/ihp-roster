{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Bepis.Tooling.Workspace.State (WorkspaceIdentity (..),
                                      decodeWorkspaceIdentity,
                                      encodeWorkspaceIdentity,
                                      readWorkspaceIdentity,
                                      registryLockRelativePath,
                                      writeWorkspaceIdentity)
import Control.Exception (throwIO)
import qualified Data.ByteString.Char8 as ByteString
import System.Directory (doesFileExist)
import System.Exit (ExitCode (ExitFailure))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "bepis-workspace-state" $ \root -> do
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
