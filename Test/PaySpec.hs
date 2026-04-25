module Test.PaySpec where

import Application.Helper.Pay
import Config
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = do
    describe "Pay helper orchestration" do
        it "decodes single-entry pay payloads" do
            let payload = "{\"entryId\":\"11111111-1111-1111-1111-111111111111\",\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"payConfigSnapshotVersion\":\"v1\",\"segments\":[{\"segment\":\"ordinary\",\"minutes\":480,\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"dayRuleMultiplier\":1.25,\"weekendMultiplier\":1.5,\"multiplier\":1.875,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":480,\"totalAmount\":0}}"
            case decodeTimesheetPayResult payload of
                Left err -> expectationFailure ("Expected decode success, got: " <> Text.unpack err)
                Right result -> do
                    result.entryId `shouldBe` "11111111-1111-1111-1111-111111111111"
                    result.shiftTypeName `shouldBe` Just "Ordinary"
                    result.payLevelName `shouldBe` Just "Level 1"
                    result.payConfigSnapshotVersion `shouldBe` Just "v1"
                    result.totals.paidMinutes `shouldBe` 480
                    fmap (.segment) result.segments `shouldBe` ["ordinary"]

        it "builds summary flags for weekend and stacked multipliers" do
            let result = TimesheetPayResult
                    { entryId = "11111111-1111-1111-1111-111111111111"
                    , shiftTypeId = Nothing
                    , shiftTypeName = Just "Ordinary"
                    , payLevelId = Nothing
                    , payLevelName = Just "Level 1"
                    , payConfigSnapshotId = Nothing
                    , payConfigSnapshotVersion = Nothing
                    , segments =
                        [ PaySegment
                            { segment = "evening"
                            , minutes = 120
                            , shiftTypeId = Nothing
                            , shiftTypeName = Just "Ordinary"
                            , payLevelId = Nothing
                            , payLevelName = Just "Level 1"
                            , multiplier = 1.875
                            , dayRuleMultiplier = Just 1.25
                            , weekendMultiplier = Just 1.5
                            , baseRate = 30
                            , amount = 75
                            }
                        ]
                    , totals = PayTotals { paidMinutes = 120, totalAmount = 0 }
                    }
                summary = buildTimesheetPaySummary result
            summary.paidMinutes `shouldBe` 120
            summary.segmentCount `shouldBe` 1
            summary.weekendApplied `shouldBe` True
            summary.hasStackedMultiplier `shouldBe` True
            summary.totalAmount `shouldBe` 0

        it "decodes range payload arrays and indexes summaries by entry id" do
            let payload = "[{\"entryId\":\"a\",\"segments\":[{\"segment\":\"ordinary\",\"minutes\":60,\"dayRuleMultiplier\":1.0,\"weekendMultiplier\":1.0,\"multiplier\":1.0,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":60,\"totalAmount\":0}},{\"entryId\":\"b\",\"segments\":[{\"segment\":\"evening\",\"minutes\":30,\"dayRuleMultiplier\":1.0,\"weekendMultiplier\":1.5,\"multiplier\":1.5,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":30,\"totalAmount\":0}}]"
            case decodeTimesheetPayResults payload of
                Left err -> expectationFailure ("Expected decode success, got: " <> Text.unpack err)
                Right results -> do
                    length results `shouldBe` 2
                    let summaries = buildTimesheetPaySummariesByEntryId results
                    fmap (.weekendApplied) (Map.lookup "a" summaries) `shouldBe` Just False
                    fmap (.weekendApplied) (Map.lookup "b" summaries) `shouldBe` Just True

    beforeAll testContext do
        describe "Award-backed pay calculations" do
            it "uses the staff default award level for ordinary weekday hours" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Ordinary"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)

                    result <- expectPayResult entry

                    result.payLevelName `shouldBe` Just "Level 1"
                    result.totals.paidMinutes `shouldBe` 480
                    result.totals.totalAmount `shouldBe` 240
                    fmap (.segment) result.segments `shouldBe` ["ordinary"]
                    fmap (.baseRate) result.segments `shouldBe` [30]
                    fmap (.amount) result.segments `shouldBe` [240]
                    result.payLevelId `shouldBe` Just (unpackId level.id)

            it "splits evening and after-midnight weekday penalties" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Late Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 18 0 0) (TimeOfDay 2 0 0)

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "evening_after_7pm", "late_night_after_midnight"]
                    fmap (.minutes) result.segments `shouldBe` [60, 300, 120]
                    fmap (.amount) result.segments `shouldBe` [30, 165, 72]
                    result.totals.totalAmount `shouldBe` 267

            it "uses weekend and public holiday penalty rows when applicable" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Weekend Bar"
                    sourceRate <- query @FwcMapdPayRate |> filterWhere (#classificationFixedId, Just level.classificationFixedId) |> fetchOne
                    createSyntheticPenalty level PublicHolidayPenalty sourceRate 75
                    _ <- newRecord @PublicHoliday
                        |> set #jurisdiction "VIC"
                        |> set #holidayDate (fromGregorian 2025 1 10)
                        |> set #name "Test Holiday"
                        |> set #isRegional False
                        |> createRecord

                    saturdayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 11) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                    publicHolidayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)

                    saturdayResult <- expectPayResult saturdayEntry
                    publicHolidayResult <- expectPayResult publicHolidayEntry

                    fmap (.amount) saturdayResult.segments `shouldBe` [150]
                    saturdayResult.totals.totalAmount `shouldBe` 150
                    fmap (.amount) publicHolidayResult.segments `shouldBe` [300]
                    publicHolidayResult.totals.totalAmount `shouldBe` 300

            it "uses casual base rates for casual staff" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Casual Bar"
                    casualPayRate <- newRecord @FwcMapdPayRate
                        |> set #awardFixedId level.awardFixedId
                        |> set #classificationFixedId (Just level.classificationFixedId)
                        |> set #classification level.classification
                        |> set #employeeRateTypeCode (Just "AD")
                        |> set #calculatedRate (Just 37.5)
                        |> set #calculatedRateType (Just "Casual Hourly")
                        |> createRecord
                    _ <- newRecord @AwardLevelBaseRate
                        |> set #awardLevelId (unpackId level.id)
                        |> set #employmentBasis Casual
                        |> set #fwcMapdPayRateId (unpackId casualPayRate.id)
                        |> set #hourlyRate 37.5
                        |> set #rateLabel ("Casual Hourly" :: Text)
                        |> createRecord
                    _ <- staff |> set #employmentBasis Casual |> updateRecord
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)

                    result <- expectPayResult entry

                    fmap (.baseRate) result.segments `shouldBe` [37.5]
                    result.totals.totalAmount `shouldBe` 150

            it "lets a shift type award level override the staff default" $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Override Venue"
                    staffLevel <- createPayLevelRecordWithRates venue "Staff Level" 30 3 6 1 1.25 1.5
                    shiftLevel <- createPayLevelRecordWithRates venue "Shift Level" 40 4 8 1 1.25 1.5
                    staff <- createStaffRecord venue Nothing "Pat" "Rate"
                        >>= updateRecord
                            . set #employmentBasis Permanent
                            . set #defaultAwardLevelId (Just staffLevel.id)
                    shiftType <- createShiftTypeRecord venue shiftLevel "Manager"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)

                    result <- expectPayResult entry

                    result.payLevelName `shouldBe` Just "Shift Level"
                    result.payLevelId `shouldBe` Just (unpackId shiftLevel.id)
                    result.totals.totalAmount `shouldBe` 160

