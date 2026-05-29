module Test.PaySpec where

import Application.Helper.Pay
import Config
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
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
            let payload = "{\"entryId\":\"11111111-1111-1111-1111-111111111111\",\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"segments\":[{\"segment\":\"ordinary\",\"minutes\":480,\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"dayRuleMultiplier\":1.25,\"weekendMultiplier\":1.5,\"multiplier\":1.875,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":480,\"totalAmount\":0}}"
            case decodeTimesheetPayResult payload of
                Left err -> expectationFailure ("Expected decode success, got: " <> Text.unpack err)
                Right result -> do
                    result.entryId `shouldBe` "11111111-1111-1111-1111-111111111111"
                    result.shiftTypeName `shouldBe` Just "Ordinary"
                    result.payLevelName `shouldBe` Just "Level 1"
                    result.totals.paidMinutes `shouldBe` 480
                    fmap (.segment) result.segments `shouldBe` ["ordinary"]

        it "builds summary flags for weekend and stacked multipliers" do
            let result = TimesheetPayResult
                    { entryId = "11111111-1111-1111-1111-111111111111"
                    , shiftTypeId = Nothing
                    , shiftTypeName = Just "Ordinary"
                    , payLevelId = Nothing
                    , payLevelName = Just "Level 1"
                    , staffPayVersionId = Nothing
                    , shiftTypePayVersionId = Nothing
                    , segments =
                        [ PaySegment
                            { segment = "evening"
                            , segmentDate = Nothing
                            , minutes = 120
                            , shiftTypeId = Nothing
                            , shiftTypeName = Just "Ordinary"
                            , payLevelId = Nothing
                            , payLevelName = Just "Level 1"
                            , penaltyKind = Nothing
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
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 15 0 0)

                    result <- expectPayResult entry

                    result.payLevelName `shouldBe` Just "Level 1"
                    result.totals.paidMinutes `shouldBe` 360
                    result.totals.totalAmount `shouldBe` 180
                    fmap (.segment) result.segments `shouldBe` ["ordinary"]
                    fmap (.baseRate) result.segments `shouldBe` [30]
                    fmap (.amount) result.segments `shouldBe` [180]
                    result.payLevelId `shouldBe` Just (unpackId level.id)

            it "splits evening and after-midnight weekday penalties" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Late Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 9) (TimeOfDay 18 0 0) (TimeOfDay 2 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 22 0 0))
                            . set #breakEndTime (Just (TimeOfDay 22 30 0))

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "evening_after_7pm", "late_night_after_midnight"]
                    fmap (.minutes) result.segments `shouldBe` [60, 270, 120]
                    fmap (.amount) result.segments `shouldBe` [30, 148.5, 72]
                    result.totals.totalAmount `shouldBe` 250.5

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

            it "uses a staff imported Xero pay item as the hourly rate" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Imported Staff Bar"
                    importedPayItem <- createImportedPayItem venue "Imported Staff Rate" "xero-staff-rate" 55
                    _ <- staff |> set #importedXeroPayItemId (Just importedPayItem.id) |> updateRecord
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)

                    result <- expectPayResult entry

                    result.payLevelName `shouldBe` Just "Imported Staff Rate"
                    fmap (.baseRate) result.segments `shouldBe` [55]
                    fmap (.amount) result.segments `shouldBe` [220]
                    result.totals.totalAmount `shouldBe` 220

            it "lets shift type imported Xero pay items override staff imported Xero pay items" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Imported Shift Bar"
                    staffImportedPayItem <- createImportedPayItem venue "Imported Staff Rate" "xero-staff-rate" 55
                    shiftImportedPayItem <- createImportedPayItem venue "Imported Shift Rate" "xero-shift-rate" 70
                    _ <- staff |> set #importedXeroPayItemId (Just staffImportedPayItem.id) |> updateRecord
                    _ <- shiftType |> set #importedXeroPayItemId (Just shiftImportedPayItem.id) |> updateRecord
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)

                    result <- expectPayResult entry

                    result.payLevelName `shouldBe` Just "Imported Shift Rate"
                    fmap (.baseRate) result.segments `shouldBe` [70]
                    fmap (.amount) result.segments `shouldBe` [280]
                    result.totals.totalAmount `shouldBe` 280

            it "allocates breaks to the actual penalty segment instead of trimming the end of an overnight shift" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Break Placement Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 9) (TimeOfDay 18 0 0) (TimeOfDay 2 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 22 0 0))
                            . set #breakEndTime (Just (TimeOfDay 22 30 0))

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "evening_after_7pm", "late_night_after_midnight"]
                    fmap (.segmentDate) result.segments `shouldBe` map Just [fromGregorian 2025 1 9, fromGregorian 2025 1 9, fromGregorian 2025 1 10]
                    fmap (.minutes) result.segments `shouldBe` [60, 270, 120]
                    result.totals.paidMinutes `shouldBe` 450
                    result.totals.totalAmount `shouldBe` 250.5

            it "allocates after-midnight breaks to the next calendar day segment" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Midnight Break Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 9) (TimeOfDay 19 0 0) (TimeOfDay 2 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 0 15 0))
                            . set #breakEndTime (Just (TimeOfDay 0 45 0))

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["evening_after_7pm", "late_night_after_midnight"]
                    fmap (.segmentDate) result.segments `shouldBe` map Just [fromGregorian 2025 1 9, fromGregorian 2025 1 10]
                    fmap (.minutes) result.segments `shouldBe` [300, 90]
                    result.totals.paidMinutes `shouldBe` 390
                    result.totals.totalAmount `shouldBe` 219

            it "resolves weekday, Saturday, Sunday, and public holiday penalties from segment dates" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Penalty Matrix Bar"
                    sourceRate <- query @FwcMapdPayRate |> filterWhere (#classificationFixedId, Just level.classificationFixedId) |> fetchOne
                    createSyntheticPenalty level PublicHolidayPenalty sourceRate 75
                    _ <- newRecord @PublicHoliday
                        |> set #jurisdiction "VIC"
                        |> set #holidayDate (fromGregorian 2025 1 13)
                        |> set #name "Test Holiday"
                        |> set #isRegional False
                        |> createRecord

                    fridayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 19 0 0) (TimeOfDay 1 0 0)
                    saturdayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 11) (TimeOfDay 18 0 0) (TimeOfDay 2 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 22 0 0))
                            . set #breakEndTime (Just (TimeOfDay 22 30 0))
                    sundayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 12) (TimeOfDay 10 0 0) (TimeOfDay 14 0 0)
                    publicHolidayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 13) (TimeOfDay 10 0 0) (TimeOfDay 14 0 0)

                    friday <- expectPayResult fridayEntry
                    saturday <- expectPayResult saturdayEntry
                    sunday <- expectPayResult sundayEntry
                    publicHoliday <- expectPayResult publicHolidayEntry

                    fmap (.penaltyKind) friday.segments `shouldBe` [Just "evening_after_7pm", Just "saturday_penalty"]
                    fmap (.minutes) friday.segments `shouldBe` [300, 60]
                    friday.totals.totalAmount `shouldBe` 202.5

                    fmap (.penaltyKind) saturday.segments `shouldBe` [Just "saturday_penalty", Just "saturday_penalty", Just "sunday_penalty"]
                    fmap (.minutes) saturday.segments `shouldBe` [60, 270, 120]
                    saturday.totals.totalAmount `shouldBe` 296.25

                    fmap (.penaltyKind) sunday.segments `shouldBe` [Just "sunday_penalty"]
                    sunday.totals.totalAmount `shouldBe` 180

                    fmap (.penaltyKind) publicHoliday.segments `shouldBe` [Just "public_holiday_penalty"]
                    publicHoliday.totals.totalAmount `shouldBe` 300

            it "uses casual base and casual weekend penalty rows when the staff member is casual" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Casual Penalty Bar"
                    permanentPayRate <- query @FwcMapdPayRate |> filterWhere (#classificationFixedId, Just level.classificationFixedId) |> fetchOne
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
                    _ <- createSyntheticEmploymentPenalty level Casual SaturdayPenalty permanentPayRate 60
                    _ <- staff |> set #employmentBasis Casual |> updateRecord
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 11) (TimeOfDay 10 0 0) (TimeOfDay 14 0 0)

                    result <- expectPayResult entry

                    fmap (.baseRate) result.segments `shouldBe` [37.5]
                    fmap (.penaltyKind) result.segments `shouldBe` [Just "saturday_penalty"]
                    fmap (.amount) result.segments `shouldBe` [240]
                    result.totals.totalAmount `shouldBe` 240

            it "replaces worked time after six hours with weekday delayed meal break segments when no break is taken" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Delayed Meal Break Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "delayed_meal_break_weekday"]
                    fmap (.penaltyKind) result.segments `shouldBe` [Nothing, Just "delayed_meal_break_weekday"]
                    fmap (.minutes) result.segments `shouldBe` [360, 120]
                    fmap (.amount) result.segments `shouldBe` [180, 90]
                    result.totals.paidMinutes `shouldBe` 480
                    result.totals.totalAmount `shouldBe` 270

            it "does not apply delayed meal break when a 30 minute break starts inside the first six hours" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Timely Meal Break Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 14 30 0))
                            . set #breakEndTime (Just (TimeOfDay 15 0 0))

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary"]
                    fmap (.minutes) result.segments `shouldBe` [450]
                    result.totals.totalAmount `shouldBe` 225

            it "stops delayed meal break once a late 30 minute break starts" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Late Meal Break Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 30
                            . set #breakStartTime (Just (TimeOfDay 15 30 0))
                            . set #breakEndTime (Just (TimeOfDay 16 0 0))

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "delayed_meal_break_weekday"]
                    fmap (.minutes) result.segments `shouldBe` [420, 30]
                    fmap (.amount) result.segments `shouldBe` [210, 22.5]
                    result.totals.totalAmount `shouldBe` 232.5

            it "uses the permanent ordinary rate for the casual delayed meal break top-up" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Casual Delayed Meal Break Bar"
                    _ <- createCasualBaseRate level 37.5
                    _ <- staff |> set #employmentBasis Casual |> updateRecord
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "delayed_meal_break_weekday"]
                    fmap (.baseRate) result.segments `shouldBe` [37.5, 37.5]
                    fmap (.amount) result.segments `shouldBe` [225, 105]
                    result.totals.totalAmount `shouldBe` 330

            it "uses weekend and public holiday day rates as the delayed meal break base" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, level) <- createPayFixture "Delayed Meal Break Penalty Bar"
                    sourceRate <- query @FwcMapdPayRate |> filterWhere (#classificationFixedId, Just level.classificationFixedId) |> fetchOne
                    createSyntheticPenalty level PublicHolidayPenalty sourceRate 75
                    _ <- newRecord @PublicHoliday
                        |> set #jurisdiction "VIC"
                        |> set #holidayDate (fromGregorian 2025 1 10)
                        |> set #name "Test Holiday"
                        |> set #isRegional False
                        |> createRecord
                    saturdayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 11) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                    publicHolidayEntry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)

                    saturday <- expectPayResult saturdayEntry
                    publicHoliday <- expectPayResult publicHolidayEntry

                    fmap (.penaltyKind) saturday.segments `shouldBe` [Just "saturday_penalty", Just "delayed_meal_break_saturday"]
                    fmap (.amount) saturday.segments `shouldBe` [225, 105]
                    saturday.totals.totalAmount `shouldBe` 330
                    fmap (.penaltyKind) publicHoliday.segments `shouldBe` [Just "public_holiday_penalty", Just "delayed_meal_break_public_holiday"]
                    fmap (.amount) publicHoliday.segments `shouldBe` [450, 180]
                    publicHoliday.totals.totalAmount `shouldBe` 630

            it "uses delayed meal break instead of evening loading for the delayed weekday window" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Delayed Evening Meal Break Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 15 0 0) (TimeOfDay 23 0 0)

                    result <- expectPayResult entry

                    fmap (.segment) result.segments `shouldBe` ["ordinary", "evening_after_7pm", "delayed_meal_break_weekday"]
                    fmap (.minutes) result.segments `shouldBe` [240, 120, 120]
                    fmap (.amount) result.segments `shouldBe` [120, 66, 90]
                    result.totals.totalAmount `shouldBe` 276

            it "emits zero paid minutes for breaks that consume the whole shift" $ withContext do
                withCleanDb do
                    (venue, staff, shiftType, _) <- createPayFixture "Zero Paid Bar"
                    entry <- createEntry venue staff shiftType (fromGregorian 2025 1 10) (TimeOfDay 9 0 0) (TimeOfDay 10 0 0)
                        >>= updateRecord
                            . set #hadBreak True
                            . set #breakMinutes 60
                            . set #breakStartTime (Just (TimeOfDay 9 0 0))
                            . set #breakEndTime (Just (TimeOfDay 10 0 0))

                    result <- expectPayResult entry

                    result.segments `shouldBe` []
                    result.totals.paidMinutes `shouldBe` 0
                    result.totals.totalAmount `shouldBe` 0

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

