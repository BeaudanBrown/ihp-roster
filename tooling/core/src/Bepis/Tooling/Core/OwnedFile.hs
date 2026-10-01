{-# LANGUAGE CApiFFI #-}
{-# LANGUAGE InterruptibleFFI #-}

module Bepis.Tooling.Core.OwnedFile
    ( tryWithExclusiveLock
    , withExclusiveLock
    , withSharedLock
    , writeFileAtomic
    ) where

import Control.Exception (bracket, bracketOnError, bracket_)
import qualified Data.ByteString as ByteString
import Foreign.C.Error (eAGAIN, eWOULDBLOCK, getErrno, throwErrno,
                        throwErrnoIfMinus1Retry_)
import Foreign.C.Types (CInt (CInt))
import Prelude
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (hClose, hFlush, openBinaryTempFile)
import System.IO.Error (catchIOError)
import System.Posix.Files (ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.IO (OpenFileFlags (cloexec, creat, nofollow), OpenMode (ReadWrite),
                        closeFd, defaultFileFlags, openFd)
import System.Posix.Types (Fd (Fd))

foreign import capi interruptible "sys/file.h flock" c_flock :: CInt -> CInt -> IO CInt

lockShared, lockExclusive, lockNonBlocking, lockUnlock :: CInt
lockShared = 1
lockExclusive = 2
lockNonBlocking = 4
lockUnlock = 8

-- | Hold a Linux advisory exclusive lock for exactly the supplied action.
-- The descriptor is close-on-exec, so an executed child cannot retain it.
withExclusiveLock :: FilePath -> IO a -> IO a
withExclusiveLock path action = do
    createDirectoryIfMissing True (takeDirectory path)
    bracket open closeFd $ \fd ->
        bracket_ (flock fd lockExclusive) (flock fd lockUnlock) action
  where
    open = openFd path ReadWrite defaultFileFlags
        { creat = Just (ownerReadMode `unionFileModes` ownerWriteMode)
        , cloexec = True
        , nofollow = True
        }
    flock (Fd fd) operation = throwErrnoIfMinus1Retry_ "flock" (c_flock fd operation)

-- | Hold a Linux advisory shared lock for exactly the supplied action.
-- Multiple cache users may coexist while an exclusive cleanup waits.
withSharedLock :: FilePath -> IO a -> IO a
withSharedLock path action = do
    createDirectoryIfMissing True (takeDirectory path)
    bracket open closeFd $ \fd ->
        bracket_ (flock fd lockShared) (flock fd lockUnlock) action
  where
    open = openFd path ReadWrite defaultFileFlags
        { creat = Just (ownerReadMode `unionFileModes` ownerWriteMode)
        , cloexec = True
        , nofollow = True
        }
    flock (Fd fd) operation = throwErrnoIfMinus1Retry_ "flock" (c_flock fd operation)

-- | Attempt a non-blocking exclusive lock. Nothing means another owner holds it.
tryWithExclusiveLock :: FilePath -> IO a -> IO (Maybe a)
tryWithExclusiveLock path action = do
    createDirectoryIfMissing True (takeDirectory path)
    bracket open closeFd $ \fd -> do
        acquired <- tryFlock fd (lockExclusive + lockNonBlocking)
        if not acquired then pure Nothing else Just <$> bracket_ (pure ()) (flock fd lockUnlock) action
  where
    open = openFd path ReadWrite defaultFileFlags
        { creat = Just (ownerReadMode `unionFileModes` ownerWriteMode)
        , cloexec = True
        , nofollow = True
        }
    flock (Fd fd) operation = throwErrnoIfMinus1Retry_ "flock" (c_flock fd operation)
    tryFlock (Fd fd) operation = do
        result <- c_flock fd operation
        if result == 0 then pure True else do
            errno <- getErrno
            if errno == eWOULDBLOCK || errno == eAGAIN
                then pure False
                else throwErrno "flock"

-- | Replace a regular owned file atomically using a temporary in its directory.
-- A failed write removes only its unpublished temporary; an existing target stays.
writeFileAtomic :: FilePath -> ByteString.ByteString -> IO ()
writeFileAtomic target contents = do
    let directory = takeDirectory target
    createDirectoryIfMissing True directory
    bracketOnError
        (openBinaryTempFile directory (takeFileName target <> ".tmp"))
        (\(temporary, handle) -> do
            catchIOError (hClose handle) (const (pure ()))
            catchIOError (removeFile temporary) (const (pure ())))
        (\(temporary, handle) -> do
            ByteString.hPut handle contents
            hFlush handle
            hClose handle
            renameFile temporary target)
