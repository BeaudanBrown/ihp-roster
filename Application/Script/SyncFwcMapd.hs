module Application.Script.SyncFwcMapd where

import Application.FwcMapd.Sync
import Application.Script.Prelude
import qualified Data.Text.IO as TextIO

run :: Script
run =
    runConfiguredMapdSync >>= \case
        Left errorMessage ->
            error (cs errorMessage)
        Right summary -> do
            liftIO do
                TextIO.putStrLn ("Synced FWC MAPD awards: " <> intercalate ", " (map tshow summary.syncedAwardFixedIds))
                TextIO.putStrLn ("Award rows: " <> tshow summary.fetchedAwardCount)
                TextIO.putStrLn ("Classification rows: " <> tshow summary.fetchedClassificationCount)
                TextIO.putStrLn ("Pay rate rows: " <> tshow summary.fetchedPayRateCount)
                TextIO.putStrLn ("Penalty rate rows: " <> tshow summary.fetchedPenaltyRateCount)
                TextIO.putStrLn ("Wage allowance rows: " <> tshow summary.fetchedWageAllowanceCount)
