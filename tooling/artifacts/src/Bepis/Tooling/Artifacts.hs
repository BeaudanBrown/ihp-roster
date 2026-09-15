{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Artifacts
    ( ArtifactError (..)
    , Manifest (..)
    , hashInventory
    , manifestCurrent
    , runArtifactsCommand
    ) where

import Bepis.Tooling.Core.OwnedFile (tryWithExclusiveLock, withExclusiveLock, withSharedLock, writeFileAtomic)
import Control.Exception (Exception, IOException, catch, throwIO)
import Data.Bits ((.&.))
import Control.Monad (filterM, forM, forM_, unless, when)
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), Value, eitherDecodeStrict', encode, object, withObject, (.:), (.=))
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString8
import qualified Data.ByteString.Lazy.Char8 as LazyByteString
import Data.List (isPrefixOf, sort, sortOn)
import System.Directory (canonicalizePath, copyFile, createDirectory, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, pathIsSymbolicLink, removeDirectoryRecursive, renameDirectory)
import System.Environment (getArgs, getEnvironment)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (isAbsolute, makeRelative, normalise, splitDirectories, takeDirectory, takeExtension, (</>))
import System.IO (hPutStrLn, stderr)
import System.Posix.Files (fileMode, fileOwner, fileSize, getFileStatus, ownerModes, setFileMode)
import System.Posix.User (getEffectiveUserID)
import System.Process (CreateProcess (cwd, env), createProcess, proc, readCreateProcessWithExitCode, waitForProcess)

newtype ArtifactError = ArtifactError (Int, String) deriving (Show)
instance Exception ArtifactError

data Manifest = Manifest { manifestInput :: String, manifestOutput :: String }
    deriving (Eq, Show)

instance ToJSON Manifest where
    toJSON Manifest {manifestInput, manifestOutput} = object
        ["version" .= (1 :: Int), "input" .= manifestInput, "output" .= manifestOutput]
instance FromJSON Manifest where
    parseJSON = withObject "Manifest" $ \value -> do
        version <- value .: "version"
        unless (version == (1 :: Int)) (fail "unsupported manifest version")
        Manifest <$> value .: "input" <*> value .: "output"

data Entry = FileEntry FilePath | ValueEntry String String deriving (Eq, Show)

data CacheOptions = CacheOptions
    { cacheAction :: String
    , cacheWorkspace :: FilePath
    , cacheParent :: FilePath
    , cacheApply :: Bool
    , cacheCommand :: [String]
    }

data CacheMarker = CacheMarker
    { cacheMarkerUid :: Int
    , cacheMarkerWorkspace :: FilePath
    , cacheMarkerWorkspaceId :: String
    } deriving (Eq, Show)

instance ToJSON CacheMarker where
    toJSON CacheMarker {cacheMarkerUid, cacheMarkerWorkspace, cacheMarkerWorkspaceId} = object
        [ "version" .= (1 :: Int), "uid" .= cacheMarkerUid, "workspace" .= cacheMarkerWorkspace
        , "workspaceId" .= cacheMarkerWorkspaceId ]
instance FromJSON CacheMarker where
    parseJSON = withObject "CacheMarker" $ \value -> do
        version <- value .: "version"
        unless (version == (1 :: Int)) (fail "unsupported cache marker version")
        CacheMarker <$> value .: "uid" <*> value .: "workspace" <*> value .: "workspaceId"

parseCache :: [String] -> IO CacheOptions
parseCache (action:arguments) | action `elem` ["prepare", "status", "clear", "stale", "exec"] =
    go arguments (CacheOptions action "" "" False [])
  where
    go ("--workspace":value:rest) options = go rest options {cacheWorkspace = value}
    go ("--parent":value:rest) options = go rest options {cacheParent = value}
    go ("--apply":rest) options = go rest options {cacheApply = True}
    go ("--":rest) options = validate options {cacheCommand = rest}
    go [] options = validate options
    go _ _ = failure 64 usage
    validate options = do
        unless (not (null (cacheParent options)) && (cacheAction options == "stale" || not (null (cacheWorkspace options))))
            (failure 64 "cache requires parent and workspace (except stale)")
        when (cacheAction options == "exec" && null (cacheCommand options)) (failure 64 "cache exec requires a command")
        when (cacheAction options /= "exec" && not (null (cacheCommand options))) (failure 64 "only cache exec accepts a command")
        when (cacheApply options && cacheAction options `notElem` ["clear", "stale"]) (failure 64 "--apply is valid only for clear and stale")
        pure options
