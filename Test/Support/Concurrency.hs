module Test.Support.Concurrency (runConcurrentActionsImmediately, runConcurrentActionsFromBarrier) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, try)
import Control.Monad (replicateM, void, zipWithM_)
import IHP.Prelude

runConcurrentActionsImmediately :: Int -> IO value -> IO [Either SomeException value]
runConcurrentActionsImmediately count action = do
    results <- replicateM count newEmptyMVar
    mapM_ (\result -> void (forkIO (try action >>= putMVar result))) results
    mapM takeMVar results

runConcurrentActionsFromBarrier :: [IO value] -> IO [Either SomeException value]
runConcurrentActionsFromBarrier actions = do
    results <- mapM (const newEmptyMVar) actions
    ready <- mapM (const newEmptyMVar) actions
    start <- newEmptyMVar
    zipWithM_
        (\result (workerReady, action) -> forkIO do
            putMVar workerReady ()
            readMVar start
            try action >>= putMVar result
        )
        results
        (zip ready actions)
    mapM_ takeMVar ready
    putMVar start ()
    mapM takeMVar results
