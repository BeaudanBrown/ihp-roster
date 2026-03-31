module Application.Helper.LiveDemo
    ( incrementDashboardLiveDemoCount
    , readDashboardLiveDemoCount
    , resetDashboardLiveDemoCount
    ) where

import Data.IORef
import IHP.Prelude
import System.IO.Unsafe (unsafePerformIO)

dashboardLiveDemoCountRef :: IORef Int
dashboardLiveDemoCountRef = unsafePerformIO (newIORef 0)
{-# NOINLINE dashboardLiveDemoCountRef #-}

readDashboardLiveDemoCount :: IO Int
readDashboardLiveDemoCount = readIORef dashboardLiveDemoCountRef

incrementDashboardLiveDemoCount :: IO Int
incrementDashboardLiveDemoCount =
    atomicModifyIORef' dashboardLiveDemoCountRef \count ->
        let nextCount = count + 1
         in (nextCount, nextCount)

resetDashboardLiveDemoCount :: IO ()
resetDashboardLiveDemoCount = writeIORef dashboardLiveDemoCountRef 0
