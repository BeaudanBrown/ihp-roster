module Application.Fixture.WageSourceFixtures
    ( ensureFreshWageSourceFacts
    , sealApprovedFixtureCalculation
    ) where

import Application.Fixture.Error
import Application.Helper.TimesheetPayLedger (persistApprovedTimesheetPayCalculation)
import Application.VenueTime.Model (decodeTimesheetTiming,
                                    timesheetTimingWorkedOn)
import Control.Monad (void)
import Data.Time.Calendar (Day, fromGregorian, toGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

ensureFreshWageSourceFacts :: (?modelContext :: ModelContext) => Day -> IO ()
ensureFreshWageSourceFacts workedOn = do
    now <- getCurrentTime
    let (year, _, _) = toGregorian workedOn
    _ <- newRecord @FwcMapdSyncRun
        |> set #status ("succeeded" :: Text)
        |> set #requestedAwardFixedIds [9]
        |> set #syncedAwardFixedIds [9]
        |> set #startedAt now
        |> set #finishedAt (Just now)
        |> createRecord
    existingHoliday <- query @PublicHoliday
        |> filterWhere (#jurisdiction, "VIC" :: Text)
        |> filterWhere (#holidayDate, fromGregorian year 1 1)
        |> filterWhere (#isRegional, False)
        |> fetchOneOrNothing
    case existingHoliday of
        Just holiday ->
            void $
                holiday
                    |> set #importedAt (Just now)
                    |> updateRecord
        Nothing ->
            void $ newRecord @PublicHoliday
                |> set #jurisdiction ("VIC" :: Text)
                |> set #holidayDate (fromGregorian year 1 1)
                |> set #name ("New Year's Day" :: Text)
                |> set #isRegional False
                |> set #source (Just "DataVic")
                |> set #importedAt (Just now)
                |> createRecord

-- | Seal test/dev approved entries through the same Haskell calculation and
-- immutable-ledger path used by production approval.
sealApprovedFixtureCalculation :: (?modelContext :: ModelContext) => TimesheetEntry -> IO TimesheetEntry
sealApprovedFixtureCalculation entry = do
    timing <- requireFixtureResult (either (Left . InvalidFixtureBoundary . tshow) Right (decodeTimesheetTiming entry))
    ensureFreshWageSourceFacts (timesheetTimingWorkedOn timing)
    result <- persistApprovedTimesheetPayCalculation entry
    case result of
        Left reason -> requireFixtureResult (Left (InvalidFixtureBoundary reason))
        Right calculation ->
            entry
                |> set #activePayCalculationId (Just calculation.id)
                |> set #legacyPayBackfillPending False
                |> updateRecord
