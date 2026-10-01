{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Epic.Manage (manage) where

import Bepis.Tooling.Epic.Orientation (EpicError (..))
import Bepis.Tooling.Runtime.Process (Observation (..), RuntimeError, observeOwned, stopOwned)
import Bepis.Tooling.Workspace.Command (runtimeStateDirectoriesFor)
import Bepis.Tooling.Workspace.State
import Control.Exception (IOException, catch, throwIO)
import Control.Monad (forM, unless, void, when)
import Data.Aeson (FromJSON (parseJSON), Value, eitherDecodeStrict', encode, object, withObject, (.:), (.=))
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy.Char8 as LazyByteString
import Data.List (find, intercalate, isPrefixOf, isSuffixOf, nub)
import Data.Maybe (catMaybes)
import qualified Data.Text as Text
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getCurrentDirectory, listDirectory)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
import Text.Read (readMaybe)


newtype IssueState = IssueState String
instance FromJSON IssueState where
    parseJSON = withObject "IssueState" $ \value -> IssueState <$> value .: "state"

data Action = Preflight | Sync | Integrate | Cleanup deriving (Eq, Show)
data Options = Options
    { action :: Action, epicNumber :: Int, jsonOutput :: Bool, apply :: Bool, approve :: Bool
    , strategy :: String, integrationMode :: String
    }
data Context = Context
    { currentRoot :: FilePath, commonDir :: FilePath, record :: WorkspaceRecord
    , workspaceStatus :: String, targetPath :: Maybe FilePath
    }
data Snapshot = Snapshot
    { context :: Context, clean :: Bool, targetClean :: Maybe Bool
    , mergeBase :: String, epicOid :: String, targetOid :: String
    , epicAhead :: Int, targetAhead :: Int, conflicts :: Bool, conflictSummary :: String
    , epicFiles :: [FilePath], targetFiles :: [FilePath], migrations :: Bool, generated :: Bool
    , runtime :: RuntimeState
    }
data RebaseSafety = RebaseSafety
    { safetyEligible :: Bool, safetyChecked :: [(String, Int)], safetyPushed :: [(String, Int, String)] }
    deriving (Eq, Show)

data RuntimeEntry = RuntimeEntry { runtimePidFile :: FilePath, runtimeOwnerFile :: FilePath, runtimeLabel :: String, runtimePid :: Int }
data RuntimeState = RuntimeState { runtimeActive :: [RuntimeEntry], runtimeStale :: [FilePath], runtimeStateDirs :: [FilePath] }

manage :: [String] -> IO ()
manage arguments = do
    options <- parseOptions arguments
    contextValue <- loadContext (epicNumber options)
    case action options of
        Preflight -> outputSnapshot options =<< preflight contextValue
        Sync -> syncAction options contextValue
        Integrate -> integrateAction options contextValue
        Cleanup -> cleanupAction options contextValue

parseOptions :: [String] -> IO Options
parseOptions [] = failure 64 usage
parseOptions (actionText:rest) = do
    selectedAction <- case actionText of
        "preflight" -> pure Preflight; "sync" -> pure Sync; "integrate" -> pure Integrate; "cleanup" -> pure Cleanup
        _ -> failure 64 usage
    parsed <- go (Options selectedAction 0 False False False "merge" "no-ff") rest
    when (epicNumber parsed <= 0) (failure 64 (actionText <> " requires --epic"))
    when (action parsed /= Sync && apply parsed) (failure 64 "--apply is only valid for sync")
    when (action parsed `notElem` [Integrate, Cleanup] && approve parsed) (failure 64 "--approve is only valid for integrate or cleanup")
    when (action parsed /= Sync && strategy parsed /= "merge") (failure 64 "--strategy is only valid for sync")
    unless (strategy parsed `elem` ["merge", "rebase"]) (failure 64 ("sync strategy must be merge or rebase: " <> strategy parsed))
    when (action parsed /= Integrate && integrationMode parsed /= "no-ff") (failure 64 "--mode is only valid for integrate")
    unless (integrationMode parsed `elem` ["no-ff", "ff-only"]) (failure 64 ("integration mode must be no-ff or ff-only: " <> integrationMode parsed))
    pure parsed
  where
    go result [] = pure result
    go result ("--epic":value:remaining) = case readMaybe value of
        Just numberValue | numberValue > 0 -> go result {epicNumber = numberValue} remaining
        _ -> failure 64 ("epic must be a positive integer: " <> value)
    go result ("--json":remaining) = go result {jsonOutput = True} remaining
    go result ("--apply":remaining) = go result {apply = True} remaining
    go result ("--approve":remaining) = go result {approve = True} remaining
    go result ("--strategy":value:remaining) = go result {strategy = value} remaining
    go result ("--mode":value:remaining) = go result {integrationMode = value} remaining
    go _ (option:_) = failure 64 ("unknown option: " <> option)

usage :: String
usage = "Usage: bepis-epic-lifecycle manage preflight|sync|integrate|cleanup --epic NUMBER [--json] [--apply|--approve]"

loadContext :: Int -> IO Context
loadContext selectedEpic = do
    current <- canonicalizePath =<< gitCurrent ["rev-parse", "--show-toplevel"]
    common <- canonicalizePath =<< gitAt current ["rev-parse", "--path-format=absolute", "--git-common-dir"]
    registry <- readRegistry common >>= either (const malformed) (maybe (failure 66 "epic worktree registry does not exist") pure)
    either (const malformed) pure (validateRegistry common registry)
    workspace <- maybe (failure 66 ("cannot inspect epic #" <> show selectedEpic <> " registration")) pure
        (find ((== selectedEpic) . recordEpic) (workspaces registry))
    status <- workspaceRecordStatus common workspace
    target <- findBranchWorktree current (Text.unpack (recordTargetBranch workspace))
    pure Context {currentRoot = current, commonDir = common, record = workspace, workspaceStatus = status, targetPath = target}
  where malformed = failure 65 "malformed or foreign epic registry"

workspaceRecordStatus :: FilePath -> WorkspaceRecord -> IO String
workspaceRecordStatus common workspace = do
    exists <- doesDirectoryExist (recordPath workspace)
    if not exists then pure "stale" else do
        top <- tryGitAt (recordPath workspace) ["rev-parse", "--show-toplevel"]
        owner <- tryGitAt (recordPath workspace) ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        branch <- tryGitAt (recordPath workspace) ["symbolic-ref", "--quiet", "--short", "HEAD"]
        identity <- ifM (doesFileExist (recordPath workspace </> identityFileName))
            (readWorkspaceIdentity (recordPath workspace)) (pure (Left "missing"))
        pure $ if top == Right (recordPath workspace) && owner == Right common
                && branch == Right (Text.unpack (recordBranch workspace))
                && identity == Right (WorkspaceIdentity (recordEpic workspace) (recordTargetBranch workspace) (recordSlot workspace))
            then "active" else "inconsistent-identity"

findBranchWorktree :: FilePath -> String -> IO (Maybe FilePath)
findBranchWorktree root branch = do
    listing <- gitAt root ["worktree", "list", "--porcelain"]
    traverse canonicalizePath (findBranch (lines listing) Nothing)
  where
    findBranch [] _ = Nothing
    findBranch (line:rest) current
        | "worktree " `isPrefixOf` line = findBranch rest (Just (drop 9 line))
        | line == "branch refs/heads/" <> branch = current
        | otherwise = findBranch rest current

preflight :: Context -> IO Snapshot
preflight contextValue = do
    let workspace = record contextValue; path = recordPath workspace
        epicBranch = Text.unpack (recordBranch workspace); targetBranch = Text.unpack (recordTargetBranch workspace)
    unless (workspaceStatus contextValue == "active") (failure 65 ("epic #" <> show (recordEpic workspace) <> " registry identity is " <> workspaceStatus contextValue <> "; repair identity or use approved stale cleanup"))
    workspaceClean <- null <$> gitAt path ["status", "--porcelain=v1"]
    targetIsClean <- traverse (fmap null . flip gitAt ["status", "--porcelain=v1"]) (targetPath contextValue)
    selectedEpicOid <- gitAt (currentRoot contextValue) ["rev-parse", epicBranch <> "^{commit}"]
    selectedTargetOid <- gitAt (currentRoot contextValue) ["rev-parse", targetBranch <> "^{commit}"]
    base <- gitAt (currentRoot contextValue) ["merge-base", selectedTargetOid, selectedEpicOid]
    eAhead <- readNumber =<< gitAt (currentRoot contextValue) ["rev-list", "--count", selectedTargetOid <> ".." <> selectedEpicOid]
    tAhead <- readNumber =<< gitAt (currentRoot contextValue) ["rev-list", "--count", selectedEpicOid <> ".." <> selectedTargetOid]
    eFiles <- gitNullAt (currentRoot contextValue) ["diff", "--name-only", "-z", base <> ".." <> selectedEpicOid]
    tFiles <- gitNullAt (currentRoot contextValue) ["diff", "--name-only", "-z", base <> ".." <> selectedTargetOid]
    (hasConflicts, summary) <- predictConflicts contextValue selectedTargetOid selectedEpicOid
    runtimeValue <- inspectRuntime workspace
    let allFiles = nub (eFiles <> tFiles)
        migrationImpact = any (\file -> file == "Application/Schema.sql" || "Application/Migration/" `isPrefixOf` file) allFiles
        generatedImpact = any generatedPath allFiles
    pure Snapshot {context = contextValue, clean = workspaceClean, targetClean = targetIsClean,
        mergeBase = base, epicOid = selectedEpicOid, targetOid = selectedTargetOid,
        epicAhead = eAhead, targetAhead = tAhead, conflicts = hasConflicts, conflictSummary = summary,
        epicFiles = eFiles, targetFiles = tFiles, migrations = migrationImpact, generated = generatedImpact,
        runtime = runtimeValue}

predictConflicts :: Context -> String -> String -> IO (Bool, String)
predictConflicts contextValue target epic = withSystemTempDirectory "bepis-merge-tree" $ \temporary -> do
    let objectRoot = temporary </> "objects"; info = objectRoot </> "info"
    createDirectoryIfMissing True info
    writeFile (info </> "alternates") (commonDir contextValue </> "objects" <> "\n")
    environment <- getEnvironment
    (status, output, errors) <- readCreateProcessWithExitCode
        (proc "git" ["-C", currentRoot contextValue, "merge-tree", "--write-tree", "--name-only", target, epic])
            {env = Just (("GIT_OBJECT_DIRECTORY", objectRoot) : environment)} ""
    let summary = trim (output <> errors)
    case status of ExitSuccess -> pure (False, summary); ExitFailure 1 -> pure (True, summary); _ -> failure 70 ("cannot predict merge conflicts: " <> summary)

generatedPath :: FilePath -> Bool
generatedPath path = "build/Generated/" `isPrefixOf` path || "frontend/ts/generated/" `isPrefixOf` path
    || ("static/app" `isPrefixOf` path && suffix ".js" path) || "/Generated/" `contains` path
  where
    contains needle value = any (needle `isPrefixOf`) (tails value)
    tails [] = [[]]; tails value@(_:rest) = value : tails rest
    suffix ending value = ending `isSuffixOf` value

snapshotJson :: Snapshot -> Value
snapshotJson snapshot = object
    [ "epic" .= recordEpic workspace
    , "workspace" .= object ["slot" .= recordSlot workspace, "path" .= recordPath workspace, "branch" .= recordBranch workspace,
        "status" .= workspaceStatus contextValue, "clean" .= clean snapshot, "runtime" .= runtimeJson (runtime snapshot)]
    , "target" .= object ["branch" .= recordTargetBranch workspace, "path" .= targetPath contextValue, "clean" .= targetClean snapshot]
    , "divergence" .= object ["mergeBase" .= mergeBase snapshot, "epicOid" .= epicOid snapshot, "targetOid" .= targetOid snapshot,
        "epicAhead" .= epicAhead snapshot, "targetAhead" .= targetAhead snapshot]
    , "conflicts" .= object ["detected" .= conflicts snapshot, "summary" .= conflictSummary snapshot]
    , "impact" .= object ["epicFiles" .= epicFiles snapshot, "targetFiles" .= targetFiles snapshot,
        "migrations" .= migrations snapshot, "generatedFiles" .= generated snapshot]
    , "requiredChecks" .= requiredChecks snapshot
    , "generatedConflictPolicy" .= ("Resolve canonical source first, then regenerate generated files; never hand-merge generated output." :: String)
    , "parentClosure" .= ("separate-approval-required" :: String)
    ]
  where contextValue = context snapshot; workspace = record contextValue

requiredChecks :: Snapshot -> [String]
requiredChecks snapshot = nub (["typecheck", "hspec-test"]
    <> if migrations snapshot then ["regen-types"] else []
    <> if generated snapshot then ["frontend-check", "generated-code-sync"] else [])

runtimeJson :: RuntimeState -> Value
runtimeJson RuntimeState {runtimeActive, runtimeStale, runtimeStateDirs} = object
    [ "active" .= map entryJson runtimeActive, "stale" .= runtimeStale, "stateDirs" .= runtimeStateDirs ]
  where entryJson entry = object ["pidFile" .= runtimePidFile entry, "pid" .= runtimePid entry, "label" .= runtimeLabel entry]

outputSnapshot :: Options -> Snapshot -> IO ()
outputSnapshot options snapshot = if jsonOutput options then printJson (snapshotJson snapshot) else printSnapshot snapshot

printSnapshot :: Snapshot -> IO ()
printSnapshot snapshot = do
    let workspace = record (context snapshot)
    putStrLn ("epic #" <> show (recordEpic workspace) <> " | " <> Text.unpack (recordBranch workspace) <> " -> " <> Text.unpack (recordTargetBranch workspace)
        <> " | clean=" <> bool (clean snapshot) <> " | ahead=" <> show (epicAhead snapshot) <> " behind=" <> show (targetAhead snapshot) <> " | conflicts=" <> bool (conflicts snapshot))
    putStrLn ("runtime: active=" <> show (length (runtimeActive (runtime snapshot))) <> " stale=" <> show (length (runtimeStale (runtime snapshot))))
    putStrLn ("impact: migrations=" <> bool (migrations snapshot) <> " generated=" <> bool (generated snapshot))
    putStrLn ("checks: " <> comma (requiredChecks snapshot))
    putStrLn "parent closure: separate approval required"

syncAction :: Options -> Context -> IO ()
syncAction options contextValue = do
    snapshot <- preflight contextValue
    safety <- if strategy options == "rebase" then Just <$> rebaseSafety contextValue else pure Nothing
    case safety of Just value | not (safetyEligible value) -> failure 65 ("refusing to rebase pushed epic branch: " <> comma [remote <> ":" <> reference | (remote, _, reference) <- safetyPushed value]); _ -> pure ()
    if not (apply options)
        then outputAction options (object ["action" .= ("sync" :: String), "strategy" .= strategy options,
            "rebaseSafety" .= fmap safetyJson safety, "applied" .= False, "approval" .= ("rerun with --apply" :: String), "preflight" .= snapshotJson snapshot])
            (printSnapshot snapshot >> putStrLn ("sync strategy=" <> strategy options <> " not applied; rerun with --apply"))
        else do
            printSnapshot snapshot
            unless (clean snapshot) (failure 65 "refusing sync with uncommitted epic work")
            revalidate snapshot
            unless (null (runtimeActive (runtime snapshot))) (failure 65 "refusing sync while epic runtime has active processes")
            assertWorktree (recordPath (record contextValue)) (Text.unpack (recordBranch (record contextValue))) "epic"
            when (strategy options == "rebase") $ do
                currentSafety <- rebaseSafety contextValue
                unless (Just currentSafety == safety) (failure 65 "remote state changed after rebase planning; inspect again")
            when (targetAhead snapshot > 0) $ do
                let path = recordPath (record contextValue)
                if strategy options == "rebase"
                    then mutateGit path ["rebase", targetOid snapshot] "rebase stopped; resolve canonical source then continue, or abort"
                    else mutateGit path ["merge", "--no-edit", targetOid snapshot] "sync conflicts require canonical-source resolution followed by regeneration; do not hand-merge generated output"
            headOid <- gitAt (recordPath (record contextValue)) ["rev-parse", "HEAD"]
            outputAction options (object ["action" .= ("sync" :: String), "strategy" .= strategy options,
                "rebaseSafety" .= fmap safetyJson safety, "applied" .= True, "head" .= headOid, "preflight" .= snapshotJson snapshot])
                (putStrLn ("epic #" <> show (epicNumber options) <> " synchronized with " <> Text.unpack (recordTargetBranch (record contextValue)) <> " using " <> strategy options))

integrateAction :: Options -> Context -> IO ()
integrateAction options contextValue = do
    snapshot <- preflight contextValue
    if not (approve options)
        then outputAction options (object ["action" .= ("integrate" :: String), "applied" .= False,
            "approval" .= ("rerun with --approve" :: String), "mergeMode" .= ("--" <> integrationMode options),
            "parentClosure" .= ("separate" :: String), "preflight" .= snapshotJson snapshot])
            (printSnapshot snapshot >> putStrLn "integration not applied; rerun with --approve")
        else do
            printSnapshot snapshot
            unless (clean snapshot) (failure 65 "refusing integration with uncommitted epic work")
            unless (targetClean snapshot == Just True) (failure 65 "refusing integration with uncommitted target work")
            revalidate snapshot
            target <- maybe (failure 65 ("target branch must be checked out before integration: " <> Text.unpack (recordTargetBranch (record contextValue)))) pure (targetPath contextValue)
            unless (null (runtimeActive (runtime snapshot))) (failure 65 "refusing integration while epic runtime has active processes")
            when (conflicts snapshot) (failure 65 "refusing integration with predicted conflicts; sync and resolve first")
            assertWorktree (recordPath (record contextValue)) (Text.unpack (recordBranch (record contextValue))) "epic"
            assertWorktree target (Text.unpack (recordTargetBranch (record contextValue))) "target"
            ancestor <- gitSuccess (currentRoot contextValue) ["merge-base", "--is-ancestor", targetOid snapshot, epicOid snapshot]
            unless ancestor (failure 65 "epic is behind its target; run approved sync first")
            already <- gitSuccess (currentRoot contextValue) ["merge-base", "--is-ancestor", epicOid snapshot, targetOid snapshot]
            if already then finish target False else do
                if integrationMode options == "ff-only"
                    then mutateGit target ["merge", "--ff-only", epicOid snapshot] "approved fast-forward integration failed; inspect target movement"
                    else mutateGit target ["merge", "--no-ff", "--no-edit", "-m", "Merge epic #" <> show (epicNumber options), epicOid snapshot] "approved integration failed; inspect target worktree conflicts"
                finish target True
  where
    finish target appliedValue = do
        headOid <- gitAt target ["rev-parse", "HEAD"]
        outputAction options (object ["action" .= ("integrate" :: String), "applied" .= appliedValue,
            "head" .= headOid, "mergeMode" .= ("--" <> integrationMode options), "parentClosure" .= ("separate-approval-required" :: String)])
            (putStrLn ("epic #" <> show (epicNumber options) <> " integrated into " <> Text.unpack (recordTargetBranch (record contextValue)) <> "; parent closure still requires separate approval"))

cleanupAction :: Options -> Context -> IO ()
cleanupAction options contextValue = do
    let workspace = record contextValue; path = recordPath workspace; targetBranch = Text.unpack (recordTargetBranch workspace); epicBranch = Text.unpack (recordBranch workspace)
    when (workspaceStatus contextValue == "inconsistent-identity") (failure 65 "refusing cleanup with inconsistent epic identity")
    exists <- doesDirectoryExist path
    when exists $ do dirty <- fmap (not . null) (gitAt path ["status", "--porcelain=v1"]); when dirty (failure 65 "refusing cleanup with uncommitted work")
    target <- maybe (failure 65 "cleanup must run from the recorded target checkout") pure (targetPath contextValue)
    unless (currentRoot contextValue == target) (failure 65 "cleanup must run from the recorded target checkout")
    repository <- gh ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]
    parentResponse <- gh ["api", "repos/" <> repository <> "/issues/" <> show (epicNumber options)]
    parentState <- case eitherDecodeStrict' (ByteString.pack parentResponse) of
        Right (IssueState value) -> pure value
        Left _ -> failure 65 "GitHub returned malformed parent issue state"
    unless (parentState == "closed") (failure 65 ("refusing cleanup while parent epic #" <> show (epicNumber options) <> " is not closed"))
    branchExists <- gitSuccess (currentRoot contextValue) ["show-ref", "--verify", "--quiet", "refs/heads/" <> epicBranch]
    unless branchExists (failure 65 "cannot prove integration because the epic branch is missing; registry retained for recovery")
    integrated <- gitSuccess (currentRoot contextValue) ["merge-base", "--is-ancestor", epicBranch, targetBranch]
    unless integrated (failure 65 "refusing cleanup with unintegrated commits")
    runtimeValue <- inspectRuntime workspace
    let report = object ["action" .= ("cleanup" :: String), "applied" .= False, "epic" .= epicNumber options,
            "path" .= path, "branch" .= epicBranch, "targetBranch" .= targetBranch, "registryStatus" .= workspaceStatus contextValue,
            "runtime" .= runtimeJson runtimeValue, "termination" .= ("owned SIGTERM, bounded wait, then SIGKILL" :: String)]
    if not (approve options)
        then outputAction options report (putStrLn "cleanup safe but not applied; rerun with --approve")
        else do
            stopRuntime workspace runtimeValue
            remaining <- inspectRuntime workspace
            unless (null (runtimeActive remaining)) (failure 75 "epic runtime survived approved cleanup termination")
            pathProcesses <- processesInPath path
            unless (null pathProcesses) (failure 75 "worktree processes survived approved cleanup termination")
            hlsCommand <- lookupEnv "BEPIS_HLS_CACHE_COMMAND"
            void $ case hlsCommand of
                Just commandPath -> commandAt Nothing "bash" [commandPath, "clear", "--registered-path", path, "--apply", "--json"]
                Nothing -> commandAt Nothing "hls-cache" ["clear", "--registered-path", path, "--apply", "--json"]
            deleted <- withRegisteredWorkspaceCleanup (commonDir contextValue) workspace $ do
                assertWorktree target targetBranch "target"
                when exists (assertWorktree path epicBranch "epic")
                branchOid <- gitAt (currentRoot contextValue) ["rev-parse", "refs/heads/" <> epicBranch <> "^{commit}"]
                targetOid <- gitAt (currentRoot contextValue) ["rev-parse", "refs/heads/" <> targetBranch <> "^{commit}"]
                stillIntegrated <- gitSuccess (currentRoot contextValue) ["merge-base", "--is-ancestor", branchOid, targetOid]
                unless stillIntegrated (failure 65 "epic or target ref moved and integration can no longer be proved; registry retained")
                when exists (mutateGit (currentRoot contextValue) ["worktree", "remove", path] "failed to remove epic worktree metadata")
                mutateGit (currentRoot contextValue) ["update-ref", "-d", "refs/heads/" <> epicBranch, branchOid] "integrated branch deletion failed; registry retained for recovery"
            unless deleted (failure 70 "workspace registry changed; recovery metadata retained")
            remoteCleanup <- cleanupRemote contextValue epicBranch targetBranch
            outputAction options (object ["action" .= ("cleanup" :: String), "applied" .= True, "epic" .= epicNumber options,
                "path" .= path, "branch" .= epicBranch, "targetBranch" .= targetBranch, "registryStatus" .= workspaceStatus contextValue,
                "runtime" .= runtimeJson runtimeValue, "termination" .= ("owned SIGTERM, bounded wait, then SIGKILL" :: String), "remoteCleanup" .= remoteCleanup])
                (putStrLn ("epic #" <> show (epicNumber options) <> " worktree, local branch, and registry entry removed; remote=" <> remoteCleanup))

