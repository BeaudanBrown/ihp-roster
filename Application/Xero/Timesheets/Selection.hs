module Application.Xero.Timesheets.Selection
    ( fetchPreparationSelectionCandidates
    , savePreparationSelection
    ) where

import Application.Helper.TimesheetSelection
import Application.Helper.XeroTimesheetReadiness (XeroTimesheetReadinessRequest (..))
import Application.Xero.Timesheets.Prepare.Helpers (preparationReadinessRequest)
import Application.Xero.Timesheets.Preview (fetchPreviewInput, XeroTimesheetPreviewInput (..))
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

fetchPreparationSelectionCandidates :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> IO [TimesheetEntry]
fetchPreparationSelectionCandidates run =
    case preparationReadinessRequest run [] of
        Left _ -> pure []
        Right request -> do
            connection <- query @XeroConnection
                |> filterWhere (#id, Id run.xeroConnectionId)
                |> filterWhere (#venueId, run.venueId)
                |> filterWhere (#connectionStatus, "active")
                |> fetchOneOrNothing
            case connection of
                Nothing -> pure []
                Just connection -> (.previewTimesheetEntries) <$> fetchPreviewInput request { readinessSelection = AllEligible } connection

-- The caller has owner/support authorization; venue and stale-run checks remain
-- inside this write boundary. No selected set can leak into another preparation.
savePreparationSelection :: (?modelContext :: ModelContext) => Id Venue -> Id XeroTimesheetPreparationRun -> UTCTime -> TimesheetSelection -> IO (Either Text XeroTimesheetPreparationRun)
savePreparationSelection venueId runId expectedUpdatedAt selection = withTransaction do
    locked :: [Only UUID] <- unsafeSqlQuery
        "SELECT id FROM xero_timesheet_preparation_runs WHERE id = ? AND venue_id = ? FOR UPDATE"
        (unpackId runId, unpackId venueId)
    case locked of
        [] -> pure (Left "Preparation was not found for this venue.")
        _ -> do
            run <- fetch runId
            if run.updatedAt /= expectedUpdatedAt || isJust run.completedAt || isJust run.xeroSubmissionRunId
                then pure (Left "Preparation changed. Reopen Choose shifts and review again.")
                else case (run.payPeriodStart, run.payPeriodEnd, selection) of
                    (Just start, Just end, ExplicitSelection _) -> do
                        candidates <- fetchPreparationSelectionCandidates run
                        case validateTimesheetSelection run.venueId start end selection candidates of
                            Left failure -> pure (Left (renderTimesheetSelectionFailure failure))
                            Right entries -> Right <$> (run
                                |> set #selectedEntriesJson (Just (Aeson.toJSON (map timesheetSelectionIdentity entries)))
                                |> set #previewPayloadJson (Aeson.object [])
                                |> set #readinessSnapshotJson (Aeson.object [])
                                |> set #errorSummary Nothing
                                |> updateRecord)
                    _ -> pure (Left "Choose a period and at least one shift before continuing.")