createImportedPayItem :: (?modelContext :: ModelContext) => Venue -> Text -> Text -> Scientific -> IO XeroImportedPayItem
createImportedPayItem venue name earningsRateId rate = do
    owner <- createUserRecord ("xero-pay-" <> earningsRateId <> "@example.com") "admin" True
    maybeConnection <-
        query @XeroConnection
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#connectionStatus, "active" :: Text)
            |> fetchOneOrNothing
    connection <- case maybeConnection of
        Just existingConnection -> pure existingConnection
        Nothing ->
            newRecord @XeroConnection
                |> set #venueId (unpackId venue.id)
                |> set #tenantId ("tenant-" <> earningsRateId)
                |> set #tenantName (Just "Demo Company")
                |> set #connectionStatus ("active" :: Text)
                |> set #scopes ("payroll.payitems.read payroll.payitems" :: Text)
                |> set #encryptedRefreshToken ("encrypted-refresh-token" :: Text)
                |> set #connectedByUserId (Just (unpackId owner.id))
                |> createRecord
    newRecord @XeroImportedPayItem
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEarningsRateId earningsRateId
        |> set #name name
        |> set #earningsType ("ORDINARYTIMEEARNINGS" :: Text)
        |> set #rateType ("RATEPERUNIT" :: Text)
        |> set #typeOfUnits ("Hours" :: Text)
        |> set #ratePerUnit rate
        |> set #importedByUserId (unpackId owner.id)
        |> createRecord

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