parseCache _ = failure 64 usage

runCache :: CacheOptions -> IO ()
runCache options = case cacheAction options of
    "prepare" -> prepareCache options >>= printCacheStatus True
    "status" -> cachePaths options >>= cacheStatus >>= uncurry printCacheStatus
    "clear" -> cachePaths options >>= clearCache (cacheApply options) >>= LazyByteString.putStrLn . encode
    "stale" -> staleCaches options
    "exec" -> do
        paths <- cachePaths options
        ensureOwnedDirectory (cacheParent options)
        ensureOwnedDirectory (cacheParent options </> "locks")
        withSharedLock (cacheLifecycleLock paths) $ do
            prepared <- prepareCache options
            validateCacheRoot prepared
            environment <- filter ((`notElem` ["XDG_CACHE_HOME", "BEPIS_HLS_CACHE_PROTOCOL"]) . fst) <$> getEnvironment
            runCommandWithEnvironment (cacheWorkspace options) (("XDG_CACHE_HOME", cacheXdg prepared) : ("BEPIS_HLS_CACHE_PROTOCOL", "worktree-v1") : environment) (cacheCommand options)
    _ -> failure 64 usage

data CachePaths = CachePaths
    { cachePathWorkspace :: FilePath
    , cachePathId :: String
    , cachePathRoot :: FilePath
    , cacheXdg :: FilePath
    , cacheLifecycleLock :: FilePath
    }

cachePaths :: CacheOptions -> IO CachePaths
cachePaths options = do
    let workspace = cacheWorkspace options
        parent = cacheParent options
    unless (isAbsolute workspace && normalise workspace == workspace && workspace /= "/" && noBreaks workspace)
        (failure 64 "cache workspace must be an absolute canonical non-root path without line breaks")
    unless (isAbsolute parent && normalise parent == parent && parent /= "/" && noBreaks parent)
        (failure 64 "cache parent must be an absolute canonical non-root path without line breaks")
    rejectSymlinkComponents workspace
    rejectSymlinkComponents parent
    let identifier = take 12 (hex (hash (ByteString8.pack workspace)))
        root = parent </> identifier
    pure CachePaths {cachePathWorkspace = workspace, cachePathId = identifier, cachePathRoot = root,
        cacheXdg = root </> "xdg", cacheLifecycleLock = parent </> "locks" </> identifier <> ".lock"}
  where noBreaks value = '\n' `notElem` value && '\r' `notElem` value

rejectSymlinkComponents :: FilePath -> IO ()
rejectSymlinkComponents path = go "/" (filter (`notElem` ["/", ""]) (splitDirectories path))
  where
    go _ [] = pure ()
    go parent (part:rest) = do
        let selected = parent </> part
        symbolic <- pathIsSymbolicLink selected `catch` missing
        when symbolic (failure 65 ("path traverses a symlink: " <> selected))
        exists <- doesDirectoryExist selected
        when exists (go selected rest)
    missing :: IOException -> IO Bool
    missing _ = pure False

prepareCache :: CacheOptions -> IO CachePaths
prepareCache options = do
    paths <- cachePaths options
    ensureOwnedDirectory (cacheParent options)
    ensureOwnedDirectory (cacheParent options </> "locks")
    withExclusiveLock (cacheParent options </> "registry.lock") $ do
        rootExists <- doesDirectoryExist (cachePathRoot paths)
        if rootExists then validateCacheRoot paths else do
            createDirectoryIfMissing False (cachePathRoot paths)
            setFileMode (cachePathRoot paths) ownerModes
            uid <- fromIntegral <$> getEffectiveUserID
            publishCacheMarker paths (CacheMarker uid (cachePathWorkspace paths) (cachePathId paths))
        ensureOwnedDirectory (cacheXdg paths)
    pure paths