assertWorktree :: FilePath -> String -> String -> IO ()
assertWorktree path branch labelValue = do
    actualBranch <- gitAt path ["symbolic-ref", "--quiet", "--short", "HEAD"]
    unless (actualBranch == branch) (failure 65 (labelValue <> " worktree changed branches after preflight; inspect again before mutation"))
    dirty <- fmap (not . null) (gitAt path ["status", "--porcelain=v1"])
    when dirty (failure 65 (labelValue <> " worktree changed after preflight; inspect again before mutation"))

processesInPath :: FilePath -> IO [Int]
processesInPath path = do
    exists <- doesDirectoryExist path
    if not exists then pure [] else do
        expected <- canonicalizePath path
        entries <- listDirectory "/proc"
        fmap catMaybes $ forM entries $ \entry -> case readMaybe entry of
            Nothing -> pure Nothing
            Just pidValue -> do
                processCwd <- (Just <$> canonicalizePath ("/proc/" <> entry <> "/cwd")) `catch` missingCwd
                pure $ case processCwd of Just cwdValue | cwdValue == expected || (expected <> "/") `isPrefixOf` cwdValue -> Just pidValue; _ -> Nothing
  where missingCwd :: IOException -> IO (Maybe FilePath); missingCwd _ = pure Nothing

