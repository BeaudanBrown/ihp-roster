module Application.Support.WageSourceFixtures
    ( ensureFreshWageSourceFacts
    , sealApprovedFixtureCalculation
    ) where

import Application.WageEngine (WageCalculationVersion (..),
                               currentWageCalculationVersion)
import Control.Monad (void)
import Data.Scientific (Scientific)
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
    when (isNothing existingHoliday) do
        void $ newRecord @PublicHoliday
            |> set #jurisdiction ("VIC" :: Text)
            |> set #holidayDate (fromGregorian year 1 1)
            |> set #name ("New Year's Day" :: Text)
            |> set #isRegional False
            |> set #source (Just "DataVic")
            |> set #importedAt (Just now)
            |> createRecord

sealApprovedFixtureCalculation :: (?modelContext :: ModelContext) => TimesheetEntry -> IO TimesheetEntry
sealApprovedFixtureCalculation entry = do
    staffVersionId <- maybe (fail "fixture missing staff pay version") pure entry.staffPayVersionId
    shiftVersionId <- maybe (fail "fixture missing shift pay version") pure entry.shiftTypePayVersionId
    approvedAt <- maybe (fail "fixture missing approval time") pure entry.approvedAt
    approvedBy <- maybe (fail "fixture missing approver") pure entry.approvedByUserId
    staffVersion <- fetch (Id staffVersionId :: Id StaffPayVersion)
    shiftVersion <- fetch (Id shiftVersionId :: Id ShiftTypePayVersion)
    let importedItemId = shiftVersion.importedXeroPayItemId <|> staffVersion.importedXeroPayItemId
        calculationSource = if isJust importedItemId then "external_imported_pay_item" else "hospitality_award" :: Text
        sourceCondition = maybe "ordinary" (\itemId -> "external_imported_pay_item:" <> inputValue itemId) importedItemId
    now <- getCurrentTime
    calculation <- newRecord @TimesheetPayCalculation
        |> set #timesheetEntryId (unpackId entry.id)
        |> set #calculationVersion (let WageCalculationVersion value = currentWageCalculationVersion in value)
        |> set #calculationSource calculationSource
        |> set #venueTimezone ("Australia/Melbourne" :: Text)
        |> set #holidayJurisdiction ("VIC" :: Text)
        |> set #staffPayVersionId staffVersionId
        |> set #shiftTypePayVersionId shiftVersionId
        |> set #approvedAt approvedAt
        |> set #approvedByUserId approvedBy
        |> createRecord
    void $ newRecord @TimesheetPayEarningsComponent
        |> set #timesheetPayCalculationId (unpackId calculation.id)
        |> set #ordinal (0 :: Int)
        |> set #quantity (0 :: Scientific)
        |> set #unitType ("hours" :: Text)
        |> set #ratePerUnit (0 :: Scientific)
        |> set #exactAmount (0 :: Scientific)
        |> set #sourceCondition sourceCondition
        |> set #calculationSource calculationSource
        |> set #sourceRateIdentity (Just "fixture:sealed-approved-calculation")
        |> createRecord
    sealed <- calculation |> set #sealedAt (Just now) |> updateRecord
    entry
        |> set #activePayCalculationId (Just sealed.id)
        |> set #legacyPayBackfillPending False
        |> updateRecord
