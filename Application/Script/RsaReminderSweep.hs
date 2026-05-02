module Application.Script.RsaReminderSweep where

import Application.Script.Prelude
import Application.StaffDocuments.Rsa
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (utctDay)

run :: Script
run = do
    today <- utctDay <$> getCurrentTime
    summary <- enqueueDueRsaReminderJobs today
    liftIO do
        TextIO.putStrLn ("RSA reminders due: " <> tshow summary.dueRsaReminderCount)
        TextIO.putStrLn ("RSA reminder jobs enqueued: " <> tshow summary.enqueuedRsaReminderCount)
        TextIO.putStrLn ("RSA reminder jobs already active: " <> tshow summary.existingRsaReminderCount)