cleanupRemote :: Context -> String -> String -> IO String
cleanupRemote contextValue epicBranch targetBranch = do
    hasOrigin <- gitSuccess (currentRoot contextValue) ["remote", "get-url", "origin"]
    if not hasOrigin then pure "absent" else do
        queried <- tryGitAt (currentRoot contextValue) ["ls-remote", "--heads", "origin", "refs/heads/" <> epicBranch]
        case queried of
            Left _ -> pure "retained-query-failed"
            Right "" -> pure "absent"
            Right line -> do
                let remoteOid = takeWhile (not . (`elem` [' ', '\t'])) line
                    root = currentRoot contextValue
                objectAvailable <- gitSuccess root ["cat-file", "-e", remoteOid <> "^{commit}"]
                fetchSucceeded <- if objectAvailable then pure True else do
                    status <- commandAtStatus (Just root) "git" ["fetch", "--no-tags", "origin", "refs/heads/" <> epicBranch]
                    pure (status == ExitSuccess)
                if not fetchSucceeded then pure "retained-query-failed" else do
                    ancestor <- gitSuccess root ["merge-base", "--is-ancestor", remoteOid, targetBranch]
                    if not ancestor then pure "retained-unintegrated" else do
                        status <- commandAtStatus (Just root) "git" ["push", "--force-with-lease=refs/heads/" <> epicBranch <> ":" <> remoteOid, "origin", ":refs/heads/" <> epicBranch]
                        pure (if status == ExitSuccess then "deleted" else "retained-delete-failed")

