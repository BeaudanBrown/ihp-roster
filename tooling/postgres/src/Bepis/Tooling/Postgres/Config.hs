{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Postgres.Config
    ( ConfigError (..)
    , Durability (..)
    , Mode (..)
    , Profile (..)
    , Settings (..)
    , InstanceConfig (..)
    , loadInstanceConfig
    , profileName
    ) where

import Control.Exception (Exception, IOException, catch, throwIO)
import Control.Monad (unless, when)
import Data.Char (isAsciiLower, isDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory (canonicalizePath, doesFileExist)
import System.Environment (lookupEnv)
import qualified System.Exit as Exit
import System.FilePath (isAbsolute, (</>))
import System.Posix.User (getEffectiveUserID)
import qualified System.Process as Process

data Profile = Hspec | Development | E2E deriving (Eq, Show)
data Mode = Managed | External FilePath deriving (Eq, Show)
data Durability = Disposable | Durable | Custom deriving (Eq, Show)
data Settings = Settings
    { fsyncSetting :: Text
    , synchronousCommitSetting :: Text
    , fullPageWritesSetting :: Text
    , maxConnections :: Maybe Int
    } deriving (Eq, Show)
data InstanceConfig = InstanceConfig
    { profile :: Profile
    , profileLabel :: String
    , mode :: Mode
    , durability :: Durability
    , settings :: Settings
    , repositoryRoot :: FilePath
    , stateRoot :: FilePath
    , projectId :: String
    , ownerUid :: String
    , preserveOnStop :: Bool
    , allowNonNative :: Bool
    } deriving (Eq, Show)

data ConfigError = ConfigError Int String deriving (Show)
instance Exception ConfigError

profileName :: Profile -> String
profileName Hspec = "hspec"
profileName Development = "dev"
profileName E2E = "e2e"

loadInstanceConfig :: Profile -> IO InstanceConfig
loadInstanceConfig selectedProfile = do
    modeValue <- environment modeVariable "managed"
    case modeValue of
        "managed" -> loadManagedConfig selectedProfile program rootVariable repoVariable defaultDurability preserveDefault
        "external" -> do
            socket <- environment socketVariable ""
            unless (isAbsolute socket) $ invalid (program <> ": external mode requires absolute " <> socketVariable)
            selectedSettings <- settingsFor selectedProfile defaultDurabilityValue
            pure InstanceConfig
                { profile = selectedProfile, profileLabel = profileName selectedProfile, mode = External socket
                , durability = defaultDurabilityValue, settings = selectedSettings
                , repositoryRoot = "", stateRoot = "", projectId = "", ownerUid = ""
                , preserveOnStop = False, allowNonNative = False
                }
        _ -> invalid (program <> ": " <> modeVariable <> " must be managed or external")
  where
    program = case selectedProfile of Hspec -> "test-postgres"; Development -> "dev-postgres"; E2E -> "e2e-postgres"
    (modeVariable, socketVariable, rootVariable, repoVariable, defaultDurability, preserveDefault) = case selectedProfile of
        Hspec -> ("TEST_POSTGRES_MODE", "TEST_DB_SOCKET", "TEST_POSTGRES_ROOT", "TEST_POSTGRES_REPO_ROOT", "disposable", "0")
        Development -> ("DEV_POSTGRES_MODE", "DEV_POSTGRES_SOCKET", "DEV_POSTGRES_ROOT", "DEV_POSTGRES_REPO_ROOT", "durable", "1")
        E2E -> ("E2E_POSTGRES_MODE", "E2E_DB_SOCKET", "E2E_POSTGRES_ROOT", "E2E_POSTGRES_REPO_ROOT", "disposable", "0")
    defaultDurabilityValue = if defaultDurability == "durable" then Durable else Disposable

loadManagedConfig :: Profile -> String -> String -> String -> String -> String -> IO InstanceConfig
loadManagedConfig selectedProfile program rootVariable repoVariable defaultDurability preserveDefault = do
    rootOverride <- lookupEnv rootVariable
    repoOverride <- lookupEnv repoVariable
    repoRaw <- maybe (gitRoot program) pure repoOverride
    repo <- canonicalizePath repoRaw
    when (any (`elem` ['\n', '\r']) repo) $ invalid (program <> ": checkout paths containing newlines are unsupported")
    marker <- doesFileExist (repo </> "Config/nix/flake/scripts.nix")
    unless marker $ missing (program <> ": run from an ihp-roster checkout or set " <> repoVariable)
    uid <- show <$> getEffectiveUserID
    identifier <- sha256Prefix repo
    customProfile <- if selectedProfile == Hspec then environment "TEST_POSTGRES_PROFILE" "hspec" else pure (profileName selectedProfile)
    unless (validProfile customProfile) $ invalid (program <> ": TEST_POSTGRES_PROFILE must be a lowercase profile name: " <> customProfile)
    let defaultRoot = "/tmp/bepis-" <> customProfile <> "-postgres-" <> uid <> "-" <> identifier
        selectedRoot = fromMaybe defaultRoot rootOverride
    unless (isAbsolute selectedRoot) $ invalid (program <> ": " <> rootVariable <> " must be absolute: " <> selectedRoot)
    when (any (`elem` ['\n', '\r', '\'']) selectedRoot) $ invalid (program <> ": " <> rootVariable <> " may not contain quotes or newlines")
    when (selectedRoot `elem` ["/", "/tmp", "/var", "/var/tmp", "/run", "/run/user", repo]) $
        invalid (program <> ": refusing unsafe state root: " <> selectedRoot)
    durabilityValue <- if selectedProfile == Hspec
        then environment "TEST_POSTGRES_DURABILITY" defaultDurability
        else pure defaultDurability
    selectedDurability <- case durabilityValue of
        "disposable" -> pure Disposable
        "durable" -> pure Durable
        "custom" -> pure Custom
        _ -> invalid (program <> ": TEST_POSTGRES_DURABILITY must be disposable, durable, or custom; got: " <> durabilityValue)
    selectedSettings <- settingsFor selectedProfile selectedDurability
    preserve <- if selectedProfile == Hspec
        then (== "1") <$> environment "TEST_POSTGRES_PRESERVE_ON_STOP" preserveDefault
        else pure (preserveDefault == "1")
    nonNative <- if selectedProfile == Hspec
        then (== "1") <$> environment "TEST_POSTGRES_ALLOW_NON_NATIVE" "0"
        else pure False
    pure InstanceConfig
        { profile = selectedProfile, profileLabel = customProfile, mode = Managed
        , durability = selectedDurability, settings = selectedSettings
        , repositoryRoot = repo, stateRoot = selectedRoot, projectId = identifier
        , ownerUid = uid, preserveOnStop = preserve, allowNonNative = nonNative
        }

settingsFor :: Profile -> Durability -> IO Settings
settingsFor selectedProfile selectedDurability = do
    (fsyncValue, commitValue, pagesValue) <- case selectedDurability of
        Disposable -> pure ("on", "off", "on")
        Durable -> pure ("on", "on", "on")
        Custom -> (,,) <$> requiredSetting "TEST_POSTGRES_FSYNC"
                       <*> requiredSetting "TEST_POSTGRES_SYNCHRONOUS_COMMIT"
                       <*> requiredSetting "TEST_POSTGRES_FULL_PAGE_WRITES"
    pure Settings
        { fsyncSetting = Text.pack fsyncValue
        , synchronousCommitSetting = Text.pack commitValue
        , fullPageWritesSetting = Text.pack pagesValue
        -- IHP 1.6: eight shards, two 20-connection pools and two listeners
        -- need 336 connections; 400 retains 64 fixture/admin/reserve slots.
        , maxConnections = if selectedProfile == E2E then Just 400 else Nothing
        }

requiredSetting :: String -> IO String
requiredSetting name = do
    value <- environment name ""
    unless (value `elem` ["on", "off"]) $ invalid "test-postgres: custom durability requires explicit on/off values for all three settings"
    pure value

environment :: String -> String -> IO String
environment name fallback = fromMaybe fallback <$> lookupEnv name

validProfile :: String -> Bool
validProfile [] = False
validProfile (first:rest) = isAsciiLower first && all (\value -> isAsciiLower value || isDigit value || value == '-') rest

gitRoot :: String -> IO FilePath
gitRoot program = do
    value <- commandOutput "git" ["rev-parse", "--show-toplevel"]
    if null value then missing (program <> ": run from an ihp-roster checkout") else pure value

sha256Prefix :: String -> IO String
sha256Prefix value = take 12 <$> commandOutputWithInput "sha256sum" [] value

commandOutput :: FilePath -> [String] -> IO String
commandOutput executable arguments = commandOutputWithInput executable arguments ""

commandOutputWithInput :: FilePath -> [String] -> String -> IO String
commandOutputWithInput executable arguments input = do
    result <- Process.readProcessWithExitCode executable arguments input `catch` unavailable
    case result of
        (Exit.ExitSuccess, output, _) -> pure (trim output)
        _ -> missing ("required command failed: " <> executable)
  where
    unavailable :: IOException -> IO (Exit.ExitCode, String, String)
    unavailable _ = throwIO (ConfigError 69 ("required command is unavailable: " <> executable))

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

invalid :: String -> IO value
invalid = throwIO . ConfigError 64

missing :: String -> IO value
missing = throwIO . ConfigError 66
