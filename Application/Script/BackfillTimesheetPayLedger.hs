module Application.Script.BackfillTimesheetPayLedger where

import Application.Helper.TimesheetPayLedger (backfillApprovedTimesheetPayCalculations)
import Application.Operator.Error
import Application.Script.Prelude
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    result <- backfillApprovedTimesheetPayCalculations
    liftIO case result of
        Right count ->
            TextIO.putStrLn ("Immutable timesheet pay ledger backfill complete: " <> tshow count <> " entries")
        Left failures ->
            exitWithScriptError $
                ScriptOperationFailed
                    ( "immutable timesheet pay ledger backfill rolled back; affected entry IDs: "
                        <> Text.intercalate ", "
                            [ tshow entryId <> " (" <> reason <> ")"
                            | (entryId, reason) <- failures
                            ]
                    )