ensureOwnedDirectory :: FilePath -> IO ()
ensureOwnedDirectory path = do
    exists <- doesDirectoryExist path
    symbolic <- pathIsSymbolicLink path `catch` missingPath
    when symbolic (failure 65 ("owned directory is symlinked: " <> path))
    unless exists (createDirectoryIfMissing True path)
    status <- getFileStatus path
    uid <- getEffectiveUserID
    unless (fileOwner status == uid) (failure 65 ("owned directory belongs to another user: " <> path))
    setFileMode path ownerModes
  where missingPath :: IOException -> IO Bool; missingPath _ = pure False

publishCacheMarker :: CachePaths -> CacheMarker -> IO ()
publishCacheMarker paths marker = writeFileAtomic (cachePathRoot paths </> ".bepis-hls-cache")
    (LazyByteString.toStrict (encode marker))

validateCacheRoot :: CachePaths -> IO ()
validateCacheRoot paths = do
    validateMode (cachePathRoot paths)
    let markerPath = cachePathRoot paths </> ".bepis-hls-cache"
    symbolic <- pathIsSymbolicLink markerPath `catch` missingPath
    when symbolic (failure 65 "cache marker is symlinked")
    contents <- ByteString.readFile markerPath `catch` missingMarker
    let decoded = eitherDecodeStrict' contents
    uid <- fromIntegral <$> getEffectiveUserID
    let expected = CacheMarker uid (cachePathWorkspace paths) (cachePathId paths)
    unless (decoded == Right expected) (failure 65 "cache root has a foreign or malformed marker")
  where
    missingPath :: IOException -> IO Bool; missingPath _ = pure False
    missingMarker :: IOException -> IO ByteString.ByteString; missingMarker _ = failure 65 "cache root has no trusted marker"

validateMode :: FilePath -> IO ()
validateMode path = do
    symbolic <- pathIsSymbolicLink path
    when symbolic (failure 65 ("owned path is symlinked: " <> path))
    status <- getFileStatus path
    uid <- getEffectiveUserID
    unless (fileOwner status == uid && fileMode status .&. 0o777 == ownerModes)
        (failure 65 ("owned path has unsafe owner or mode: " <> path))

cacheStatus :: CachePaths -> IO (Bool, CachePaths)
cacheStatus paths = do
    exists <- doesDirectoryExist (cachePathRoot paths)
    if not exists then pure (False, paths) else do
        validateMode (takeDirectory (takeDirectory (cacheLifecycleLock paths)))
        validateMode (takeDirectory (cacheLifecycleLock paths))
        validateCacheRoot paths
        pure (True, paths)

printCacheStatus :: Bool -> CachePaths -> IO ()
printCacheStatus present paths = LazyByteString.putStrLn . encode =<< cacheStatusValue present paths

cacheStatusValue :: Bool -> CachePaths -> IO Value
cacheStatusValue present paths = do
    rootExists <- doesDirectoryExist (cachePathRoot paths)
    active <- if not present || not rootExists then pure False else do
        result <- tryWithExclusiveLock (cacheLifecycleLock paths) (pure ())
        pure (result == Nothing)
    bytes <- if present && rootExists then directoryBytes (cachePathRoot paths) else pure 0
    filesystem <- if not present || not rootExists then pure "absent" else cacheFilesystem (cachePathRoot paths)
    pure (object ["state" .= if present then ("present" :: String) else "absent",
        "root" .= cachePathRoot paths, "workspace" .= cachePathWorkspace paths, "workspaceId" .= cachePathId paths,
        "filesystem" .= filesystem, "bytes" .= bytes, "active" .= active, "xdg" .= cacheXdg paths,
        "lock" .= cacheLifecycleLock paths])

