module Application.Script.PublicHolidayRefreshSweep where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.PublicHolidays.Job
import Application.Script.Prelude
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    enqueueResult <- enqueuePublicHolidayRefreshJob Nothing
    liftIO do
        case enqueueResult of
            EnqueuedAppJob appJob ->
                TextIO.putStrLn ("Public holiday refresh job enqueued: " <> tshow appJob.id)
            ExistingActiveAppJob appJob ->
                TextIO.putStrLn ("Public holiday refresh job already active: " <> tshow appJob.id)