revalidate :: Snapshot -> IO ()
revalidate snapshot = do
    let contextValue = context snapshot; workspace = record contextValue
    currentEpic <- gitAt (currentRoot contextValue) ["rev-parse", Text.unpack (recordBranch workspace) <> "^{commit}"]
    currentTarget <- gitAt (currentRoot contextValue) ["rev-parse", Text.unpack (recordTargetBranch workspace) <> "^{commit}"]
    unless (currentEpic == epicOid snapshot) (failure 65 "epic branch changed after preflight; inspect again before mutation")
    unless (currentTarget == targetOid snapshot) (failure 65 "target branch changed after preflight; inspect again before mutation")
    currentClean <- null <$> gitAt (recordPath workspace) ["status", "--porcelain=v1"]
    unless currentClean (failure 65 "epic worktree changed after preflight; inspect again before mutation")

rebaseSafety :: Context -> IO RebaseSafety
rebaseSafety contextValue = do
    remotes <- lines <$> gitAt (currentRoot contextValue) ["remote"]
    endpoints <- fmap nub $ fmap concat $ forM remotes $ \remote -> do
        fetch <- lines <$> gitAt (currentRoot contextValue) ["remote", "get-url", "--all", remote]
        push <- lines <$> gitAt (currentRoot contextValue) ["remote", "get-url", "--push", "--all", remote]
        pure [(remote, url) | url <- nub (fetch <> push), not (null url)]
    pushed <- fmap concat $ forM (zip [1..] endpoints) $ \(endpoint, (remote, url)) -> do
        output <- gitAt (currentRoot contextValue) ["ls-remote", "--heads", url, "refs/heads/" <> Text.unpack (recordBranch (record contextValue))]
        pure [(remote, endpoint, reference) | line <- lines output, let reference = dropWhile (/= 'r') line, not (null reference)]
    pure RebaseSafety {safetyEligible = null pushed, safetyChecked = [(remote, endpoint) | (endpoint, (remote, _)) <- zip [1..] endpoints], safetyPushed = pushed}

