{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Workspace.State
    ( PathProblem (..)
    , Registry (..)
    , RuntimeReservation (..)
    , WorkspaceIdentity (..)
    , WorkspaceRecord (..)
    , WorkspaceStatus (..)
    , decodeRegistry
    , decodeWorkspaceIdentity
    , encodeRegistry
    , encodeWorkspaceIdentity
    , identityFileName
    , inspectCanonicalPath
    , runtimePorts
    , runtimePathOverlap
    , validRuntimePorts
    , portConflicts
    , readRegistry
    , readWorkspaceIdentity
    , registryFileRelativePath
    , registryLockRelativePath
    , validateRegistry
    , withRegistryLock
    , withRegisteredWorkspaceCleanup
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
import Data.List (intersect, isPrefixOf, nub)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory (makeAbsolute, pathIsSymbolicLink)
import System.Posix.Files (FileStatus, getSymbolicLinkStatus, isRegularFile)
import System.FilePath (addTrailingPathSeparator, isAbsolute, normalise, splitDirectories, takeDirectory, (</>))
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
    , runtime      :: [RuntimeReservation]
    }
    deriving (Eq, Show)

-- Epic metadata is independent; both plain and epic worktrees own the same
-- reservation shape. Keep historical evidence locations when overrides change.
data RuntimeReservation = RuntimeReservation
    { runtimePath            :: FilePath
    , runtimeSlot            :: Int
    , runtimePortOffset      :: Int
    , runtimeStateDirs       :: [FilePath]
    , runtimePostgresRoots   :: [FilePath]
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
        version <- value .: "version"
        unless (version == (2 :: Int)) $ fail "registry requires v2; complete the operator cutover first"
        exactFields 4 value "registry"
        owner <- value .: "commonGitDir"
        records <- value .: "workspaces"
        reservations <- value .: "runtime"
        unless (validAbsolutePath owner) $ fail "registry has invalid common Git directory"
        pure Registry {commonGitDir = owner, workspaces = records, runtime = reservations}

instance ToJSON Registry where
    toJSON Registry {commonGitDir, workspaces, runtime} = object
        [ "version" .= (2 :: Int), "commonGitDir" .= commonGitDir
        , "workspaces" .= workspaces, "runtime" .= runtime ]

instance FromJSON RuntimeReservation where
    parseJSON = withObject "RuntimeReservation" $ \value -> do
        exactFields 5 value "runtime reservation"
        reservation <- RuntimeReservation <$> value .: "path" <*> value .: "slot"
            <*> value .: "portOffset" <*> value .: "stateDirectories" <*> value .: "managedPostgresRoots"
        unless (validReservation reservation) $ fail "invalid runtime reservation"
        pure reservation

instance ToJSON RuntimeReservation where
    toJSON RuntimeReservation {runtimePath, runtimeSlot, runtimePortOffset, runtimeStateDirs, runtimePostgresRoots} = object
        [ "path" .= runtimePath, "slot" .= runtimeSlot, "portOffset" .= runtimePortOffset
        , "stateDirectories" .= runtimeStateDirs, "managedPostgresRoots" .= runtimePostgresRoots ]

validReservation :: RuntimeReservation -> Bool
validReservation RuntimeReservation {runtimePath, runtimeSlot, runtimePortOffset, runtimeStateDirs, runtimePostgresRoots} =
    validAbsolutePath runtimePath && validRuntimePorts runtimeSlot runtimePortOffset
        && all validAbsolutePath (runtimeStateDirs <> runtimePostgresRoots)
        && nub runtimeStateDirs == runtimeStateDirs && nub runtimePostgresRoots == runtimePostgresRoots

-- Every listener selected by the workspace layout, including the development
-- tools' app+1 port and Tempo's existing slot-only memberlist port.
runtimePorts :: Int -> Int -> [Int]
runtimePorts slotNumber offset =
    [app, app + 1, app + 2, 7946 + slotNumber]
        <> map (+ (offset + slotNumber)) [1025, 8025, 3200, 9095, 14317, 14318, 4317, 4318, 13133, 3300]
  where app = 8000 + offset + 3 * slotNumber

validRuntimePorts :: Int -> Int -> Bool
validRuntimePorts slotNumber offset =
    slotNumber >= 0 && slotNumber <= 19177 && offset >= 0 && offset <= 40000
        && all (<= 65535) ports && length (nub ports) == length ports
  where ports = runtimePorts slotNumber offset

portConflicts :: RuntimeReservation -> RuntimeReservation -> Bool
portConflicts first second = not (null (ports first `intersect` ports second))
  where ports reservation = runtimePorts (runtimeSlot reservation) (runtimePortOffset reservation)


exactFields :: Int -> KeyMap.KeyMap value -> String -> Aeson.Parser ()
exactFields count value label = unless (KeyMap.size value == count) (fail (label <> " must contain exactly the declared fields"))

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
    canonical <- inspectCanonicalPath path
    case canonical of
        Left badPath -> pure (Left ("unsafe registry path: " <> show badPath))
        Right () -> do
            status <- (Just <$> getSymbolicLinkStatus path) `catch` absent
            case status of
                Nothing -> pure (Right Nothing)
                Just attributes | isRegularFile attributes -> fmap (fmap Just . decodeRegistry) (ByteString.readFile path)
                _ -> pure (Left "registry exists but is not a regular file")
  where
    absent :: IOException -> IO (Maybe FileStatus)
    absent exception | isDoesNotExistError exception = pure Nothing
                     | otherwise = throwIO exception

validateRegistry :: FilePath -> Registry -> Either String ()
validateRegistry owner Registry {commonGitDir, workspaces, runtime}
    | commonGitDir /= owner = Left "registry belongs to another Git common directory"
    | duplicate (map recordEpic workspaces) = Left "registry contains duplicate epic numbers"
    | duplicate (map recordBranch workspaces) = Left "registry contains duplicate epic branches"
    | duplicate (map recordPath workspaces) = Left "registry contains duplicate epic paths"
    | duplicate (map runtimePath runtime) = Left "registry contains duplicate runtime paths"
    | duplicate (map runtimeSlot runtime) = Left "registry contains duplicate runtime slots"
    | not (all validReservation runtime) = Left "registry contains an invalid runtime reservation"
    | not (all hasReservation workspaces) = Left "registry contains an epic without its matching runtime reservation"
    | anyPair evidenceConflicts runtime = Left "registry contains overlapping runtime state or PostgreSQL paths"
    | otherwise = Right ()
  where
    linked = filter ((/= 0) . runtimeSlot) runtime
    duplicate values = length values /= length (nub values)
    hasReservation record = any (\entry -> runtimePath entry == recordPath record && runtimeSlot entry == recordSlot record) linked
    evidenceConflicts first second = runtimePathOverlap (paths first) (paths second)
    paths entry = runtimeStateDirs entry <> runtimePostgresRoots entry
    anyPair _ [] = False
    anyPair conflicts (entry:rest) = any (conflicts entry) rest || anyPair conflicts rest

runtimePathOverlap :: [FilePath] -> [FilePath] -> Bool
runtimePathOverlap first second = any (\left -> any (overlaps left) second) first
  where overlaps left right = left == right || addTrailingPathSeparator left `isPrefixOf` right || addTrailingPathSeparator right `isPrefixOf` left

withRegistryLock :: FilePath -> IO value -> IO value
withRegistryLock common = withExclusiveLock (common </> registryLockRelativePath)

writeRegistryUnlocked :: FilePath -> Registry -> IO ()
writeRegistryUnlocked common = writeFileAtomic (common </> registryFileRelativePath) . encodeRegistry

writeWorkspaceIdentityUnlocked :: FilePath -> WorkspaceIdentity -> IO ()
writeWorkspaceIdentityUnlocked root = writeFileAtomic (root </> identityFileName) . encodeWorkspaceIdentity

withRegisteredWorkspaceCleanup :: FilePath -> WorkspaceRecord -> IO () -> IO Bool
withRegisteredWorkspaceCleanup common expected cleanup = withRegistryLock common $ do
    decoded <- readRegistry common
    case decoded of
        Right (Just registry) | validateRegistry common registry == Right () ->
            case filter ((== recordEpic expected) . recordEpic) (workspaces registry) of
                [actual] | actual == expected -> do
                    cleanup
                    writeRegistryUnlocked common registry
                        { workspaces = filter ((/= recordEpic expected) . recordEpic) (workspaces registry)
                        -- The allocator, not epic cleanup, proves runtime absence.
                        }
                    pure True
                _ -> pure False
        _ -> pure False

writeWorkspaceIdentity :: FilePath -> FilePath -> WorkspaceIdentity -> IO ()
writeWorkspaceIdentity common root identity = withRegistryLock common (writeWorkspaceIdentityUnlocked root identity)
