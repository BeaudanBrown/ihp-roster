{-# LANGUAGE ForeignFunctionInterface #-}

-- | Synchronous command ownership for artifact mutations. The caller retains
-- its lifecycle lock until the command's process group is stopped and reaped.
module Bepis.Tooling.Artifacts.Command (runOwnedCommand) where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, bracket, catch, mask, onException, uninterruptibleMask_)
import Control.Monad (filterM, unless, void)
import qualified Data.ByteString.Char8 as ByteString
import Data.Char (isDigit)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Foreign.C.Error (throwErrnoIfMinus1Retry)
import Foreign.C.Types (CInt (..))
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (listDirectory)
import System.Exit (ExitCode (..))
import System.IO.Error (isDoesNotExistError)
import System.Posix.Signals (Handler (Catch), Signal, installHandler, sigINT, sigKILL, sigTERM, signalProcessGroup)
import System.Posix.Types (ProcessID)
import System.Process (CreateProcess (create_group), createProcess, getPid, waitForProcess)
import Text.Read (readMaybe)

-- WNOWAIT keeps the direct child (and thus its process-group ID) reserved even
-- after it exits. Polling getProcessExitCode would reap that anchor too early.
foreign import ccall unsafe "bepis_artifact_child_exited"
    childExited :: CInt -> IO CInt

runOwnedCommand :: CreateProcess -> IO ExitCode
runOwnedCommand command = mask $ \restore -> do
    interrupted <- newIORef Nothing
    let record selected = atomicModifyIORef' interrupted $ \current ->
            (case current of Nothing -> Just selected; Just previous -> Just previous, ())
        install = do
            oldInt <- installHandler sigINT (Catch (record sigINT)) Nothing
            oldTerm <- installHandler sigTERM (Catch (record sigTERM)) Nothing
            pure (oldInt, oldTerm)
        restoreHandlers (oldInt, oldTerm) = do
            void (installHandler sigINT oldInt Nothing)
            void (installHandler sigTERM oldTerm Nothing)
    bracket install restoreHandlers $ \_ -> do
        (_, _, _, child) <- createProcess command { create_group = True }
        pid <- getPid child >>= maybe (ioError (userError "artifact command PID unavailable")) pure
        let cleanup = uninterruptibleMask_ $ do
                stopGroup pid sigTERM
                void (waitForProcess child)
            poll = do
                selected <- readIORef interrupted
                case selected of
                    Just signal -> pure (Just signal)
                    Nothing -> do
                        exited <- throwErrnoIfMinus1Retry "artifact command waitid" (childExited (fromIntegral pid))
                        if exited /= 0 then pure Nothing else threadDelay 20000 >> poll
        selected <- restore poll `onException` cleanup
        -- Even an exited leader may have left children behind. Keep the zombie
        -- anchor until cleanup completes so signals cannot target a reused PGID.
        uninterruptibleMask_ $ do
            stopGroup pid (maybe sigTERM id selected)
            status <- waitForProcess child
            latest <- readIORef interrupted
            pure $ case latest of
                Just signal | signal == sigINT -> ExitFailure 130
                Just _ -> ExitFailure 143
                Nothing -> status

stopGroup :: ProcessID -> Signal -> IO ()
stopGroup pid firstSignal = do
    live <- groupHasLiveMembers pid
    if not live then pure () else do
        signalProcessGroup firstSignal pid
        start <- getMonotonicTimeNSec
        let waitGrace = do
                remaining <- groupHasLiveMembers pid
                now <- getMonotonicTimeNSec
                if not remaining then pure ()
                else if now - start >= 2000000000 then do
                    signalProcessGroup sigKILL pid
                    waitDead
                else threadDelay 20000 >> waitGrace
            waitDead = do
                remaining <- groupHasLiveMembers pid
                unless (not remaining) (threadDelay 20000 >> waitDead)
        waitGrace

-- Linux native tooling: zombies cannot write outputs and do not delay cleanup.
-- Uninterruptible kernel tasks retain the lock until they actually terminate;
-- a deadline must never falsely claim that a writer has stopped.
groupHasLiveMembers :: ProcessID -> IO Bool
groupHasLiveMembers group = do
    entries <- filter (\name -> not (null name) && all isDigit name) <$> listDirectory "/proc"
    members <- filterM belongs entries
    pure (not (null members))
  where
    belongs name = do
        content <- (Just <$> ByteString.readFile ("/proc/" <> name <> "/stat")) `catch` vanished
        pure $ case content of
            Nothing -> False
            Just bytes -> case words (reverse (takeWhile (/= ')') (reverse (ByteString.unpack bytes)))) of
                state : _parent : processGroup : _ ->
                    state /= "Z" && state /= "X" && readMaybe processGroup == Just group
                _ -> False
    vanished :: IOException -> IO (Maybe ByteString.ByteString)
    vanished exception
        | isDoesNotExistError exception = pure Nothing
        | otherwise = ioError exception
