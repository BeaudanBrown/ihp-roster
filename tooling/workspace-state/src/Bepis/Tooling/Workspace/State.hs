{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Workspace.State
    ( PathProblem (..)
    , Registry (..)
    , WorkspaceIdentity (..)
    , WorkspaceRecord (..)
    , WorkspaceStatus (..)
    , decodeRegistry
    , decodeWorkspaceIdentity
    , encodeRegistry
    , encodeWorkspaceIdentity
    , identityFileName
    , inspectCanonicalPath
    , readRegistry
    , readWorkspaceIdentity
    , registryFileRelativePath
    , registryLockRelativePath
    , validateRegistry
    , withRegistryLock
    , writeRegistryUnlocked
    , writeWorkspaceIdentity
    , writeWorkspaceIdentityUnlocked
    ) where

import Bepis.Tooling.Core.OwnedFile (withExclusiveLock, writeFileAtomic)
import Control.Exception (IOException, catch, throwIO)
import Control.Monad (unless)
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), eitherDecodeStrict',
                   encode, object, withObject, (.:), (.=))
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory (doesFileExist, makeAbsolute, pathIsSymbolicLink)
import System.FilePath (isAbsolute, normalise, splitDirectories, takeDirectory, (</>))
import System.IO.Error (isDoesNotExistError)

data PathProblem = NonCanonicalPath FilePath | SymlinkPathComponent FilePath
    deriving (Eq, Show)

data WorkspaceIdentity = WorkspaceIdentity
    { epic         :: Int
    , targetBranch :: Text
    , slot         :: Int
    }
    deriving (Eq, Show)

data WorkspaceRecord = WorkspaceRecord
    { recordEpic         :: Int
    , recordTargetBranch :: Text
    , recordBranch       :: Text
    , recordPath         :: FilePath
    , recordSlot         :: Int
    }
    deriving (Eq, Show)

data Registry = Registry
    { commonGitDir :: FilePath
    , workspaces   :: [WorkspaceRecord]
    }
    deriving (Eq, Show)

data WorkspaceStatus = Active | MissingIdentity | InconsistentIdentity | Stale
    deriving (Eq, Show)

instance FromJSON WorkspaceIdentity where
    parseJSON = withObject "WorkspaceIdentity" $ \value -> do
        exactFields 5 value "workspace identity"
        version <- value .: "version"
        kind <- value .: "kind"
        parsedEpic <- value .: "epic"
        parsedTarget <- value .: "targetBranch"
        parsedSlot <- value .: "slot"
        unless (version == (1 :: Int) && kind == ("epic" :: Text) && parsedEpic > 0 && parsedSlot > 0 && validText parsedTarget) $
            fail "workspace identity has invalid v1 values"
        pure WorkspaceIdentity {epic = parsedEpic, targetBranch = parsedTarget, slot = parsedSlot}

instance ToJSON WorkspaceIdentity where
    toJSON WorkspaceIdentity {epic, targetBranch, slot} = object
        [ "version" .= (1 :: Int), "epic" .= epic, "targetBranch" .= targetBranch
        , "slot" .= slot, "kind" .= ("epic" :: Text)
        ]

instance FromJSON WorkspaceRecord where
    parseJSON = withObject "WorkspaceRecord" $ \value -> do
        exactFields 6 value "workspace record"
        parsedEpic <- value .: "epic"
        parsedTarget <- value .: "targetBranch"
        parsedBranch <- value .: "branch"
        parsedPath <- value .: "path"
        parsedSlot <- value .: "slot"
        kind <- value .: "kind"
        unless (parsedEpic > 0 && parsedSlot > 0 && kind == ("epic" :: Text)
                && validText parsedTarget && validText parsedBranch && validAbsolutePath parsedPath) $
            fail "workspace record has invalid v1 values"
        pure WorkspaceRecord
            { recordEpic = parsedEpic, recordTargetBranch = parsedTarget
            , recordBranch = parsedBranch, recordPath = parsedPath, recordSlot = parsedSlot
            }

instance ToJSON WorkspaceRecord where
    toJSON WorkspaceRecord {recordEpic, recordTargetBranch, recordBranch, recordPath, recordSlot} = object
        [ "epic" .= recordEpic, "targetBranch" .= recordTargetBranch, "branch" .= recordBranch
        , "path" .= recordPath, "slot" .= recordSlot, "kind" .= ("epic" :: Text)
        ]

