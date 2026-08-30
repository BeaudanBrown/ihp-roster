module Application.Helper.Profiling.Runtime
    ( withDiagnosticProfilingRuntime
    ) where

import Application.Helper.Profiling (isRequestProfilingEnabled)
import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Exception (bracket)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import GHC.Stats (RTSStats (..), getRTSStats, getRTSStatsEnabled)
import IHP.Prelude
import System.IO (hFlush, stdout)

-- Run-level samples only. Request/query/message paths never collect RTS stats.
withDiagnosticProfilingRuntime :: IO a -> IO a
withDiagnosticProfilingRuntime action = do
    profilingEnabled <- isRequestProfilingEnabled
    statsEnabled <- getRTSStatsEnabled
    if profilingEnabled && statsEnabled
        then bracket startSampler stopSampler (const action)
        else action

startSampler :: IO ThreadId
startSampler = forkIO sampleForever

stopSampler :: ThreadId -> IO ()
stopSampler = killThread

sampleForever :: IO ()
sampleForever = forever do
    stats <- getRTSStats
    ByteString.putStrLn (LazyByteString.toStrict ("[diagnostic-runtime] " <> Aeson.encode (runtimeSample stats)))
    hFlush stdout
    threadDelay 1000000

runtimeSample :: RTSStats -> Aeson.Value
runtimeSample stats =
    Aeson.object
        [ "allocatedBytes" Aeson..= stats.allocated_bytes
        , "copiedBytes" Aeson..= stats.copied_bytes
        , "gcCount" Aeson..= stats.gcs
        , "majorGcCount" Aeson..= stats.major_gcs
        , "maxLiveBytes" Aeson..= stats.max_live_bytes
        , "maxMemInUseBytes" Aeson..= stats.max_mem_in_use_bytes
        , "mutatorCpuNs" Aeson..= stats.mutator_cpu_ns
        , "gcCpuNs" Aeson..= stats.gc_cpu_ns
        , "cpuNs" Aeson..= stats.cpu_ns
        , "elapsedNs" Aeson..= stats.elapsed_ns
        ]
