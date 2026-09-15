{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Workspace.Command (runWorkspaceCommand) where

import Bepis.Tooling.Workspace.State
import Control.Exception (Exception, IOException, catch, throwIO)
import Control.Monad (unless, when)
import Data.Aeson (ToJSON (toJSON), encode, object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy.Char8 as LazyByteString
import Data.Char (isAsciiLower, isDigit)
import Data.List (find, intercalate, isPrefixOf, sortOn)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import System.Directory (canonicalizePath, createDirectoryIfMissing, createFileLink, doesDirectoryExist,
                         doesFileExist, doesPathExist, getCurrentDirectory,
                         getDirectoryContents, makeAbsolute, pathIsSymbolicLink)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (isAbsolute, normalise, takeDirectory, takeFileName, (</>))
import System.IO (hPutStrLn, stderr)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Files (setFileMode)
import System.Posix.User (getEffectiveUserID)
import System.Process (readProcessWithExitCode)
import Text.Read (readMaybe)

data ToolError = ToolError Int String deriving (Show)
instance Exception ToolError

data Selector = ByEpic Int | ByBranch String | ByPath FilePath | All deriving (Eq, Show)

data Options = Options
    { optionValues :: [(String, String)]
    , optionFlags  :: [String]
    }

runWorkspaceCommand :: IO ()
runWorkspaceCommand = run `catch` handleToolError
  where
    handleToolError (ToolError status message) = do
        hPutStrLn stderr ("bepis-workspace-state: " <> message)
        exitWith (ExitFailure status)

run :: IO ()
run = do
    arguments <- getArgs
    case arguments of
        ["contract"] -> printJson $ object
            [ "identityFile" .= identityFileName, "identityVersion" .= (1 :: Int)
            , "registryFile" .= registryFileRelativePath, "registryLock" .= registryLockRelativePath
            ]
        [command, help] | command `elem` ["register", "resolve", "provision"] && help `elem` ["-h", "--help"] -> putStrLn usage
        "register":rest  -> registerCommand =<< parseOptions ["--epic", "--target", "--branch", "--path", "--kind"] ["--json"] rest
        "resolve":rest   -> resolveCommand =<< parseOptions ["--epic", "--branch", "--path"] ["--all", "--json"] rest
        "provision":rest -> provisionCommand =<< parseOptions ["--epic", "--base", "--name"] ["--json"] rest
        "info":rest      -> infoCommand rest
        ["agent-state-dir"] -> workspaceConfiguration >>= putStrLn . field "DEVENV_AGENT_STATE_DIR"
        _ -> failure 64 usage

usage :: String
usage = intercalate "\n"
    [ "Usage: bepis-workspace-state COMMAND [OPTIONS]"
    , "Commands: register, resolve, provision, info, agent-state-dir, contract"
    ]

parseOptions :: [String] -> [String] -> [String] -> IO Options
parseOptions values flags = go (Options [] [])
  where
    go result [] = pure result
    go result (name:value:rest) | name `elem` values = go result {optionValues = (name, value) : optionValues result} rest
    go _ [name] | name `elem` values = failure 64 ("missing value for " <> name)
    go result (name:rest) | name `elem` flags = go result {optionFlags = name : optionFlags result} rest
    go _ (name:_) = failure 64 ("unknown option: " <> name)

required :: String -> Options -> IO String
required name options = maybe (failure 64 ("missing required option " <> name)) pure (lookup name (optionValues options))

optional :: String -> Options -> Maybe String
optional name = lookup name . optionValues

flag :: String -> Options -> Bool
flag name = elem name . optionFlags

positive :: String -> String -> IO Int
positive label value = case readMaybe value of
    Just number | number > 0 -> pure number
    _ -> failure 64 (label <> " must be a positive integer: " <> value)

noLineBreaks :: String -> String -> IO ()
noLineBreaks label value = when (any (`elem` ['\n', '\r']) value) (failure 64 (label <> " may not contain line breaks"))

runCommand :: Int -> String -> [String] -> IO String
runCommand missing executable arguments = do
    (status, output, errors) <- readProcessWithExitCode executable arguments "" `catch` unavailable
    case status of
        ExitSuccess -> pure (trim output)
        ExitFailure code -> failure (if code == 127 then 69 else missing) (trimOr (executable <> " command failed") errors)
  where
    unavailable :: IOException -> IO (ExitCode, String, String)
    unavailable _ = failure 69 ("required command is unavailable: " <> executable)

tryCommand :: String -> [String] -> IO (ExitCode, String, String)
tryCommand executable arguments = readProcessWithExitCode executable arguments "" `catch` unavailable
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 ("required command is unavailable: " <> executable)

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

trimOr :: String -> String -> String
trimOr fallback value = let result = trim value in if null result then fallback else result

canonicalWorktree :: FilePath -> IO (FilePath, FilePath)
canonicalWorktree requested = do
    noLineBreaks "path" requested
    exists <- doesDirectoryExist requested
    unless exists (failure 66 ("worktree path does not exist: " <> requested))
    path <- canonicalizePath requested
    top <- runCommand 66 "git" ["-C", path, "rev-parse", "--show-toplevel"]
    canonicalTop <- canonicalizePath top
    unless (path == canonicalTop) (failure 64 ("path must be the worktree root: " <> path))
    commonRaw <- runCommand 66 "git" ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"]
    common <- canonicalizePath commonRaw
    pure (path, common)

currentWorktree :: IO (FilePath, FilePath)
currentWorktree = do
    current <- getCurrentDirectory
    canonicalWorktree current

loadRegistry :: FilePath -> Bool -> IO Registry
loadRegistry common allowMissing = do
    decoded <- readRegistry common
    registry <- case decoded of
        Left _ -> failure 65 ("malformed or foreign registry: " <> common </> registryFileRelativePath)
        Right Nothing | allowMissing -> pure Registry {commonGitDir = common, workspaces = []}
        Right Nothing -> failure 66 "epic worktree registry does not exist"
        Right (Just value) -> pure value
    either (const (failure 65 ("malformed or foreign registry: " <> common </> registryFileRelativePath))) pure (validateRegistry common registry)
    mapM_ validateRecordBranches (workspaces registry)
    pure registry

validateRecordBranches :: WorkspaceRecord -> IO ()
validateRecordBranches record = do
    validateStoredBranch (Text.unpack (recordBranch record))
    validateStoredBranch (Text.unpack (recordTargetBranch record))
  where
    validateStoredBranch branch = do
        (status, _, _) <- tryCommand "git" ["check-ref-format", "--branch", branch]
        unless (status == ExitSuccess) (failure 65 "registry contains an invalid branch")

identityFor :: WorkspaceRecord -> WorkspaceIdentity
identityFor record = WorkspaceIdentity
    { epic = recordEpic record, targetBranch = recordTargetBranch record, slot = recordSlot record }

recordStatus :: FilePath -> WorkspaceRecord -> IO WorkspaceStatus
recordStatus common record = do
    pathExists <- doesDirectoryExist (recordPath record)
    if not pathExists then pure Stale else do
        (topStatus, top, _) <- tryCommand "git" ["-C", recordPath record, "rev-parse", "--show-toplevel"]
        (commonStatus, actualCommon, _) <- tryCommand "git" ["-C", recordPath record, "rev-parse", "--path-format=absolute", "--git-common-dir"]
        (branchStatus, branch, _) <- tryCommand "git" ["-C", recordPath record, "symbolic-ref", "--quiet", "--short", "HEAD"]
        actualTop <- canonicalIfPresent (trim top)
        actualOwner <- canonicalIfPresent (trim actualCommon)
        if topStatus /= ExitSuccess || commonStatus /= ExitSuccess || branchStatus /= ExitSuccess
            || actualTop /= Just (recordPath record) || actualOwner /= Just common
            || trim branch /= Text.unpack (recordBranch record)
            then pure Stale
            else do
                let identityPath = recordPath record </> identityFileName
                exists <- doesFileExist identityPath
                if not exists then pure MissingIdentity else do
                    decoded <- readWorkspaceIdentity (recordPath record)
                    pure $ if decoded == Right (identityFor record) then Active else InconsistentIdentity

canonicalIfPresent :: FilePath -> IO (Maybe FilePath)
canonicalIfPresent "" = pure Nothing
canonicalIfPresent path = (Just <$> canonicalizePath path) `catch` handler
  where handler :: IOException -> IO (Maybe FilePath); handler _ = pure Nothing

statusText :: WorkspaceStatus -> String
statusText Active = "active"
statusText MissingIdentity = "missing-identity"
statusText InconsistentIdentity = "inconsistent-identity"
statusText Stale = "stale"

recordJson :: WorkspaceRecord -> WorkspaceStatus -> Aeson.Value
recordJson record status = case toJSON record of
    Aeson.Object fields -> Aeson.Object (fields <> KeyMap.fromList [("status", toJSON (statusText status))])
    value -> value

resolveCommand :: Options -> IO ()
resolveCommand options = do
    selector <- selectorFrom options
    lookupPath <- case selector of
        ByPath path -> pure path
        _ -> getCurrentDirectory
    (_, common) <- canonicalWorktree lookupPath
    registry <- loadRegistry common False
    selected <- selectRecords selector registry
    when (null selected) (failure 66 "no registered epic workspace matched")
    records <- traverse (\record -> do status <- recordStatus common record; pure (record, status)) selected
    let values = map (uncurry recordJson) records
    if flag "--json" options
        then case (selector, values) of
            (All, _) -> printJson values
            (_, value:_) -> printJson value
            (_, []) -> failure 66 "no registered epic workspace matched"
        else mapM_ printResolved records

selectorFrom :: Options -> IO Selector
selectorFrom options = do
    let present = [(name, value) | (name, value) <- optionValues options, name `elem` ["--epic", "--branch", "--path"]]
        count = length present + if flag "--all" options then 1 else 0
    when (count > 1) (failure 64 "resolve accepts only one selector")
    case (flag "--all" options, present) of
        (True, _) -> pure All
        (_, [("--epic", value)]) -> ByEpic <$> positive "epic" value
        (_, [("--branch", value)]) -> noLineBreaks "workspace branch" value >> pure (ByBranch value)
        (_, [("--path", value)]) -> do (path, _) <- canonicalWorktree value; pure (ByPath path)
        _ -> do (path, _) <- currentWorktree; pure (ByPath path)

selectRecords :: Selector -> Registry -> IO [WorkspaceRecord]
selectRecords selector registry = pure $ filter matches (workspaces registry)
  where
    matches record = case selector of
        All -> True
        ByEpic number -> recordEpic record == number
        ByBranch branch -> recordBranch record == Text.pack branch
        ByPath path -> recordPath record == path

printResolved :: (WorkspaceRecord, WorkspaceStatus) -> IO ()
printResolved (record, status) = putStrLn $
    "epic #" <> show (recordEpic record) <> " | epic | slot " <> show (recordSlot record)
    <> " | " <> Text.unpack (recordBranch record) <> " -> " <> Text.unpack (recordTargetBranch record)
    <> " | " <> statusText status <> " | " <> recordPath record

registerCommand :: Options -> IO ()
registerCommand options = do
    number <- positive "epic" =<< required "--epic" options
    target <- required "--target" options
    noLineBreaks "target branch" target
    kind <- pure (maybe "epic" id (optional "--kind" options))
    unless (kind == "epic") (failure 64 ("unsupported workspace kind: " <> kind))
    requested <- maybe getCurrentDirectory pure (optional "--path" options)
    (path, common) <- canonicalWorktree requested
    actualBranch <- runCommand 64 "git" ["-C", path, "symbolic-ref", "--quiet", "--short", "HEAD"]
    branch <- pure (maybe actualBranch id (optional "--branch" options))
    unless (branch == actualBranch) (failure 65 ("workspace branch '" <> branch <> "' does not match checked-out branch '" <> actualBranch <> "'"))
    when (branch == target) (failure 64 "workspace branch and target branch must differ")
    validateGitBranch "target branch" target
    validateGitBranch "workspace branch" branch
    result <- withRegistryLock common $ do
        registry <- loadRegistry common True
        let conflicts = filter (\record -> recordEpic record == number || recordBranch record == Text.pack branch || recordPath record == path) (workspaces registry)
        case conflicts of
            [] -> do
                selectedSlot <- slotForRegistration path number target registry
                createRegistration common path registry WorkspaceRecord
                    { recordEpic = number, recordTargetBranch = Text.pack target, recordBranch = Text.pack branch
                    , recordPath = path, recordSlot = selectedSlot }
            [record] -> do
                unless (record == WorkspaceRecord number (Text.pack target) (Text.pack branch) path (recordSlot record)) $
                    failure 65 "registration conflicts with existing workspace"
                status <- recordStatus common record
                case status of
                    Active -> pure record
                    MissingIdentity -> writeWorkspaceIdentityUnlocked path (identityFor record) >> pure record
                    _ -> failure 65 "worktree identity conflicts with registry"
            _ -> failure 65 "epic, branch, or path resolve to conflicting registry entries"
    status <- recordStatus common result
    if flag "--json" options then printJson (recordJson result status) else printResolved (result, status)

createRegistration :: FilePath -> FilePath -> Registry -> WorkspaceRecord -> IO WorkspaceRecord
createRegistration common path registry record = do
    occupied <- doesPathExist (path </> identityFileName)
    if occupied
        then do
            existing <- readWorkspaceIdentity path `catch` unreadableIdentity
            unless (existing == Right (identityFor record)) $
                failure 65 "unregistered worktree already contains an epic identity"
        else writeWorkspaceIdentityUnlocked path (identityFor record) `catch` writeFailed
    let updated = registry {workspaces = sortOn recordSlot (record : workspaces registry)}
    writeRegistryUnlocked common updated `catch` publishFailed
    pure record
  where
    unreadableIdentity :: IOException -> IO (Either String WorkspaceIdentity)
    unreadableIdentity _ = failure 65 "unregistered worktree already contains an unreadable epic identity"
    writeFailed :: IOException -> IO (); writeFailed _ = failure 73 "cannot write worktree identity; registry unchanged"
    publishFailed :: IOException -> IO (); publishFailed _ = failure 73 "cannot publish workspace registry; identity retained for resumable retry"

slotForRegistration :: FilePath -> Int -> String -> Registry -> IO Int
slotForRegistration path number target registry = do
    exists <- doesPathExist (path </> identityFileName)
    if not exists then pure fallback else do
        decoded <- readWorkspaceIdentity path `catch` unreadable
        case decoded of
            Right identity | epic identity == number && targetBranch identity == Text.pack target
                && slot identity `notElem` used -> pure (slot identity)
            _ -> failure 65 "unregistered worktree already contains an epic identity"
  where
    used = map recordSlot (workspaces registry)
    fallback = firstFreeSlot used
    unreadable :: IOException -> IO (Either String WorkspaceIdentity)
    unreadable _ = failure 65 "unregistered worktree already contains an unreadable epic identity"

firstFreeSlot :: [Int] -> Int
firstFreeSlot = findFree 1
  where
    findFree candidate used
        | candidate `elem` used = findFree (candidate + 1) used
        | otherwise = candidate

validateGitBranch :: String -> String -> IO ()
validateGitBranch label branch = do
    (status, _, _) <- tryCommand "git" ["check-ref-format", "--branch", branch]
    unless (status == ExitSuccess) (failure 64 ("invalid " <> label <> ": " <> branch))

provisionCommand :: Options -> IO ()
provisionCommand options = do
    number <- positive "epic" =<< provisionRequired "--epic" options
    base <- provisionRequired "--base" options
    name <- provisionRequired "--name" options
    noLineBreaks "base ref" base
    validateGitBranch "base ref" base
    unless (validName name) (failure 64 ("name must be one or two lowercase kebab-case words: " <> name))
    (primary, common) <- currentWorktree
    primaryLine <- fmap (takeWhile (/= '\n')) $ runCommand 66 "git" ["-C", primary, "worktree", "list", "--porcelain"]
    let primaryListed = drop 9 primaryLine
    listed <- canonicalizePath primaryListed
    unless (primary == listed) (failure 65 ("provisioning must run from the primary checkout: " <> listed))
    identityExists <- doesPathExist (primary </> identityFileName)
    when identityExists (failure 65 "primary checkout unexpectedly contains epic identity")
    baseCommit <- runCommand 66 "git" ["-C", primary, "rev-parse", "--verify", "--end-of-options", base <> "^{commit}"]
    let namedBranch = "epic-" <> show number <> "-" <> name
        namedPath = normalise (takeDirectory primary </> takeFileName primary <> "-" <> name)
        legacyBranch = "epic-" <> show number
        legacyPath = normalise (takeDirectory primary </> takeFileName primary <> "-epic-" <> show number)
    validateStablePath namedPath
    initialRegistry <- loadRegistry common True
    (selectedBranch, selectedPath, existingRecord) <- case find ((== number) . recordEpic) (workspaces initialRegistry) of
        Just existing -> do
            let accepted = (recordBranch existing == Text.pack namedBranch && recordPath existing == namedPath)
                        || (recordBranch existing == Text.pack legacyBranch && recordPath existing == legacyPath)
            unless (accepted && recordTargetBranch existing == Text.pack base) $
                failure 65 "existing epic registration conflicts with requested workspace name"
            status <- recordStatus common existing
            unless (status == Active) (failure 65 "existing epic registration is not active")
            pure (Text.unpack (recordBranch existing), recordPath existing, Just existing)
        Nothing -> pure (namedBranch, namedPath, Nothing)
    case existingRecord of
        Just _ -> pure ()
        Nothing -> withRegistryLock common $ do
            current <- loadRegistry common True
            when (any ((== selectedPath) . recordPath) (workspaces current)) $
                failure 65 ("refusing existing path that is already registered to another epic: " <> selectedPath)
            when (any (conflictsWith number selectedBranch selectedPath) (workspaces current)) $
                failure 65 "registration conflicts with concurrently provisioned workspace"
            prepareWorktree primary common baseCommit selectedBranch selectedPath
    linkConfiguration primary selectedPath ".ghci"
    linkConfiguration primary selectedPath ".env"
    initializeWorktree selectedPath
    record <- case existingRecord of
        Just existing -> pure existing
        Nothing -> withRegistryLock common $ do
            current <- loadRegistry common True
            let conflicts = filter (conflictsWith number selectedBranch selectedPath) (workspaces current)
            case conflicts of
                [existing] | recordEpic existing == number
                    && recordTargetBranch existing == Text.pack base
                    && recordBranch existing == Text.pack selectedBranch
                    && recordPath existing == selectedPath -> pure existing
                [] -> do
                    selectedSlot <- slotForRegistration selectedPath number base current
                    createRegistration common selectedPath current WorkspaceRecord
                        { recordEpic = number, recordTargetBranch = Text.pack base, recordBranch = Text.pack selectedBranch
                        , recordPath = selectedPath, recordSlot = selectedSlot }
                _ -> failure 65 "registration conflicts with concurrently provisioned workspace"
    let report = object
            [ "epic" .= recordEpic record, "targetBranch" .= recordTargetBranch record, "baseCommit" .= baseCommit
            , "branch" .= recordBranch record, "path" .= recordPath record, "slot" .= recordSlot record
            , "appUrl" .= ("http://127.0.0.1:" <> show (8000 + 3 * recordSlot record))
            , "mailhogUrl" .= ("http://127.0.0.1:" <> show (8025 + recordSlot record)) ]
    if flag "--json" options then printJson report else do
        putStrLn ("epic #" <> show number <> " | slot " <> show (recordSlot record) <> " | " <> Text.unpack (recordBranch record) <> " @ " <> take 12 baseCommit <> " -> " <> base)
        putStrLn ("path: " <> recordPath record)
        putStrLn ("app: http://127.0.0.1:" <> show (8000 + 3 * recordSlot record))
        putStrLn ("mailhog: http://127.0.0.1:" <> show (8025 + recordSlot record))

conflictsWith :: Int -> String -> FilePath -> WorkspaceRecord -> Bool
conflictsWith number branch path record =
    recordEpic record == number || recordBranch record == Text.pack branch || recordPath record == path

provisionRequired :: String -> Options -> IO String
provisionRequired name options = maybe (failure 64 ("provisioning requires " <> name)) pure (lookup name (optionValues options))

validName :: String -> Bool
validName value = case splitDash value of
    [one] -> validWord one
    [one, two] -> validWord one && validWord two
    _ -> False
  where
    validWord [] = False
    validWord (first:rest) = isAsciiLower first && all (\character -> isAsciiLower character || isDigit character) rest
    splitDash input = case break (== '-') input of
        (first, []) -> [first]
        (first, _:rest) -> first : splitDash rest

prepareWorktree :: FilePath -> FilePath -> String -> String -> FilePath -> IO ()
prepareWorktree primary common baseCommit branch path = do
    symlink <- pathIsSymbolicLink path `catch` absent
    when symlink (failure 65 ("refusing symlink at stable sibling path: " <> path))
    exists <- doesPathExist path
    branchExists <- branchPresent primary branch
    when branchExists $ do
        ancestor <- commandSucceeds "git" ["-C", primary, "merge-base", "--is-ancestor", baseCommit, branch]
        unless ancestor (failure 65 ("existing epic branch does not descend from requested base ref: " <> branch))
    if exists
        then validateExisting `catch` rejectExisting
        else do
            listing <- runCommand 65 "git" ["-C", primary, "worktree", "list", "--porcelain"]
            when (branchCheckedOut branch listing) (failure 65 ("epic branch is already checked out at another path: " <> branch))
            if branchExists
                then runCommand 70 "git" ["-C", primary, "worktree", "add", "--quiet", path, branch] >> pure ()
                else runCommand 70 "git" ["-C", primary, "worktree", "add", "--quiet", "-b", branch, path, baseCommit] >> pure ()
  where
    absent :: IOException -> IO Bool
    absent errorValue = if isDoesNotExistError errorValue then pure False else throwIO errorValue
    validateExisting = do
        (actualPath, actualCommon) <- canonicalWorktree path
        actualBranch <- runCommand 65 "git" ["-C", actualPath, "symbolic-ref", "--quiet", "--short", "HEAD"]
        unless (actualPath == path && actualCommon == common && actualBranch == branch) $
            failure 65 ("refusing existing path that is not the expected epic worktree: " <> path)
    rejectExisting :: ToolError -> IO ()
    rejectExisting _ = failure 65 ("refusing existing path that is not the expected epic worktree: " <> path)

branchPresent :: FilePath -> String -> IO Bool
branchPresent root branch = commandSucceeds "git" ["-C", root, "show-ref", "--verify", "--quiet", "refs/heads/" <> branch]

commandSucceeds :: String -> [String] -> IO Bool
commandSucceeds executable arguments = do (status, _, _) <- tryCommand executable arguments; pure (status == ExitSuccess)

branchCheckedOut :: String -> String -> Bool
branchCheckedOut branch listing = ("branch refs/heads/" <> branch) `elem` lines listing

validateStablePath :: FilePath -> IO ()
validateStablePath path = do
    canonicalParent <- canonicalizePath (takeDirectory path)
    unless (canonicalParent </> takeFileName path == path) $
        failure 65 ("derived sibling path is not canonical: " <> path)
    symlink <- pathIsSymbolicLink path `catch` absent
    when symlink (failure 65 ("refusing symlink at stable sibling path: " <> path))
  where
    absent :: IOException -> IO Bool
    absent errorValue = if isDoesNotExistError errorValue then pure False else throwIO errorValue

linkConfiguration :: FilePath -> FilePath -> FilePath -> IO ()
linkConfiguration primary workspace name = do
    sourceExists <- doesFileExist (primary </> name)
    targetExists <- doesPathExist (workspace </> name)
    unless (not sourceExists || targetExists) $
        createFileLink (primary </> name) (workspace </> name) `catch` linkFailed
  where
    linkFailed :: IOException -> IO ()
    linkFailed errorValue
        | isAlreadyExistsError errorValue = pure ()
        | otherwise = failure 73 ("failed to link primary " <> name <> " into worktree: " <> workspace)

initializeWorktree :: FilePath -> IO ()
initializeWorktree path = do
    (allowStatus, _, _) <- tryCommand "direnv" ["allow", path]
    case allowStatus of
        ExitFailure code -> failure code ("direnv/Nix initialization failed for " <> path)
        ExitSuccess -> pure ()
    (initStatus, _, _) <- tryCommand "direnv" ["exec", path, "true"]
    case initStatus of
        ExitFailure code -> failure code ("direnv/Nix initialization failed for " <> path)
        ExitSuccess -> pure ()

type Configuration = [(String, String)]

field :: String -> Configuration -> String
field name values = fromMaybe "" (lookup name values)

infoCommand :: [String] -> IO ()
infoCommand arguments = do
    mode <- case arguments of
        [] -> pure "--human"
        [value] | value `elem` ["--human", "--json", "--shell"] -> pure value
        ["-h"] -> putStrLn "Usage: dev-workspace-info [--human|--json|--shell]" >> exitWith ExitSuccess
        ["--help"] -> putStrLn "Usage: dev-workspace-info [--human|--json|--shell]" >> exitWith ExitSuccess
        [value] -> failure 64 ("unknown info option: " <> value)
        _ -> failure 64 "info accepts at most one mode"
    values <- workspaceConfiguration
    case mode of
        "--shell" -> mapM_ (\(name, value) -> putStrLn ("export " <> name <> "=" <> shellQuote value)) values
        "--json" -> printJson (configurationJson values)
        _ -> putStrLn $ field "BEPIS_WORKSPACE_KIND" values <> " workspace | slot " <> field "BEPIS_WORKSPACE_SLOT" values
            <> " | app " <> field "APP_BASE_URL" values <> " | SMTP " <> field "SMTP_PORT" values
            <> " | MailHog " <> field "MAILHOG_BASE_URL" values <> " | Grafana :" <> field "IHP_ROSTER_DEV_GRAFANA_PORT" values
            <> " | OTLP :" <> field "IHP_ROSTER_DEV_OTLP_HTTP_PORT" values <> "\nstate: " <> field "DEVENV_AGENT_STATE_DIR" values
            <> "\npostgres: " <> field "PGHOST" values

workspaceConfiguration :: IO Configuration
workspaceConfiguration = do
    requested <- lookupEnv "BEPIS_WORKSPACE_REPO_ROOT" >>= maybe getCurrentDirectory pure
    (root, common) <- canonicalWorktree requested
    identityExists <- doesPathExist (root </> identityFileName)
    (kind, workspaceEpic, workspaceSlot) <- if identityExists
        then do
            registry <- loadRegistry common False
            case filter ((== root) . recordPath) (workspaces registry) of
                [record] -> do
                    status <- recordStatus common record
                    unless (status == Active) (failure 65 ("worktree does not have an active registry identity: " <> root))
                    pure ("epic", show (recordEpic record), recordSlot record)
                _ -> failure 65 ("worktree does not have an active registry identity: " <> root)
        else do
            listing <- runCommand 66 "git" ["-C", root, "worktree", "list", "--porcelain"]
            let firstLine = takeWhile (/= '\n') listing
            primary <- canonicalizePath (drop 9 firstLine)
            unless (root == primary) (failure 65 ("linked worktree is missing epic identity: " <> root))
            pure ("primary", "", 0)
    offsetText <- fromMaybe "0" <$> lookupEnv "BEPIS_WORKSPACE_PORT_OFFSET"
    offset <- case readMaybe offsetText of
        Just value | value >= (0 :: Int) && value <= 40000 -> pure value
        _ -> failure 64 "port offset must be an integer from 0 through 40000"
    workspaceId <- hashPrefix root
    stateConfigured <- lookupEnv "BEPIS_WORKSPACE_STATE_CONFIGURED"
    configuredRoot <- lookupEnv "BEPIS_WORKSPACE_REPO_ROOT"
    configuredState <- lookupEnv "DEVENV_AGENT_STATE_DIR"
    stateOverride <- lookupEnv "BEPIS_WORKSPACE_STATE_ROOT"
    configuredMarker <- maybe (pure False) (doesFileExist . (</> ".bepis-dev-runtime")) configuredState
    let (stateRoot, stateDir) = case (stateConfigured, configuredRoot, configuredState) of
            (Just "1", Just configured, Just selected) | configured == root && configuredMarker -> (fromMaybe "" stateOverride, selected)
            (_, _, Just selected) | selected /= root </> ".devenv" </> "agent" ->
                let absolute = if isAbsolute selected then normalise selected else normalise (root </> selected)
                in (absolute, absolute </> "workspace-" <> workspaceId)
            _ -> let selected = "/tmp/bepis-dev-runtime-" <> "UID" <> "-" <> workspaceId in (selected, selected)
    uid <- show <$> getEffectiveUserID
    let finalStateRoot = replaceUid uid stateRoot
        finalStateDir = replaceUid uid stateDir
    ensureNativeState finalStateDir root uid
    let appPort = 8000 + offset + 3 * workspaceSlot
        hooglePort = appPort + 2
    when (hooglePort > 65535) (failure 64 "port offset and workspace slot exceed the TCP port range")
    postgresMode <- fromMaybe "managed" <$> lookupEnv "DEV_POSTGRES_MODE"
    postgresOverride <- lookupEnv "DEV_POSTGRES_ROOT"
    let defaultPostgres = "/tmp/bepis-dev-postgres-" <> uid <> "-" <> workspaceId
        postgresRoot = fromMaybe defaultPostgres postgresOverride
    postgresSocket <- case postgresMode of
        "managed" -> do
            unless (isAbsolute postgresRoot && postgresRoot `notElem` unsafeRoots root) (failure 64 ("refusing unsafe development PostgreSQL root: " <> postgresRoot))
            rejectSymlinkPath postgresRoot
            pure (postgresRoot </> "socket")
        "external" -> do
            socket <- fromMaybe "" <$> lookupEnv "DEV_POSTGRES_SOCKET"
            unless (isAbsolute socket) (failure 64 "DEV_POSTGRES_MODE=external requires absolute DEV_POSTGRES_SOCKET")
            pure socket
        _ -> failure 64 "DEV_POSTGRES_MODE must be managed or external"
    let smtpPort = 1025 + offset + workspaceSlot
        mailhogPort = 8025 + offset + workspaceSlot
        appUrl = "http://127.0.0.1:" <> show appPort
        mailhogUrl = "http://127.0.0.1:" <> show mailhogPort
        otelName = if workspaceSlot == 0 then "ihp-roster-dev" else "ihp-roster-dev-epic-" <> workspaceEpic
        port base = show (base + offset + workspaceSlot)
        values =
            [ ("BEPIS_WORKSPACE_REPO_ROOT", root), ("BEPIS_WORKSPACE_KIND", kind), ("BEPIS_WORKSPACE_SLOT", show workspaceSlot)
            , ("BEPIS_WORKSPACE_EPIC", workspaceEpic), ("BEPIS_WORKSPACE_STATE_CONFIGURED", "1"), ("BEPIS_WORKSPACE_STATE_ROOT", finalStateRoot)
            , ("BEPIS_WORKSPACE_PORT_OFFSET", show offset), ("DEVENV_AGENT_STATE_DIR", finalStateDir), ("PORT", show appPort)
            , ("IHP_HOOGLE_PORT", show hooglePort), ("APP_BASE_URL", appUrl), ("BASE_URL", appUrl), ("PWCLI_BASE_URL", appUrl)
            , ("SMTP_HOST", "127.0.0.1"), ("SMTP_PORT", show smtpPort), ("MAILHOG_SMTP_PORT", show smtpPort)
            , ("MAILHOG_PORT", show mailhogPort), ("MAILHOG_BASE_URL", mailhogUrl), ("DEV_POSTGRES_MODE", postgresMode)
            , ("DEV_POSTGRES_ROOT", postgresRoot), ("DEV_POSTGRES_SOCKET", postgresSocket), ("PGHOST", postgresSocket)
            , ("DATABASE_URL", "postgresql:///app?host=" <> postgresSocket), ("BEPIS_WORKSPACE_OTEL_SERVICE_NAME", otelName)
            , ("IHP_ROSTER_DEV_TEMPO_PORT", port 3200), ("IHP_ROSTER_DEV_TEMPO_SERVER_GRPC_PORT", port 9095)
            , ("IHP_ROSTER_DEV_TEMPO_OTLP_GRPC_PORT", port 14317), ("IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT", port 14318)
            , ("IHP_ROSTER_DEV_OTLP_GRPC_PORT", port 4317), ("IHP_ROSTER_DEV_OTLP_HTTP_PORT", port 4318)
            , ("IHP_ROSTER_DEV_COLLECTOR_HEALTH_PORT", port 13133), ("IHP_ROSTER_DEV_GRAFANA_PORT", port 3300) ]
    when (read (field "IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT" values) > (65535 :: Int)) $
        failure 64 "port offset and workspace slot exceed the TCP port range"
    pure values

configurationJson :: Configuration -> Aeson.Value
configurationJson values = object
    [ "path" .= field "BEPIS_WORKSPACE_REPO_ROOT" values, "kind" .= field "BEPIS_WORKSPACE_KIND" values
    , "epic" .= optionalNumber (field "BEPIS_WORKSPACE_EPIC" values), "slot" .= number "BEPIS_WORKSPACE_SLOT"
    , "portOffset" .= number "BEPIS_WORKSPACE_PORT_OFFSET", "appPort" .= number "PORT", "hooglePort" .= number "IHP_HOOGLE_PORT"
    , "appUrl" .= field "APP_BASE_URL" values, "smtpPort" .= number "SMTP_PORT", "mailhogPort" .= number "MAILHOG_PORT"
    , "mailhogUrl" .= field "MAILHOG_BASE_URL" values, "stateDir" .= field "DEVENV_AGENT_STATE_DIR" values
    , "postgresMode" .= field "DEV_POSTGRES_MODE" values, "postgresRoot" .= field "DEV_POSTGRES_ROOT" values
    , "postgresSocket" .= field "PGHOST" values, "databaseUrl" .= field "DATABASE_URL" values
    , "otelServiceName" .= field "BEPIS_WORKSPACE_OTEL_SERVICE_NAME" values, "grafanaPort" .= number "IHP_ROSTER_DEV_GRAFANA_PORT"
    , "otlpHttpPort" .= number "IHP_ROSTER_DEV_OTLP_HTTP_PORT" ]
  where
    number name = read (field name values) :: Int
    optionalNumber "" = Nothing :: Maybe Int
    optionalNumber value = readMaybe value

hashPrefix :: String -> IO String
hashPrefix value = do
    (status, output, _) <- readProcessWithExitCode "sha256sum" [] value `catch` unavailable
    case status of ExitSuccess -> pure (take 12 output); ExitFailure _ -> failure 69 "sha256sum failed"
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 "required command is unavailable: sha256sum"

replaceUid :: String -> String -> String
replaceUid uid value = case breakOn "UID" value of
    Just (before, after) -> before <> uid <> after
    Nothing -> value

breakOn :: String -> String -> Maybe (String, String)
breakOn needle = search ""
  where
    search _ "" = Nothing
    search before rest | needle `isPrefixOf` rest = Just (reverse before, drop (length needle) rest)
    search before (character:rest) = search (character:before) rest

unsafeRoots :: FilePath -> [FilePath]
unsafeRoots root = ["/", "/tmp", "/var", "/var/tmp", "/run", "/run/user", root]

rejectSymlinkPath :: FilePath -> IO ()
rejectSymlinkPath requested = do
    absolute <- normalise <$> makeAbsolute requested
    unless (absolute == requested) (failure 73 ("state path must be canonical: " <> requested))
    inspect absolute
  where
    inspect "/" = pure ()
    inspect component = do
        symlink <- pathIsSymbolicLink component `catch` absent
        when symlink (failure 73 ("refusing symlinked state path component: " <> component))
        inspect (takeDirectory component)
    absent :: IOException -> IO Bool
    absent errorValue = if isDoesNotExistError errorValue then pure False else throwIO errorValue

ensureNativeState :: FilePath -> FilePath -> String -> IO ()
ensureNativeState stateDir root uid = do
    when (stateDir `elem` unsafeRoots root) (failure 64 ("refusing unsafe state directory: " <> stateDir))
    rejectSymlinkPath stateDir
    exists <- doesDirectoryExist stateDir
    unless exists $ createDirectoryIfMissing True stateDir
    owner <- runCommand 73 "stat" ["-c", "%u", stateDir]
    unless (owner == uid) (failure 73 ("state directory is not owned by uid " <> uid <> ": " <> stateDir))
    projectId <- hashPrefix root
    let marker = stateDir </> ".bepis-dev-runtime"
        expected = "bepis-dev-runtime-v1\nuid=" <> uid <> "\nproject=" <> projectId <> "\n"
    markerExists <- doesFileExist marker
    unless markerExists $ do
        entries <- filter (`notElem` [".", ".."]) <$> getDirectoryContents stateDir
        unless (null entries) (failure 73 ("refusing non-empty unowned state directory: " <> stateDir))
        writeFile marker expected
    actual <- readFile marker
    unless (actual == expected) (failure 73 ("state ownership marker does not match this checkout: " <> marker))
    setFileMode stateDir 0o700
    fsType <- runCommand 73 "stat" ["-f", "-c", "%T", stateDir]
    allowed <- lookupEnv "BEPIS_DEV_RUNTIME_ALLOW_NON_NATIVE"
    when (nonNative fsType && allowed /= Just "1") (failure 78 ("refusing " <> fsType <> " runtime state at " <> stateDir))
  where
    nonNative value = value `elem` ["virtiofs", "9p", "nfs", "nfs4", "cifs"] || "fuse" `isPrefixOf` value || "smb" `isPrefixOf` value

shellQuote :: String -> String
shellQuote value = "'" <> concatMap escape value <> "'"
  where escape '\'' = "'\\''"; escape character = [character]

printJson :: ToJSON value => value -> IO ()
printJson = LazyByteString.putStrLn . encode

failure :: Int -> String -> IO value
failure status = throwIO . ToolError status