cacheFilesystem :: FilePath -> IO String
cacheFilesystem path = do
    (status, output, _) <- readCreateProcessWithExitCode (proc "stat" ["-f", "-c", "%T", path]) "" `catch` unavailable
    pure (if status == ExitSuccess then takeWhile (/= '\n') output else "unknown")
  where
    unavailable :: IOException -> IO (ExitCode, String, String)
    unavailable _ = pure (ExitFailure 1, "", "")

clearCache :: Bool -> CachePaths -> IO Value
clearCache apply paths = do
    (present, _) <- cacheStatus paths
    before <- cacheStatusValue present paths
    when (present && apply) $ do
        result <- tryWithExclusiveLock (cacheLifecycleLock paths) $ do
            validateCacheRoot paths
            removeDirectoryRecursive (cachePathRoot paths)
        when (result == Nothing) (failure 75 ("active process owns cache: " <> cachePathRoot paths))
    pure before

staleCaches :: CacheOptions -> IO ()
staleCaches options = do
    let parent = cacheParent options
    exists <- doesDirectoryExist parent
    if not exists then LazyByteString.putStrLn (encode (object ["caches" .= ([] :: [Value]), "applied" .= cacheApply options])) else do
        validateMode parent
        names <- listDirectory parent
        stale <- fmap concat $ forM names $ \name -> do
            let root = parent </> name
                markerPath = root </> ".bepis-hls-cache"
            isDirectory <- doesDirectoryExist root
            markerExists <- doesFileExist markerPath
            if not isDirectory || not markerExists || name == "locks" then pure [] else do
                decoded <- eitherDecodeStrict' <$> ByteString.readFile markerPath
                marker <- either (const (failure 65 ("malformed cache marker: " <> markerPath))) pure decoded
                let selected = options {cacheWorkspace = cacheMarkerWorkspace marker}
                paths <- cachePaths selected
                validateCacheRoot paths
                unless (cachePathRoot paths == root) (failure 65 ("cache marker identity mismatch: " <> root))
                workspaceExists <- doesDirectoryExist (cacheMarkerWorkspace marker)
                if workspaceExists then pure [] else do
                    status <- cacheStatusValue True paths
                    when (cacheApply options) $ do
                        _ <- clearCache True paths
                        pure ()
                    pure [status]
        LazyByteString.putStrLn (encode (object ["caches" .= stale, "applied" .= cacheApply options]))

directoryBytes :: FilePath -> IO Integer
directoryBytes root = do
    names <- listDirectory root
    sizes <- forM names $ \name -> do
        let path = root </> name
        symbolic <- pathIsSymbolicLink path
        when symbolic (failure 65 ("cache contains a symlink: " <> path))
        directory <- doesDirectoryExist path
        if directory then directoryBytes path else fromIntegral . fileSize <$> getFileStatus path
    pure (sum sizes)

data GenerateOptions = GenerateOptions
    { generateMode :: String
    , generateRoot :: FilePath
    , generateLock :: FilePath
    , generateManifest :: FilePath
    , inputCommand :: FilePath
    , outputCommand :: FilePath
    , generator :: [String]
    }

runArtifactsCommand :: IO ()
runArtifactsCommand = run `catch` handleError
  where
    handleError (ArtifactError (status, message)) = do
        putStrLnError ("bepis-artifacts: " <> message)
        exitWith (ExitFailure status)

run :: IO ()
run = getArgs >>= \case
    "snapshot" : "--root" : root : "--inventory-command" : command : [] ->
        putStrLn =<< inventorySnapshot root command
    "digest" : "--truncate" : count : values -> case reads count of
        [(lengthValue, "")] | lengthValue > 0 -> putStrLn (take lengthValue (digestValues values))
        _ -> failure 64 "digest truncation must be positive"
    "digest" : values | not (null values) -> putStrLn (digestValues values)
    "manifest" : "check" : path : inputHash : outputHash : [] -> do
        current <- manifestCurrent path inputHash outputHash
        if current then pure () else exitWith (ExitFailure 1)
    "manifest" : "publish" : path : inputHash : outputHash : [] ->
        publishManifest path (Manifest inputHash outputHash)
    "cache" : arguments -> parseCache arguments >>= runCache
    "generate" : arguments -> parseGenerate arguments >>= runGenerate
    "publish-managed" : arguments -> parsePublish arguments >>= runPublish
    "lock-exec" : arguments -> parseLockExec arguments >>= runLockExec
    _ -> failure 64 usage