instance FromJSON Registry where
    parseJSON = withObject "Registry" $ \value -> do
        exactFields 3 value "registry"
        version <- value .: "version"
        owner <- value .: "commonGitDir"
        records <- value .: "workspaces"
        unless (version == (1 :: Int) && validAbsolutePath owner) $ fail "registry has invalid v1 values"
        pure Registry {commonGitDir = owner, workspaces = records}

instance ToJSON Registry where
    toJSON Registry {commonGitDir, workspaces} = object
        [ "version" .= (1 :: Int), "commonGitDir" .= commonGitDir, "workspaces" .= workspaces ]

exactFields :: Int -> KeyMap.KeyMap value -> String -> Aeson.Parser ()
exactFields count value label = unless (KeyMap.size value == count) (fail (label <> " must contain exactly the v1 fields"))

validText :: Text -> Bool
validText value = not (Text.null value) && Text.all (`notElem` ['\n', '\r']) value

validAbsolutePath :: FilePath -> Bool
validAbsolutePath path =
    isAbsolute path && path /= "/" && normalise path == path
        && not (any (`elem` [".", ".."]) (splitDirectories path))
        && '\n' `notElem` path && '\r' `notElem` path

inspectCanonicalPath :: FilePath -> IO (Either PathProblem ())
inspectCanonicalPath requested = do
    absolute <- normalise <$> makeAbsolute requested
    if absolute /= requested || any (`elem` [".", ".."]) (splitDirectories requested)
        then pure (Left (NonCanonicalPath requested))
        else inspect requested
  where
    inspect "/" = pure (Right ())
    inspect component = do
        linked <- pathIsSymbolicLink component `catchMissing` pure False
        if linked then pure (Left (SymlinkPathComponent component)) else inspect (takeDirectory component)
    catchMissing action fallback = action `catch` handler
      where
        handler :: IOException -> IO Bool
        handler errorValue = if isDoesNotExistError errorValue then fallback else throwIO errorValue

identityFileName, registryFileRelativePath, registryLockRelativePath :: FilePath
identityFileName = ".bepis-epic-worktree.json"
registryFileRelativePath = "bepis" </> "epic-worktrees" </> "registry.json"
registryLockRelativePath = "bepis" </> "epic-worktrees" </> "registry.lock"

decodeWorkspaceIdentity :: ByteString.ByteString -> Either String WorkspaceIdentity
decodeWorkspaceIdentity = eitherDecodeStrict'

encodeWorkspaceIdentity :: WorkspaceIdentity -> ByteString.ByteString
encodeWorkspaceIdentity = LazyByteString.toStrict . encode

decodeRegistry :: ByteString.ByteString -> Either String Registry
decodeRegistry = eitherDecodeStrict'

encodeRegistry :: Registry -> ByteString.ByteString
encodeRegistry = LazyByteString.toStrict . encode

readWorkspaceIdentity :: FilePath -> IO (Either String WorkspaceIdentity)
readWorkspaceIdentity root = decodeWorkspaceIdentity <$> ByteString.readFile (root </> identityFileName)

readRegistry :: FilePath -> IO (Either String (Maybe Registry))
readRegistry common = do
    let path = common </> registryFileRelativePath
    exists <- doesFileExist path
    if exists then fmap (fmap Just . decodeRegistry) (ByteString.readFile path) else pure (Right Nothing)

validateRegistry :: FilePath -> Registry -> Either String ()
validateRegistry owner Registry {commonGitDir, workspaces}
    | commonGitDir /= owner = Left "registry belongs to another Git common directory"
    | duplicate recordEpic = Left "registry contains duplicate epic numbers"
    | duplicate recordBranch = Left "registry contains duplicate branches"
    | duplicate recordPath = Left "registry contains duplicate paths"
    | duplicate recordSlot = Left "registry contains duplicate slots"
    | otherwise = Right ()
  where
    duplicate project = let values = map project workspaces in length values /= length (nub values)

withRegistryLock :: FilePath -> IO value -> IO value
withRegistryLock common = withExclusiveLock (common </> registryLockRelativePath)

writeRegistryUnlocked :: FilePath -> Registry -> IO ()
writeRegistryUnlocked common = writeFileAtomic (common </> registryFileRelativePath) . encodeRegistry

writeWorkspaceIdentityUnlocked :: FilePath -> WorkspaceIdentity -> IO ()
writeWorkspaceIdentityUnlocked root = writeFileAtomic (root </> identityFileName) . encodeWorkspaceIdentity

writeWorkspaceIdentity :: FilePath -> FilePath -> WorkspaceIdentity -> IO ()
writeWorkspaceIdentity common root identity = withRegistryLock common (writeWorkspaceIdentityUnlocked root identity)
