module Application.Script.XeroKeepaliveSweep where

import Application.Script.Prelude
import Application.Xero.Keepalive
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    summary <- enqueueDueXeroKeepaliveJobs
    liftIO do
        TextIO.putStrLn ("Xero keepalive due connections: " <> tshow summary.dueConnectionCount)
        TextIO.putStrLn ("Xero keepalive jobs enqueued: " <> tshow summary.enqueuedJobCount)
        TextIO.putStrLn ("Xero keepalive jobs already active: " <> tshow summary.existingJobCount)