usage :: String
usage = unlines
    [ "usage: bepis-artifacts snapshot --root ROOT --inventory-command COMMAND"
    , "       bepis-artifacts digest [--truncate N] VALUE..."
    , "       bepis-artifacts cache prepare|status|clear|stale --workspace PATH --parent PATH [--apply]"
    , "       bepis-artifacts cache exec --workspace PATH --parent PATH -- COMMAND [ARGS...]"
    , "       bepis-artifacts manifest check|publish PATH INPUT OUTPUT"
    , "       bepis-artifacts generate --mode ensure|sync --root ROOT --lock PATH --manifest PATH --input-command COMMAND --output-command COMMAND -- COMMAND [ARGS...]"
    , "       bepis-artifacts publish-managed --stage PATH --root PATH --managed-relative PATH --marker TEXT --recovery PATH -- VALIDATOR [ARGS...]"
    , "       bepis-artifacts lock-exec --lock PATH [--nonblocking] -- COMMAND [ARGS...]"
    ]

parseGenerate :: [String] -> IO GenerateOptions
parseGenerate arguments = go arguments (GenerateOptions "" "" "" "" "" "" [])
  where
    go ("--mode":value:rest) options = go rest options {generateMode = value}
    go ("--root":value:rest) options = go rest options {generateRoot = value}
    go ("--lock":value:rest) options = go rest options {generateLock = value}
    go ("--manifest":value:rest) options = go rest options {generateManifest = value}
    go ("--input-command":value:rest) options = go rest options {inputCommand = value}
    go ("--output-command":value:rest) options = go rest options {outputCommand = value}
    go ("--":rest) options = validate options {generator = rest}
    go _ _ = failure 64 usage
    validate options = do
        unless (generateMode options `elem` ["ensure", "sync"]) (failure 64 "generate mode must be ensure or sync")
        unless (all (not . null) [generateRoot options, generateLock options, generateManifest options, inputCommand options, outputCommand options])
            (failure 64 "generate requires root, lock, manifest, input command and output command")
        when (null (generator options)) (failure 64 "generate requires a generator command")
        pure options

runGenerate :: GenerateOptions -> IO ()
runGenerate options = withExclusiveLock (generateLock options) $ do
    root <- canonicalizePath (generateRoot options)
    inputBefore <- inventorySnapshot root (inputCommand options)
    outputBefore <- inventorySnapshot root (outputCommand options)
    current <- manifestCurrent (generateManifest options) inputBefore outputBefore
    if generateMode options == "ensure" && current
        then putStrLn "current"
        else do
            runCommand root (generator options)
            inputAfter <- inventorySnapshot root (inputCommand options)
            unless (inputAfter == inputBefore) (failure 75 "generation inputs changed while the generator was running; outputs retained without a success manifest")
            outputAfter <- requiredInventorySnapshot root (outputCommand options)
            publishManifest (generateManifest options) (Manifest inputAfter outputAfter)
            putStrLn "published"

data PublishOptions = PublishOptions
    { publishStage :: FilePath
    , publishRoot :: FilePath
    , managedRelative :: FilePath
    , generatedMarker :: String
    , recoveryRoot :: FilePath
    , validatorCommand :: [String]
    }

parsePublish :: [String] -> IO PublishOptions
parsePublish arguments = go arguments (PublishOptions "" "" "" "" "" [])
  where
    go ("--stage":value:rest) options = go rest options {publishStage = value}
    go ("--root":value:rest) options = go rest options {publishRoot = value}
    go ("--managed-relative":value:rest) options = go rest options {managedRelative = value}
    go ("--marker":value:rest) options = go rest options {generatedMarker = value}
    go ("--recovery":value:rest) options = go rest options {recoveryRoot = value}
    go ("--":rest) options = validate options {validatorCommand = rest}
    go _ _ = failure 64 usage
    validate options = do
        unless (all (not . null) [publishStage options, publishRoot options, managedRelative options,
            generatedMarker options, recoveryRoot options]) (failure 64 "publish-managed requires all path and marker options")
        when (null (validatorCommand options)) (failure 64 "publish-managed requires a validator command")
        unless (safeRelative (managedRelative options)) (failure 64 "managed-relative must be canonical and relative")
        pure options

