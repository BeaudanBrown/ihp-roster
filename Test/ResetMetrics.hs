{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- Process-local diagnostics. No SQL, scheduling or fixture cleanup ownership.
module Test.ResetMetrics (withResetMetrics, withResetSuite, measureReset) where

import Control.Concurrent (ThreadId, myThreadId)
import Control.Concurrent.MVar
import Control.Exception
import Control.Monad (void)
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Types (Pair)
import qualified Data.ByteString.Lazy as Bytes
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Clock (getMonotonicTimeNSec)
import Prelude
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Unsafe (unsafePerformIO)
import qualified System.Process as Process
import Text.Read (readMaybe)

data Counters = Counters !Integer !Integer !Integer !Integer

data ResetState = ResetState
    { threadSuites :: !(Map.Map ThreadId String)
    , totals       :: !(Map.Map (Maybe String) Counters)
    , overflow     :: !Bool
    }

type Recorder = (Set.Set String, MVar ResetState)

{-# NOINLINE activeRecorder #-}
activeRecorder :: IORef (Maybe Recorder)
activeRecorder = unsafePerformIO (newIORef Nothing)

withResetMetrics :: [String] -> IO a -> IO a
withResetMetrics labels action = do
    target <- lookupEnv "BEPIS_VERIFICATION_EVENTS"
    if maybe True null target || length labels > 256 || not (all validLabel labels)
        then action
        else bracket acquire release (const action)
  where
    acquire = do
        state <- newMVar (ResetState Map.empty Map.empty False)
        previous <- atomicModifyIORef' activeRecorder (\old -> (Just (Set.fromList labels, state), old))
        pure (previous, state)
    release (previous, state) = do
        writeIORef activeRecorder previous
        snapshot <- readMVar state
        void (try @IOException (publish snapshot))
    validLabel name = case name of
        first : rest -> isAsciiUpper first && length rest < 64
            && all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` (".-" :: String)) rest
        [] -> False

withResetSuite :: String -> IO a -> IO a
withResetSuite label action = do
    recorder <- readIORef activeRecorder
    case recorder of
        Just (labels, state) | Set.member label labels -> do
            thread <- myThreadId
            started <- getMonotonicTimeNSec
            bracket (enter state thread) (leave state thread started) (const action)
        _ -> action
  where
    enter state thread = modifyMVar state $ \snapshot ->
        let previous = Map.lookup thread (threadSuites snapshot)
        in if Map.size (threadSuites snapshot) >= 256 && previous == Nothing
            then pure (snapshot { overflow = True }, previous)
            else pure (snapshot { threadSuites = Map.insert thread label (threadSuites snapshot) }, previous)
    leave state thread started previous = do
        finished <- getMonotonicTimeNSec
        modifyMVar_ state $ \snapshot ->
            let Counters count failures resetDuration exampleDuration = Map.findWithDefault (Counters 0 0 0 0) (Just label) (totals snapshot)
                updated = Counters count failures resetDuration (exampleDuration + toInteger (finished - started))
            in pure snapshot
                { threadSuites = maybe (Map.delete thread) (Map.insert thread) previous (threadSuites snapshot)
                , totals = Map.insert (Just label) updated (totals snapshot)
                }

measureReset :: forall a. IO a -> IO a
measureReset action = do
    recorder <- readIORef activeRecorder
    case recorder of
        Nothing -> action
        Just (_, state) -> mask $ \restore -> do
            thread <- myThreadId
            started <- getMonotonicTimeNSec
            result <- try @SomeException (restore action)
            finished <- getMonotonicTimeNSec
            modifyMVar_ state $ \snapshot ->
                let label = Map.lookup thread (threadSuites snapshot)
                    Counters count failures duration exampleDuration = Map.findWithDefault (Counters 0 0 0 0) label (totals snapshot)
                    failed = either (const 1) (const 0) result
                    updated = Counters (count + 1) (failures + failed) (duration + toInteger (finished - started)) exampleDuration
                in pure snapshot { totals = Map.insert label updated (totals snapshot) }
            either throwIO pure result

counterFields :: Counters -> [Pair]
counterFields (Counters count failures duration exampleDuration) =
    [ "attempts" .= count, "failures" .= failures, "durationNanoseconds" .= duration
    -- Summed inclusive example callbacks, not reset time or whole-suite startup.
    , "exampleDurationNanoseconds" .= exampleDuration
    ]

publish :: ResetState -> IO ()
publish snapshot = do
    root <- lookupEnv "BEPIS_SCRIPTS_ROOT"
    scope <- maybe (Just 1) (readMaybe @Int) <$> lookupEnv "TEST_SHARD_INDEX"
    case (root, scope) of
        (Just scriptsRoot, Just shard) | shard >= 0 && shard <= 65535 -> do
            let report :: Value
                report = object
                    [ "schemaVersion" .= (2 :: Int)
                    , "scope" .= shard
                    , "overflow" .= overflow snapshot
                    , "suites" .= [object (("suite" .= label) : counterFields counters)
                                  | (Just label, counters) <- Map.toAscList (totals snapshot)]
                    , "unattributed" .= object (counterFields (Map.findWithDefault (Counters 0 0 0 0) Nothing (totals snapshot)))
                    ]
            Process.withCreateProcess
                ((Process.proc "python3" ["-S", scriptsRoot </> "../../../scripts/profiling/verification-measure.py", "reset-summary"])
                    { Process.std_in = Process.CreatePipe, Process.std_out = Process.NoStream
                    , Process.std_err = Process.Inherit, Process.close_fds = True })
                (\input _ _ process -> do
                    case input of
                        Just handle -> Bytes.hPut handle (encode report) >> hClose handle
                        Nothing -> pure ()
                    void (Process.waitForProcess process))
        _ -> pure ()
