{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Epic.Orientation (EpicError (..), orient) where

import Bepis.Tooling.Workspace.State
import Control.Exception (Exception, IOException, catch, throwIO)
import Control.Monad (forM, unless)
import Data.Aeson (FromJSON (parseJSON), ToJSON, Value (Array), eitherDecodeStrict', encode, object, withObject, (.:), (.:?), (.!=), (.=))
import qualified Data.Aeson as Aeson
import Data.Aeson.Key (Key)
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy.Char8 as LazyByteString
import Data.Char (isDigit)
import Data.List (find, nub, sort, sortOn)
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import GHC.Generics (Generic)
import qualified Data.Vector as Vector
import System.Directory (canonicalizePath, getCurrentDirectory)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Text.Read (readMaybe)


data GhAssignee = GhAssignee { login :: Text.Text } deriving (Show, Generic)
instance FromJSON GhAssignee
instance ToJSON GhAssignee

data GhIssue = GhIssue
    { number :: Int
    , title :: Text.Text
    , state :: Text.Text
    , html_url :: Text.Text
    , assignees :: [GhAssignee]
    } deriving (Show, Generic)
instance FromJSON GhIssue where
    parseJSON = withObject "GhIssue" $ \value -> GhIssue
        <$> value .: "number" <*> value .: "title" <*> value .: "state"
        <*> value .: "html_url" <*> value .:? "assignees" .!= []
instance ToJSON GhIssue

data EpicError = EpicError Int String deriving (Show)
instance Exception EpicError

data IssueSummary = IssueSummary
    { summaryNumber :: Int
    , summaryTitle :: Text.Text
    , summaryUrl :: Text.Text
    , summaryAssignees :: [Text.Text]
    } deriving (Show)

summaryJson :: IssueSummary -> Value
summaryJson IssueSummary {summaryNumber, summaryTitle, summaryUrl, summaryAssignees} = object
    [ "number" .= summaryNumber, "title" .= summaryTitle, "url" .= summaryUrl
    , "assignees" .= summaryAssignees
    ]

orient :: Bool -> IO ()
orient jsonOutput = do
    root <- git ["rev-parse", "--show-toplevel"]
    canonicalRoot <- canonicalizePath root
    common <- canonicalizePath =<< git ["rev-parse", "--path-format=absolute", "--git-common-dir"]
    registry <- readRegistry common >>= either (const (failure 65 "malformed or foreign registry")) (maybe (failure 66 "epic worktree registry does not exist") pure)
    either (const (failure 65 "malformed or foreign registry")) pure (validateRegistry common registry)
    record <- maybe (failure 66 "current worktree is not registered as an epic workspace") pure
        (find ((== canonicalRoot) . recordPath) (workspaces registry))
    identity <- readWorkspaceIdentity canonicalRoot >>= either (const (failure 65 "current epic worktree identity is stale or inconsistent")) pure
    unless (identity == WorkspaceIdentity (recordEpic record) (recordTargetBranch record) (recordSlot record))
        (failure 65 "current epic worktree identity is stale or inconsistent")
    branch <- git ["symbolic-ref", "--quiet", "--short", "HEAD"]
    unless (Text.pack branch == recordBranch record) (failure 65 "current epic worktree identity is stale or inconsistent")

    repository <- gh ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]
    unless (validRepository repository) (failure 65 "GitHub returned an invalid repository name")
    parent <- ghJson ["api", apiHeader, versionHeader, "repos/" <> repository <> "/issues/" <> show (recordEpic record)]
    unless (number parent == recordEpic record) (failure 65 "GitHub returned malformed parent issue state")
    children <- ghCollection ["api", "--paginate", "--slurp", apiHeader, versionHeader,
        "repos/" <> repository <> "/issues/" <> show (recordEpic record) <> "/sub_issues?per_page=100"]

    changes <- worktreeChanges canonicalRoot
    targetOid <- git ["rev-parse", Text.unpack (recordTargetBranch record) <> "^{commit}"]
    headOid <- git ["rev-parse", "HEAD"]
    ahead <- readInt =<< git ["rev-list", "--count", targetOid <> ".." <> headOid]
    commitText <- git ["log", "--format=%s%n%b", targetOid <> ".." <> headOid]
    let committed = committedIssueNumbers commitText
        openChildren = filter ((== "open") . state) children
    classified <- forM openChildren $ \child -> do
        blockers <- ghCollection ["api", "--paginate", "--slurp", apiHeader, versionHeader,
            "repos/" <> repository <> "/issues/" <> show (number child) <> "/dependencies/blocked_by?per_page=100"]
        let openBlockers = filter ((== "open") . state) blockers
            reasons = ["committed-work-awaiting-resolution" | number child `elem` committed] :: [Text.Text]
            summary = IssueSummary (number child) (title child) (html_url child) (map login (assignees child))
        pure (summary, openBlockers, reasons)
    let ready = map summaryJson $ sortOn (\issue -> (not (null (summaryAssignees issue)), summaryNumber issue))
            [issue | (issue, blockers, reasons) <- classified, null blockers, null reasons]
        active = [mergeObject (summaryJson issue) ["reasons" .= reasons] | (issue, blockers, reasons) <- classified, null blockers, not (null reasons)]
        blocked = [mergeObject (summaryJson issue)
                    ["blockedBy" .= map blockerJson blockers] | (issue, blockers, _) <- classified, not (null blockers)]
        pending = sort [number child | child <- openChildren, number child `elem` committed]
        localInterrupted = not (all null [changeStaged changes, changeUnstaged changes, changeUntracked changes, changeConflicted changes])
        interrupted = localInterrupted || not (null pending)
        parentValue = object ["number" .= number parent, "title" .= title parent, "state" .= state parent, "url" .= html_url parent]
        workspaceValue = object
            [ "epic" .= recordEpic record, "targetBranch" .= recordTargetBranch record
            , "branch" .= recordBranch record, "path" .= recordPath record, "slot" .= recordSlot record
            , "kind" .= ("epic" :: Text.Text), "status" .= ("active" :: Text.Text)
            , "interrupted" .= interrupted, "pendingCommittedIssues" .= pending
            , "aheadOfTarget" .= ahead, "changes" .= changesJson changes
            ]
        result = object
            [ "epic" .= parentValue, "workspace" .= workspaceValue
            , "issues" .= object ["ready" .= ready, "activeInterrupted" .= active, "blocked" .= blocked]
            , "selection" .= object ["allowed" .= (state parent == "open" && not interrupted), "requiresUserChoice" .= False]
            , "workflowRules" .= workflowRules parent interrupted
            ]
    if jsonOutput then LazyByteString.putStrLn (encode result) else printHuman parent record ahead interrupted ready active blocked
  where
    apiHeader = "-H=Accept: application/vnd.github+json"
    versionHeader = "-H=X-GitHub-Api-Version: 2022-11-28"

workflowRules :: GhIssue -> Bool -> [Text.Text]
workflowRules parent interrupted
    | state parent /= "open" = ["Stop: the parent epic is closed; do not select or begin its remaining work."]
    | interrupted = ["Resolve the interrupted workspace work before selecting another issue."]
    | otherwise =
        [ "Select and begin the most appropriate ready issue unless the user retained control or a material decision needs input."
        , "Prefer unassigned ready work; before starting assigned work, confirm issue activity does not show another actor actively implementing it."
        , "Commit, present verification evidence, and close a completed sub-issue without routine confirmation."
        , "After closure, refresh orientation and continue with the next most appropriate ready issue by default."
        ]

data Changes = Changes
    { changeStaged :: [String], changeUnstaged :: [String]
    , changeUntracked :: [String], changeConflicted :: [String]
    }

worktreeChanges :: FilePath -> IO Changes
worktreeChanges root = Changes
    <$> gitNull root ["diff", "--cached", "--name-only", "-z"]
    <*> gitNull root ["diff", "--name-only", "-z"]
    <*> gitNull root ["ls-files", "--others", "--exclude-standard", "-z"]
    <*> gitNull root ["diff", "--name-only", "--diff-filter=U", "-z"]

changesJson :: Changes -> Value
changesJson Changes {changeStaged, changeUnstaged, changeUntracked, changeConflicted} = object
    [ "staged" .= changeStaged, "unstaged" .= changeUnstaged
    , "untracked" .= changeUntracked, "conflicted" .= changeConflicted
    ]

blockerJson :: GhIssue -> Value
blockerJson issue = object ["number" .= number issue, "title" .= title issue, "url" .= html_url issue]

mergeObject :: Value -> [(Key, Value)] -> Value
mergeObject (Aeson.Object fields) pairs = Aeson.Object (fields <> KeyMap.fromList pairs)
mergeObject value _ = value

printHuman :: GhIssue -> WorkspaceRecord -> Int -> Bool -> [Value] -> [Value] -> [Value] -> IO ()
printHuman parent record ahead interrupted ready active blocked = do
    putStrLn ("EPIC #" <> show (number parent) <> ": " <> Text.unpack (title parent) <> " [" <> Text.unpack (state parent) <> "]")
    putStrLn ("WORKSPACE: slot " <> show (recordSlot record) <> ", " <> Text.unpack (recordBranch record) <> " -> " <> Text.unpack (recordTargetBranch record) <> ", ahead " <> show ahead)
    if state parent /= "open"
        then putStrLn "STOP: the parent epic is closed; do not select new work from it." >> putStrLn "READY — unavailable because epic is closed"
        else if interrupted
            then putStrLn "STOP: interrupted workspace work must be resumed or resolved before choosing new work." >> putStrLn "READY — unavailable until interruption resolved"
            else putStrLn "READY — select the most appropriate issue"
    mapM_ (putIssue "  ") ready
    putStrLn "ACTIVE / INTERRUPTED"
    mapM_ (putIssue "  ") active
    putStrLn "BLOCKED"
    mapM_ (putIssue "  ") blocked
    unless (state parent /= "open" || interrupted) $ do
        putStrLn "Select and begin the most appropriate ready issue unless the user retained control or a material decision needs input."
        putStrLn "Prefer unassigned work; confirm an assigned issue has no active implementation before starting it."
        putStrLn "After implementation: verify, commit, present evidence, and close the completed sub-issue without routine confirmation."
        putStrLn "After closure: refresh orientation and continue with the next most appropriate ready issue by default."
  where
    putIssue prefix value = case eitherDecodeStrict' (LazyByteString.toStrict (encode value)) :: Either String IssueSummaryWire of
        Right issue -> putStrLn (prefix <> "#" <> show (wireNumber issue) <> " " <> Text.unpack (wireTitle issue)
            <> if null (wireAssignees issue) then "" else " [assigned: " <> Text.unpack (Text.intercalate ", " (wireAssignees issue)) <> "]")
        Left _ -> pure ()

data IssueSummaryWire = IssueSummaryWire { wireNumber :: Int, wireTitle :: Text.Text, wireAssignees :: [Text.Text] }
instance FromJSON IssueSummaryWire where
    parseJSON = withObject "IssueSummary" $ \value -> IssueSummaryWire <$> value .: "number" <*> value .: "title" <*> value .:? "assignees" .!= []

ghJson :: FromJSON value => [String] -> IO value
ghJson arguments = decodeOutput "GitHub returned malformed issue state" =<< ghRaw arguments

ghCollection :: [String] -> IO [GhIssue]
ghCollection arguments = do
    value <- decodeOutput "GitHub returned malformed paginated issue state" =<< ghRaw arguments
    case Aeson.fromJSON value of
        Aeson.Success issues -> pure issues
        Aeson.Error _ -> case value of
            Array outer -> concat <$> mapM decodePage (Vector.toList outer)
            _ -> failure 65 "GitHub returned malformed paginated issue state"
  where
    decodePage value = case Aeson.fromJSON value of
        Aeson.Success issues -> pure issues
        Aeson.Error _ -> failure 65 "GitHub returned malformed paginated issue state"

gh :: [String] -> IO String
gh = command 69 "gh"

ghRaw :: [String] -> IO String
ghRaw = command 69 "gh"

git :: [String] -> IO String
git arguments = do
    current <- getCurrentDirectory
    command 65 "git" (["-C", current] <> arguments)

gitNull :: FilePath -> [String] -> IO [String]
gitNull root arguments = splitNull <$> command 65 "git" (["-C", root] <> arguments)

command :: Int -> String -> [String] -> IO String
command failureStatus executable arguments = do
    (status, output, errors) <- readProcessWithExitCode executable arguments "" `catch` unavailable
    case status of
        ExitSuccess -> pure (trim output)
        ExitFailure _ -> failure failureStatus (if null (trim errors) then executable <> " command failed" else trim errors)
  where
    unavailable :: IOException -> IO (ExitCode, String, String)
    unavailable _ = failure 69 ("required command is unavailable: " <> executable)

decodeOutput :: FromJSON value => String -> String -> IO value
decodeOutput label output = either (const (failure 65 label)) pure (eitherDecodeStrict' (ByteString.pack output))

splitNull :: String -> [String]
splitNull value = filter (not . null) (go value)
  where
    go [] = []
    go input = let (item, rest) = break (== '\0') input in item : case rest of [] -> []; _:remaining -> go remaining

committedIssueNumbers :: String -> [Int]
committedIssueNumbers = sort . nub . mapMaybe readMarker . tails
  where
    tails [] = []
    tails value@(_:rest) = value : tails rest
    readMarker ('#':rest) = case span isDigit rest of
        (digits, _) | not (null digits) -> readMaybe digits
        _ -> Nothing
    readMarker _ = Nothing

validRepository :: String -> Bool
validRepository value = case break (== '/') value of
    (owner, '/':repository) -> valid owner && valid repository
    _ -> False
  where valid part = not (null part) && all (\character -> character `elem` (['A'..'Z'] <> ['a'..'z'] <> ['0'..'9'] <> "_.-")) part

readInt :: String -> IO Int
readInt value = case reads value of [(numberValue, "")] -> pure numberValue; _ -> failure 65 "Git returned malformed numeric state"

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

failure :: Int -> String -> IO value
failure status message = throwIO (EpicError status message)
