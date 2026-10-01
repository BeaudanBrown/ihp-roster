module Main (main) where

import Bepis.Tooling.Core.OwnedFile (tryWithExclusiveLock, withExclusiveLock, withSharedLock, writeFileAtomic)
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, throwIO, try)
import qualified Data.ByteString.Char8 as ByteString
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure))
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createProcess, proc)

main :: IO ()
main = do
    arguments <- getArgs
    case arguments of
        ["--hold-lock", lockPath, readyPath, microseconds] ->
            withExclusiveLock lockPath $ do
                writeFileAtomic readyPath (ByteString.pack "ready\n")
                threadDelay (read microseconds)
        ["--spawn-child", lockPath, readyPath] ->
            withExclusiveLock lockPath $ do
                writeFileAtomic readyPath (ByteString.pack "ready\n")
                _ <- createProcess (proc "sleep" ["2"])
                pure ()
        [] -> atomicWriteTest
        _ -> throwIO (ExitFailure 64)

atomicWriteTest :: IO ()
atomicWriteTest = withSystemTempDirectory "bepis-tooling-core" $ \root -> do
    let target = root </> "state" </> "owned.json"
        lock = root </> "state" </> "operation.lock"
    withExclusiveLock lock $ do
        unavailable <- tryWithExclusiveLock lock (pure ())
        case unavailable of
            Nothing -> pure ()
            Just () -> throwIO (ExitFailure 1)
    withSharedLock lock $ do
        unavailable <- tryWithExclusiveLock lock (pure ())
        case unavailable of
            Nothing -> withSharedLock lock (pure ())
            Just () -> throwIO (ExitFailure 1)
    failedLockAction <- try (withExclusiveLock lock (throwIO (ExitFailure 71))) :: IO (Either SomeException ())
    case failedLockAction of
        Left _ -> withExclusiveLock lock (pure ())
        Right _ -> throwIO (ExitFailure 1)
    writeFileAtomic target (ByteString.pack "first\n")
    writeFileAtomic target (ByteString.pack "second\n")
    actual <- ByteString.readFile target
    exists <- doesFileExist target
    if exists && actual == ByteString.pack "second\n"
        then pure ()
        else do
            hPutStrLn stderr "atomic write did not replace the complete target"
            throwIO (ExitFailure 1)