runPublish :: PublishOptions -> IO ()
runPublish options = do
    stage <- canonicalizePath (publishStage options)
    root <- canonicalizePath (publishRoot options)
    stageFiles <- filter ((== ".hs") . takeExtension) <$> recursiveFiles stage
    when (null stageFiles) (failure 65 "staged managed set is empty")
    let relativeFiles = sort (map (makeRelative stage) stageFiles)
        managedPrefix = managedRelative options <> "/"
    unless (all (managedPrefix `isPrefixOf`) relativeFiles) (failure 65 "staged file escaped the managed subtree")
    before <- hashRelativeFiles stage relativeFiles
    validationStatus <- runCommandStatus root (validatorCommand options <> [stage] <> stageFiles)
    unless (validationStatus == ExitSuccess) $ do
        retainRecovery options stage relativeFiles
        failure 1 "staged managed set failed validation; recovery evidence retained"
    after <- hashRelativeFiles stage relativeFiles
    unless (after == before) $ do
        retainRecovery options stage relativeFiles
        failure 75 "staged files changed during validation; recovery evidence retained"
    uid <- getEffectiveUserID
    let target = root </> managedRelative options
        candidate = target <> ".publish-new"
        previous = target <> ".publish-old"
        publicationLockRoot = "/var/tmp/bepis-artifacts-" <> show uid
        publicationLock = publicationLockRoot </> ("publication-" <> take 24 (digestValues [target]) <> ".lock")
    ensureOwnedDirectory publicationLockRoot
    validatePublicationPath root (takeDirectory (managedRelative options))
    withExclusiveLock publicationLock $ do
        validatePublicationTarget target
        refuseRecoveryPath candidate
        refuseRecoveryPath previous
        currentFiles <- recursiveFiles target
        generatedCurrent <- filterM (hasMarker (generatedMarker options)) currentFiles
        let handwritten = filter (`notElem` generatedCurrent) currentFiles
        createDirectory candidate
        forM_ handwritten $ \source -> copyPublicationFile target candidate (makeRelative target source)
        forM_ relativeFiles $ \relative ->
            copyPublicationFile (stage </> managedRelative options) candidate (makeRelative (managedRelative options) relative)
        targetExists <- doesDirectoryExist target
        when targetExists (renameDirectory target previous)
        renameDirectory candidate target `catch` restorePrevious target previous targetExists
        when targetExists (removeDirectoryRecursive previous)
    putStrLn ("published " <> show (length relativeFiles))

validatePublicationTarget :: FilePath -> IO ()
validatePublicationTarget target = do
    symbolic <- pathIsSymbolicLink target `catch` missingPath
    when symbolic (failure 65 ("managed publication target is symlinked: " <> target))
    exists <- doesDirectoryExist target
    fileExists <- doesFileExist target
    when (fileExists && not exists) (failure 65 ("managed publication target is not a directory: " <> target))
  where
    missingPath :: IOException -> IO Bool
    missingPath _ = pure False

refuseRecoveryPath :: FilePath -> IO ()
refuseRecoveryPath path = do
    exists <- doesFileExist path
    directory <- doesDirectoryExist path
    symbolic <- pathIsSymbolicLink path `catch` missingPath
    when (exists || directory || symbolic) (failure 75 ("managed publication recovery state requires inspection: " <> path))
  where
    missingPath :: IOException -> IO Bool
    missingPath _ = pure False

copyPublicationFile :: FilePath -> FilePath -> FilePath -> IO ()
copyPublicationFile sourceRoot destinationRoot relative = do
    let source = sourceRoot </> relative
        destination = destinationRoot </> relative
    validatePublicationPath destinationRoot (takeDirectory relative)
    copyFile source destination