safetyJson :: RebaseSafety -> Value
safetyJson safety = object
    [ "eligible" .= safetyEligible safety
    , "checked" .= [object ["remote" .= remote, "endpoint" .= endpoint] | (remote, endpoint) <- safetyChecked safety]
    , "pushedTo" .= [object ["remote" .= remote, "endpoint" .= endpoint, "ref" .= reference] | (remote, endpoint, reference) <- safetyPushed safety]
    ]

inspectRuntime :: WorkspaceRecord -> IO RuntimeState
inspectRuntime workspace = do
    stateDirs <- runtimeDirs workspace
    entries <- fmap concat $ forM stateDirs $ \stateDir -> fmap catMaybes $ forM serviceLabels $ \labelValue -> do
        let pidFile = stateDir </> labelValue <> ".pid"; ownerFile = stateDir </> labelValue <> ".owner.json"
        exists <- doesFileExist pidFile
        if not exists then pure Nothing else do
            observation <- observeOwned pidFile ownerFile (recordPath workspace) labelValue `catch` invalidObservation
            pure $ if observedOwned observation then RuntimeEntry pidFile ownerFile labelValue <$> observedPid observation else Nothing
    stale <- fmap concat $ forM stateDirs $ \stateDir -> do
        exists <- doesDirectoryExist stateDir
        if not exists then pure [] else do
            files <- listDirectory stateDir
            pure [stateDir </> file | file <- files, suffix ".pid" file,
                all ((/= stateDir </> file) . runtimePidFile) entries]
    pure RuntimeState {runtimeActive = entries, runtimeStale = stale, runtimeStateDirs = stateDirs}
  where
    invalidObservation :: RuntimeError -> IO Observation
    invalidObservation _ = pure (Observation Nothing False False "invalid")
    suffix ending value = ending `isSuffixOf` value

