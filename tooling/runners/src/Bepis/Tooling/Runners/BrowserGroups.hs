{-# LANGUAGE OverloadedStrings #-}

-- | Pure assignment policy only. Playwright owns discovery and execution;
-- the existing runner owns ports, processes, databases and failure retention.
module Bepis.Tooling.Runners.BrowserGroups (planBrowserGroups) where

import Control.Monad (unless, when)
import Data.Aeson (FromJSON (..), Value, eitherDecodeStrict', object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Aeson.Types (Parser)
import qualified Data.ByteString as ByteString
import Data.Char (isAlphaNum)
import Data.List (groupBy, minimumBy, nub, sort, sortOn)
import Data.Ord (Down (..), comparing)
import System.FilePath (isAbsolute, normalise, splitDirectories, takeExtension)

type Identity = (String, FilePath, String)
type GroupKey = (String, FilePath)
data Inventory = Inventory [Identity]
data Duration = Duration GroupKey Int Integer
data Durations = Durations [Duration]
data Group = Group GroupKey [String] Integer
data Shard = Shard Int Integer [Group]

instance FromJSON Inventory where
    parseJSON = withObject "Playwright inventory" $ \value -> do
        errors <- value .:? "errors" .!= ([] :: [Value])
        unless (null errors) (fail "Playwright discovery reported errors")
        config <- value .: "config"
        parallel <- config .:? "fullyParallel" .!= False
        when parallel (fail "whole-group policy requires fullyParallel=false")
        projects <- config .: "projects" >>= traverse parseProject
        unless (not (null projects) && length projects == length (nub projects)) (fail "invalid project membership")
        subjects <- (value .: "suites" :: Parser [Value]) >>= fmap concat . traverse parseSuite
        unless (all (\(project, _, _) -> project `elem` projects) subjects) (fail "unknown inventory project")
        pure (Inventory subjects)
      where
        parseProject = withObject "project" $ \project -> do
            name <- project .: "name"
            repeatEach <- project .:? "repeatEach" .!= (1 :: Int)
            dependencies <- project .:? "dependencies" .!= ([] :: [Value])
            unless (repeatEach == 1 && null dependencies) (fail "repeated/dependent projects require separate grouping proof")
            pure name

parseSuite :: Value -> Parser [Identity]
parseSuite = withObject "suite" $ \suite -> do
    specs <- suite .:? "specs" .!= [] >>= fmap concat . traverse parseSpec
    children <- suite .:? "suites" .!= [] >>= fmap concat . traverse parseSuite
    pure (specs <> children)
  where
    parseSpec = withObject "spec" $ \spec -> do
        identifier <- spec .: "id"
        file <- spec .: "file"
        tests <- spec .: "tests"
        unless (not (null tests)) (fail "spec without project tests")
        traverse (withObject "test" $ \test -> do
            project <- test .: "projectName"
            pure (project, file, identifier)) tests

instance FromJSON Durations where
    parseJSON = withObject "duration estimates" $ \value -> do
        version <- value .: "schemaVersion"
        unless (version == (1 :: Int)) (fail "unsupported duration schema")
        Durations <$> (value .: "groups" >>= traverse parseDuration)
      where
        parseDuration = withObject "duration group" $ \group -> do
            project <- group .: "project"
            file <- group .: "file"
            count <- group .: "testCount"
            milliseconds <- group .: "milliseconds"
            unless (count > 0 && count <= 10000 && milliseconds > 0 && milliseconds <= 86400000) (fail "invalid duration estimate")
            pure (Duration (project, file) count milliseconds)

-- Estimates affect placement, never membership or successful-result authority.
-- New groups receive 3s/test; changed counts scale the prior per-test estimate.
planBrowserGroups :: Int -> ByteString.ByteString -> ByteString.ByteString -> Either String Value
planBrowserGroups count inventoryBytes durationBytes = do
    unless (count >= 1 && count <= 8) (Left "browser group shards must be between 1 and 8")
    Inventory identities <- eitherDecodeStrict' inventoryBytes
    Durations durations <- eitherDecodeStrict' durationBytes
    unless (not (null identities) && length identities <= 10000) (Left "browser inventory must contain 1..10000 tests")
    unless (length identities == length (nub identities)) (Left "duplicate browser test identity")
    unless (all validIdentity identities) (Left "unsafe browser group identity")
    let durationKeys = [key | Duration key _ _ <- durations]
    unless (length durationKeys <= 10000 && length durationKeys == length (nub durationKeys) && all validKey durationKeys)
        (Left "invalid or duplicate duration group")
    let grouped = groupBy (\a b -> keyOf a == keyOf b) (sort identities)
        groups = map (makeGroup durations) grouped
    unless (length groups >= count) (Left "not enough whole groups for requested shards")
    let ordered = sortOn (\(Group key _ milliseconds) -> (Down milliseconds, key)) groups
        shards = foldl' assign [Shard index 0 [] | index <- [1..count]] ordered
    pure (object ["schemaVersion" .= (1 :: Int), "testCount" .= length identities,
        "groupCount" .= length groups, "shards" .= map renderShard shards])
  where
    keyOf (project, file, _) = (project, file)
    validIdentity (project, file, identifier) = validKey (project, file)
        && not (null identifier) && length identifier <= 512
        && all (\c -> c >= ' ' && c /= '\DEL') identifier
    validKey (project, file) = not (null project) && length project <= 128
        && all (\c -> isAlphaNum c || c `elem` ("._-" :: String)) project
        && not (null file) && length file <= 512 && not (isAbsolute file) && normalise file == file
        && all (`notElem` ["..", ".", ""]) (splitDirectories file)
        && takeExtension file `elem` [".ts", ".js", ".mts", ".mjs", ".cts", ".cjs", ".tsx", ".jsx"]
        && all (\c -> c > ' ' && c `notElem` (">›:\\[]\DEL" :: String)) file
    makeGroup estimates subjects@((project, file, _):_) =
        let key = (project, file)
            identifiers = sort [identifier | (_, _, identifier) <- subjects]
            size = toInteger (length subjects)
            estimate = case [ (oldCount, milliseconds) | Duration oldKey oldCount milliseconds <- estimates, oldKey == key ] of
                [(oldCount, milliseconds)] -> (milliseconds * size + toInteger oldCount - 1) `div` toInteger oldCount
                _ -> 3000 * size
        in Group key identifiers estimate
    makeGroup _ [] = error "groupBy produced an empty group"
    assign shards group@(Group _ _ milliseconds) =
        let Shard target _ _ = minimumBy (comparing (\(Shard index weight _) -> (weight, index))) shards
        in [if index == target then Shard index (weight + milliseconds) (group : groups) else shard
           | shard@(Shard index weight groups) <- shards]
    renderShard (Shard index milliseconds groups) =
        let ordered = sortOn (\(Group key _ _) -> key) groups
        in object ["index" .= index, "estimatedMilliseconds" .= milliseconds,
            "selectors" .= ["[" <> project <> "] › " <> file | Group (project, file) _ _ <- ordered],
            "groups" .= [object ["project" .= project, "file" .= file, "testIds" .= identifiers,
                "estimatedMilliseconds" .= duration] | Group (project, file) identifiers duration <- ordered]]