restorePrevious :: FilePath -> FilePath -> Bool -> IOException -> IO ()
restorePrevious target previous hadPrevious exception = do
    when hadPrevious (renameDirectory previous target `catch` retain)
    throwIO exception
  where
    retain :: IOException -> IO ()
    retain _ = pure ()

retainRecovery :: PublishOptions -> FilePath -> [FilePath] -> IO ()
retainRecovery options stage relativeFiles = do
    let recovery = recoveryRoot options
    createDirectoryIfMissing True recovery
    forM_ relativeFiles $ \relative -> do
        contents <- ByteString.readFile (stage </> relative)
        writeFileAtomic (recovery </> relative) contents

validatePublicationPath :: FilePath -> FilePath -> IO ()
validatePublicationPath root relative = go root (splitDirectories relative)
  where
    go _ [] = pure ()
    go parent (part:rest) = do
        let path = parent </> part
        exists <- doesDirectoryExist path
        symbolic <- pathIsSymbolicLink path `catch` missing
        when symbolic (failure 65 ("publication path traverses a symlink: " <> path))
        unless exists (createDirectoryIfMissing False path)
        go path rest
    missing :: IOException -> IO Bool
    missing _ = pure False

recursiveFiles :: FilePath -> IO [FilePath]
recursiveFiles root = do
    exists <- doesDirectoryExist root
    if not exists then pure [] else do
        names <- sort <$> listDirectory root
        fmap concat $ forM names $ \name -> do
            let path = root </> name
            symbolic <- pathIsSymbolicLink path
            when symbolic (failure 65 ("managed tree contains a symlink: " <> path))
            directory <- doesDirectoryExist path
            if directory then recursiveFiles path else do
                regular <- doesFileExist path
                pure [path | regular]

hasMarker :: String -> FilePath -> IO Bool
hasMarker marker path = do
    contents <- ByteString8.lines <$> ByteString.readFile path
    pure (ByteString8.pack marker `elem` contents)

hashRelativeFiles :: FilePath -> [FilePath] -> IO String
hashRelativeFiles root paths = hex . hash . ByteString.concat <$> mapM render paths
  where
    render path = do
        contents <- ByteString.readFile (root </> path)
        pure (ByteString8.pack (path <> "\0") <> contents <> "\0")

safeRelative :: FilePath -> Bool
safeRelative path = not (null path) && not (isAbsolute path) && normalise path == path
    && all (`notElem` ["..", "."]) (splitDirectories path)

parseLockExec :: [String] -> IO (FilePath, Bool, [String])
parseLockExec = go "" False
  where
    go _ _ [] = failure 64 usage
    go _ nonBlocking ("--lock":path:rest) = go path nonBlocking rest
    go path _ ("--nonblocking":rest) = go path True rest
    go path nonBlocking ("--":command) | not (null path) && not (null command) = pure (path, nonBlocking, command)
    go _ _ _ = failure 64 usage

runLockExec :: (FilePath, Bool, [String]) -> IO ()
runLockExec (lockPath, nonBlocking, command) = if nonBlocking
    then do
        result <- tryWithExclusiveLock lockPath (runCommand "" command)
        case result of Nothing -> failure 75 "another process owns the requested lock"; Just () -> pure ()
    else withExclusiveLock lockPath (runCommand "" command)

inventorySnapshot :: FilePath -> FilePath -> IO String
inventorySnapshot root command = do
    entries <- inventoryEntries root command
    hashInventory root entries

requiredInventorySnapshot :: FilePath -> FilePath -> IO String
requiredInventorySnapshot root command = do
    entries <- inventoryEntries root command
    missing <- filterM (fmap not . doesFileExist . (root </>)) [path | FileEntry path <- entries]
    unless (null missing) (failure 70 ("generator succeeded without required outputs: " <> show missing))
    hashInventory root entries

inventoryEntries :: FilePath -> FilePath -> IO [Entry]
inventoryEntries root command = do
    output <- commandOutput root command
    either (failure 65) pure (parseInventory output)

