{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Workspace.State
    ( WorkspaceIdentity (..)
    , decodeWorkspaceIdentity
    , encodeWorkspaceIdentity
    , identityFileName
    , readWorkspaceIdentity
    , registryLockRelativePath
    , writeWorkspaceIdentity
    ) where

import Bepis.Tooling.Core.OwnedFile (withExclusiveLock, writeFileAtomic)
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), eitherDecodeStrict',
                   encode, object, withObject, (.:), (.=))
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import Data.Text (Text)
import System.FilePath ((</>))

data WorkspaceIdentity = WorkspaceIdentity
    { epic         :: Int
    , targetBranch :: Text
    , slot         :: Int
    }
    deriving (Eq, Show)

instance FromJSON WorkspaceIdentity where
    parseJSON = withObject "WorkspaceIdentity" $ \value -> do
        if KeyMap.size value == 5
            then pure ()
            else fail "workspace identity must contain exactly the v1 fields"
        version <- value .: "version"
        kind <- value .: "kind"
        parsedEpic <- value .: "epic"
        parsedTarget <- value .: "targetBranch"
        parsedSlot <- value .: "slot"
        if version == (1 :: Int) && kind == ("epic" :: Text) && parsedEpic > 0 && parsedSlot > 0
            then pure WorkspaceIdentity {epic = parsedEpic, targetBranch = parsedTarget, slot = parsedSlot}
            else fail "workspace identity has invalid v1 values"

instance ToJSON WorkspaceIdentity where
    toJSON WorkspaceIdentity {epic, targetBranch, slot} = object
        [ "version" .= (1 :: Int)
        , "epic" .= epic
        , "targetBranch" .= targetBranch
        , "slot" .= slot
        , "kind" .= ("epic" :: Text)
        ]

identityFileName :: FilePath
identityFileName = ".bepis-epic-worktree.json"

registryLockRelativePath :: FilePath
registryLockRelativePath = "bepis" </> "epic-worktrees" </> "registry.lock"

decodeWorkspaceIdentity :: ByteString.ByteString -> Either String WorkspaceIdentity
decodeWorkspaceIdentity = eitherDecodeStrict'

encodeWorkspaceIdentity :: WorkspaceIdentity -> ByteString.ByteString
encodeWorkspaceIdentity = LazyByteString.toStrict . encode

readWorkspaceIdentity :: FilePath -> IO (Either String WorkspaceIdentity)
readWorkspaceIdentity root = decodeWorkspaceIdentity <$> ByteString.readFile (root </> identityFileName)

writeWorkspaceIdentity :: FilePath -> FilePath -> WorkspaceIdentity -> IO ()
writeWorkspaceIdentity commonGitDirectory workspaceRoot identity =
    withExclusiveLock (commonGitDirectory </> registryLockRelativePath) $
        writeFileAtomic (workspaceRoot </> identityFileName) (encodeWorkspaceIdentity identity)