runtimeDirs :: WorkspaceRecord -> IO [FilePath]
runtimeDirs = runtimeStateDirectoriesFor . recordPath

serviceLabels :: [String]
serviceLabels = ["devenv", "app", "worker", "frontend-watch", "frontend-generated-watch", "mailhog", "tempo", "otel-collector", "grafana", "stripe-listen"]

stopRuntime :: WorkspaceRecord -> RuntimeState -> IO ()
stopRuntime workspace stateValue = mapM_ stop (runtimeActive stateValue)
  where stop entry = do
            stopped <- stopOwned (runtimePidFile entry) (runtimeOwnerFile entry) (recordPath workspace) (runtimeLabel entry) 5000
            unless stopped (failure 75 (runtimeLabel entry <> " runtime ownership changed; retained state"))

outputAction :: Options -> Value -> IO () -> IO ()
outputAction options value human = if jsonOutput options then printJson value else human

printJson :: Value -> IO ()
printJson = LazyByteString.putStrLn . encode

mutateGit :: FilePath -> [String] -> String -> IO ()
mutateGit root arguments explanation = do
    (status, output, errors) <- readProcessWithExitCode "git" (["-C", root] <> arguments) "" `catch` unavailable
    unless (status == ExitSuccess) (failure (exitStatus status) (trim (output <> errors) <> "\nbepis-epic-lifecycle: " <> explanation))
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 "required command is unavailable: git"