createPayFixture :: (?modelContext :: ModelContext) => Text -> IO (Venue, Staff, ShiftType, AwardLevel)
createPayFixture shiftTypeName = do
    venue <- createVenueWithConfig "Pay Calc Venue"
    level <- createPayLevelRecordWithRates venue "Level 1" 30 3 6 1 1.25 1.5
    staff <- createStaffRecord venue Nothing "Pat" "Rate"
        >>= updateRecord
            . set #employmentBasis Permanent
            . set #defaultAwardLevelId (Just level.id)
    shiftType <-
        newRecord @ShiftType
            |> set #venueId (unpackId venue.id)
            |> set #name shiftTypeName
            |> set #sortOrder 0
            |> set #overrideAwardLevelId Nothing
            |> set #isActive True
            |> createRecord
    pure (venue, staff, shiftType, level)

createEntry :: (?modelContext :: ModelContext) => Venue -> Staff -> ShiftType -> Day -> TimeOfDay -> TimeOfDay -> IO TimesheetEntry
createEntry venue staff shiftType workedOn startTime endTime =
    createTimesheetEntryRecord venue staff workedOn
        >>= updateRecord
            . set #shiftTypeId (unpackId shiftType.id)
            . set #startTime startTime
            . set #endTime endTime

expectPayResult :: (?modelContext :: ModelContext) => TimesheetEntry -> IO TimesheetPayResult
expectPayResult entry = do
    payResult <- fetchTimesheetPay entry.id
    case payResult of
        Left err     -> fail ("Expected pay result, got: " <> Text.unpack err)
        Right result -> pure result
