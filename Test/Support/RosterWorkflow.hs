module Test.Support.RosterWorkflow
    ( assertRosterTimesheetJobCancelled
    , fetchRosterTimesheetJobForSlot
    , fetchRosterTimesheetJobsForSlot
    , timeOfDay
    ) where

import Application.RosterTimesheets.Automation (rosterTimesheetCreationJobKind)
import qualified Data.Aeson as Aeson
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import Test.Hspec

fetchRosterTimesheetJobForSlot :: (?modelContext :: ModelContext) => RosterSlot -> IO AppJob
fetchRosterTimesheetJobForSlot rosterSlot = do
    jobs <- fetchRosterTimesheetJobsForSlot rosterSlot
    case jobs of
        [job] -> pure job
        _ -> do
            expectationFailure ("Expected one roster timesheet job for slot, got " <> cs (tshow (length jobs)))
            error "unreachable"

fetchRosterTimesheetJobsForSlot :: (?modelContext :: ModelContext) => RosterSlot -> IO [AppJob]
fetchRosterTimesheetJobsForSlot rosterSlot =
    query @AppJob
        |> filterWhere (#jobKind, rosterTimesheetCreationJobKind)
        |> filterWhere (#relatedTable, Just "roster_slots")
        |> filterWhere (#relatedId, Just (unpackId rosterSlot.id))
        |> orderByAsc #createdAt
        |> fetch

assertRosterTimesheetJobCancelled :: (?modelContext :: ModelContext) => AppJob -> IO ()
assertRosterTimesheetJobCancelled job = do
    updatedJob <- fetch job.id
    updatedJob.status `shouldBe` JobStatusSucceeded
    updatedJob.result
        `shouldBe` Aeson.object
            [ "status" Aeson..= ("cancelled" :: Text)
            , "reason" Aeson..= ("roster_week_moved_to_draft" :: Text)
            ]

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