gitAt :: FilePath -> [String] -> IO String
gitAt root arguments = commandAt (Just root) "git" arguments

gitCurrent :: [String] -> IO String
gitCurrent arguments = getCurrentDirectory >>= \root -> gitAt root arguments

tryGitAt :: FilePath -> [String] -> IO (Either String String)
tryGitAt root arguments = do
    (status, output, errors) <- readProcessWithExitCode "git" (["-C", root] <> arguments) "" `catch` unavailable
    pure $ case status of ExitSuccess -> Right (trim output); ExitFailure _ -> Left (trim errors)
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 "required command is unavailable: git"

gitSuccess :: FilePath -> [String] -> IO Bool
gitSuccess root arguments = do status <- commandAtStatus (Just root) "git" arguments; pure (status == ExitSuccess)

gitNullAt :: FilePath -> [String] -> IO [String]
gitNullAt root arguments = splitNull <$> gitAt root arguments

commandAt :: Maybe FilePath -> FilePath -> [String] -> IO String
commandAt cwdValue executable arguments = do
    (status, output, errors) <- readCreateProcessWithExitCode (proc executable arguments) {cwd = cwdValue} "" `catch` unavailable
    case status of ExitSuccess -> pure (trim output); ExitFailure code -> failure (if code == 127 then 69 else 65) (trimOr (executable <> " command failed") errors)
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 ("required command is unavailable: " <> executable)