createCasualBaseRate :: (?modelContext :: ModelContext) => AwardLevel -> Scientific -> IO AwardLevelBaseRate
createCasualBaseRate level hourlyRate = do
    casualPayRate <- newRecord @FwcMapdPayRate
        |> set #awardFixedId level.awardFixedId
        |> set #classificationFixedId (Just level.classificationFixedId)
        |> set #classification level.classification
        |> set #employeeRateTypeCode (Just "AD")
        |> set #calculatedRate (Just hourlyRate)
        |> set #calculatedRateType (Just "Casual Hourly")
        |> createRecord
    newRecord @AwardLevelBaseRate
        |> set #awardLevelId (unpackId level.id)
        |> set #employmentBasis Casual
        |> set #fwcMapdPayRateId (unpackId casualPayRate.id)
        |> set #hourlyRate hourlyRate
        |> set #rateLabel ("Casual Hourly" :: Text)
        |> createRecord

createSyntheticEmploymentPenalty :: (?modelContext :: ModelContext) => AwardLevel -> StaffEmploymentBasisEnum -> AwardPenaltyKindEnum -> FwcMapdPayRate -> Scientific -> IO ()
createSyntheticEmploymentPenalty awardLevel employmentBasis penaltyKind payRate hourlyRate = do
    penaltyRate <-
        newRecord @FwcMapdPenaltyRate
            |> set #awardFixedId awardLevel.awardFixedId
            |> set #classificationFixedId (Just awardLevel.classificationFixedId)
            |> set #classification awardLevel.classification
            |> set #employeeRateTypeCode (Just "AD")
            |> set #basePayRateId payRate.basePayRateId
            |> set #penaltyDescription (Just (inputValue penaltyKind))
            |> set #penaltyCalculatedValue (Just hourlyRate)
            |> createRecord
    void
        ( newRecord @AwardLevelPenaltyRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis employmentBasis
            |> set #penaltyKind penaltyKind
            |> set #fwcMapdPenaltyRateId (unpackId penaltyRate.id)
            |> set #hourlyRate hourlyRate
            |> createRecord
        )