parseInventory :: String -> Either String [Entry]
parseInventory input = traverse parseLine (filter (not . null) (lines input))
  where
    parseLine line = case splitTabs line of
        ["path", path] | safeRelative path -> Right (FileEntry path)
        ["value", label, value] | not (null label) -> Right (ValueEntry label value)
        _ -> Left ("malformed inventory row: " <> line)

hashInventory :: FilePath -> [Entry] -> IO String
hashInventory root entries = hex . hash . ByteString.concat <$> mapM render (sortOn identity entries)
  where
    identity (FileEntry path) = "path\0" <> path
    identity (ValueEntry label value) = "value\0" <> label <> "\0" <> value
    render (ValueEntry label value) = pure (bytes ["value", label, value])
    render (FileEntry path) = do
        let absolute = root </> path
        exists <- doesFileExist absolute
        contents <- if exists then ByteString.readFile absolute else pure ""
        pure (bytes ["path", path, if exists then "present" else "missing"] <> contents <> "\0")
    bytes = ByteString8.pack . concatMap (<> "\0")

manifestCurrent :: FilePath -> String -> String -> IO Bool
manifestCurrent path inputHash outputHash = do
    exists <- doesFileExist path
    if not exists then pure False else do
        decoded <- eitherDecodeStrict' <$> ByteString.readFile path
        pure (decoded == Right (Manifest inputHash outputHash))

publishManifest :: FilePath -> Manifest -> IO ()
publishManifest path = writeFileAtomic path . LazyByteString.toStrict . encode

commandOutput :: FilePath -> FilePath -> IO String
commandOutput root command = do
    let process = (proc command []) {cwd = Just root}
    (status, output, errors) <- readCreateProcessWithExitCode process "" `catch` unavailable
    case status of
        ExitSuccess -> pure output
        ExitFailure _ -> failure 70 (if null errors then "inventory command failed" else trim errors)
  where
    unavailable :: IOException -> IO (ExitCode, String, String)
    unavailable _ = failure 69 ("required inventory command is unavailable: " <> command)

runCommand :: FilePath -> [String] -> IO ()
runCommand root command = do
    status <- runCommandStatus root command
    unless (status == ExitSuccess) (exitWith status)

runCommandWithEnvironment :: FilePath -> [(String, String)] -> [String] -> IO ()
runCommandWithEnvironment root environment (command:arguments) = do
    (_, _, _, processHandle) <- createProcess (proc command arguments) {cwd = Just root, env = Just environment}
        `catch` (\exception -> unavailable exception)
    status <- waitForProcess processHandle
    unless (status == ExitSuccess) (exitWith status)
  where
    unavailable :: IOException -> IO value
    unavailable _ = failure 69 ("required command is unavailable: " <> command)
runCommandWithEnvironment _ _ [] = failure 64 "missing command"

runCommandStatus :: FilePath -> [String] -> IO ExitCode
runCommandStatus root (command:arguments) = do
    let selectedCwd = if null root then Nothing else Just root
    (_, _, _, processHandle) <- createProcess (proc command arguments) {cwd = selectedCwd}
        `catch` (\exception -> unavailable exception)
    waitForProcess processHandle
  where
    unavailable :: IOException -> IO value
    unavailable _ = failure 69 ("required command is unavailable: " <> command)
runCommandStatus _ [] = failure 64 "missing command"

splitTabs :: String -> [String]
splitTabs [] = [""]
splitTabs value = let (field, rest) = break (== '\t') value in field : case rest of [] -> []; _:remaining -> splitTabs remaining

digestValues :: [String] -> String
digestValues = hex . hash . ByteString8.pack . concatMap (<> "\0")

hex :: ByteString.ByteString -> String
hex = concatMap byteHex . ByteString.unpack
  where
    digits = "0123456789abcdef"
    byteHex byte = [digits !! fromIntegral (byte `div` 16), digits !! fromIntegral (byte `mod` 16)]

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

putStrLnError :: String -> IO ()
putStrLnError = hPutStrLn stderr

failure :: Int -> String -> IO value
failure status message = throwIO (ArtifactError (status, message))