commandAtStatus :: Maybe FilePath -> FilePath -> [String] -> IO ExitCode
commandAtStatus cwdValue executable arguments = do
    (status, _, _) <- readCreateProcessWithExitCode (proc executable arguments) {cwd = cwdValue} "" `catch` unavailable
    pure status
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = failure 69 ("required command is unavailable: " <> executable)

gh :: [String] -> IO String
gh = commandAt Nothing "gh"

splitNull :: String -> [String]
splitNull [] = []
splitNull input = let (item, rest) = break (== '\0') input in [item | not (null item)] <> case rest of [] -> []; _:remaining -> splitNull remaining

readNumber :: String -> IO Int
readNumber value = maybe (failure 65 "Git returned malformed numeric state") pure (readMaybe value)

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse
trimOr :: String -> String -> String
trimOr fallback value = if null (trim value) then fallback else trim value

comma :: [String] -> String
comma = intercalate ", "

bool :: Bool -> String
bool True = "true"
bool False = "false"

exitStatus :: ExitCode -> Int
exitStatus ExitSuccess = 0
exitStatus (ExitFailure status) = status

ifM :: Monad monad => monad Bool -> monad value -> monad value -> monad value
ifM condition yes no = condition >>= \value -> if value then yes else no

failure :: Int -> String -> IO value
failure status message = throwIO (EpicError status message)
