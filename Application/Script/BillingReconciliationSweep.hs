module Application.Script.BillingReconciliationSweep where

import Application.Billing.Reconciliation
import Application.Script.Prelude
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    summary <- enqueueBillingReconciliationSweep
    liftIO do
        TextIO.putStrLn ("Billing reconciliation eligible subscriptions: " <> tshow summary.eligibleSubscriptionCount)
        TextIO.putStrLn ("Billing reconciliation jobs enqueued: " <> tshow summary.enqueuedJobCount)
        TextIO.putStrLn ("Billing reconciliation jobs already active: " <> tshow summary.existingJobCount)
