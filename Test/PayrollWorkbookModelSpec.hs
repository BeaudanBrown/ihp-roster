module Test.PayrollWorkbookModelSpec where

import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.Types
import Application.WageEngine
import qualified Application.WageEngine as WageEngine
import qualified Data.Map.Strict as Map
import Data.Ratio ((%))
import qualified Data.Text as Text
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Generated.Types
import IHP.ModelSupport
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Payroll Workbook authoritative hourly model" do
        it "aggregates shift types sharing one approval-pinned pay bucket and reconciles breaks, top-up hours, and cents" do
            let day = fromGregorian 2025 1 6
            let staff = testStaff testStaffId "Ada" "Lovelace"
            let bucket = PayrollWorkbookPayBucket (PayrollWorkbookAwardLevel payLevelId) "LVL 3"
            let firstEntry = testEntry firstEntryId testStaffId firstShiftTypeId day (testUtc 2025 1 5 22) (testUtc 2025 1 6 0)
            let secondEntry = testEntry secondEntryId testStaffId secondShiftTypeId day (testUtc 2025 1 5 23) (testUtc 2025 1 6 0)
            let firstWorked = paidSegment Worked day (testUtc 2025 1 5 22) (testUtc 2025 1 5 23)
            let firstWorkedAfterBreak = paidSegment Worked day (testUtcMinute 2025 1 5 23 30) (testUtc 2025 1 6 0)
            let firstTopUp = paidSegment CasualMinimumEngagementTopUp day (testUtc 2025 1 6 0) (testUtcMinute 2025 1 6 0 30)
            let firstCalculation = calculation firstEntryId day
                    [firstWorked, firstWorkedAfterBreak, firstTopUp]
                    [ hourlyComponent firstWorked 3000
                    , hourlyComponent firstWorkedAfterBreak 1500
                    , hourlyComponent firstTopUp 1500
                    ]
            let secondWorked = paidSegment Worked day (testUtc 2025 1 5 23) (testUtc 2025 1 6 0)
            let secondCalculation = calculation secondEntryId day [secondWorked] [hourlyComponent secondWorked 3000]
            let result = buildPayrollWorkbookHourlyModel
                    day
                    day
                    testVenueConfig
                    [firstEntry, secondEntry]
                    (Map.singleton testStaffId staff)
                    (Map.fromList [(firstEntryId, bucket), (secondEntryId, bucket)])
                    (Map.fromList [(firstEntryId, firstCalculation), (secondEntryId, secondCalculation)])

            model <- expectRight result
            let rows = concatMap (.payrollDayRows) model.payrollModelDays
            length rows `shouldBe` 1
            let row = fromMaybe (error "expected payroll row") (head rows)
            row.payrollRowEntryCount `shouldBe` 2
            sum row.payrollRowHours `shouldBe` 3
            sum row.payrollRowWageCents `shouldBe` 9000
            valueAt model row 9 FirstHourlyOccurrence `shouldBe` roundSix (4 % 3)
            valueAt model row 10 FirstHourlyOccurrence `shouldBe` roundSix (5 % 3)
            centsAt model row 9 FirstHourlyOccurrence `shouldBe` 4000
            centsAt model row 10 FirstHourlyOccurrence `shouldBe` 5000

        it "owns Monday final-day overnight work by Operational date and emits identical columns for empty dates" do
            let rangeStart = fromGregorian 2025 1 7
            let rangeEnd = fromGregorian 2025 1 13
            let staff = testStaff testStaffId "Grace" "Hopper"
            let narrowVenueConfig =
                    testVenueConfig
                        |> set #timePickerStartMinuteOfDay (9 * 60 + 15)
                        |> set #timePickerFinalSelectableMinuteOfDay (17 * 60 + 15)
            let bucket = PayrollWorkbookPayBucket (PayrollWorkbookAwardLevel payLevelId) "LVL 2"
            let entry = testEntry firstEntryId testStaffId firstShiftTypeId rangeEnd (testUtc 2025 1 13 12) (testUtc 2025 1 13 16)
            let segment = paidSegment Worked rangeEnd (testUtc 2025 1 13 12) (testUtc 2025 1 13 16)
            model <- buildPayrollWorkbookHourlyModel
                    rangeStart
                    rangeEnd
                    narrowVenueConfig
                    [entry]
                    (Map.singleton testStaffId staff)
                    (Map.singleton firstEntryId bucket)
                    (Map.singleton firstEntryId (calculation firstEntryId rangeEnd [segment] [hourlyComponent segment 12000]))
                |> expectRight

            model.payrollModelWindow `shouldBe` HourlyReportWindow 9 27
            map (.payrollDayDate) model.payrollModelDays `shouldBe` [rangeStart .. rangeEnd]
            map (length . (.payrollDayRows)) model.payrollModelDays `shouldBe` replicate 6 0 <> [1]
            let finalDay = fromMaybe (error "expected final payroll day") (last model.payrollModelDays)
            let finalRow = fromMaybe (error "expected final payroll row") (head finalDay.payrollDayRows)
            sum finalRow.payrollRowHours `shouldBe` 4
            sum finalRow.payrollRowWageCents `shouldBe` 12000
            valueAt model finalRow 26 FirstHourlyOccurrence `shouldBe` 1

        it "separates repeated autumn hours and leaves skipped spring hours at zero" do
            let autumnDate = fromGregorian 2026 4 4
            let springDate = fromGregorian 2026 10 3
            autumn <- dstModel autumnDate (testUtc 2026 4 4 14) (testUtc 2026 4 4 17)
            spring <- dstModel springDate (testUtc 2026 10 3 14) (testUtc 2026 10 3 17)
            let autumnDay = fromMaybe (error "expected autumn payroll day") (head autumn.payrollModelDays)
            let springDay = fromMaybe (error "expected spring payroll day") (head spring.payrollModelDays)
            let autumnRow = fromMaybe (error "expected autumn payroll row") (head autumnDay.payrollDayRows)
            let springRow = fromMaybe (error "expected spring payroll row") (head springDay.payrollDayRows)

            valueAt autumn autumnRow 26 FirstHourlyOccurrence `shouldBe` 1
            valueAt autumn autumnRow 26 SecondHourlyOccurrence `shouldBe` 1
            centsAt autumn autumnRow 26 FirstHourlyOccurrence `shouldBe` 3000
            centsAt autumn autumnRow 26 SecondHourlyOccurrence `shouldBe` 3000
            valueAt spring springRow 26 FirstHourlyOccurrence `shouldBe` 0
            valueAt spring springRow 26 SecondHourlyOccurrence `shouldBe` 0
            sum springRow.payrollRowHours `shouldBe` 3

            let autumnWorkbook = payrollWorkbookFromHourlyModel 1 autumn
            let autumnHoursSheet = autumnWorkbook.sheets !! 1
            let autumnSummary = fromMaybe (error "expected rendered autumn Summary sheet") (head autumnWorkbook.sheets)
            let repeatedHeaders =
                    [ value
                    | PayrollWorkbookCell { value = PayrollWorkbookText value } <- autumnHoursSheet.cells
                    , Text.isInfixOf "02:00-03:00+1" value
                    ]
            repeatedHeaders `shouldBe` ["02:00-03:00+1 (first)", "02:00-03:00+1 (second)"]
            let repeatedSummaryFormulas =
                    [ formula
                    | PayrollWorkbookCell { value = PayrollWorkbookFormula formula } <- autumnSummary.cells
                    , Text.isInfixOf "Hours Sat 2026-04-04" formula
                    , Text.isInfixOf "+" formula
                    ]
            repeatedSummaryFormulas `shouldSatisfy` (not . null)

        it "fails empty requests and missing payroll authority clearly" do
            buildPayrollWorkbookHourlyModel
                (fromGregorian 2025 1 6)
                (fromGregorian 2025 1 6)
                testVenueConfig
                []
                Map.empty
                Map.empty
                Map.empty
                `shouldBe` Left "No approved payroll entries were found for the Payroll Workbook range."

            let day = fromGregorian 2025 1 6
            let entry = testEntry firstEntryId testStaffId firstShiftTypeId day (testUtc 2025 1 5 22) (testUtc 2025 1 5 23)
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] Map.empty Map.empty Map.empty
                `shouldBe` Left ("Payroll Workbook entry has no linked active staff: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

            let staff = testStaff testStaffId "Failure" "Boundary"
            let bucket = PayrollWorkbookPayBucket (PayrollWorkbookAwardLevel payLevelId) "LVL 1"
            let staffMap = Map.singleton testStaffId staff
            let bucketMap = Map.singleton firstEntryId bucket
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] staffMap Map.empty Map.empty
                `shouldBe` Left ("Payroll Workbook entry has no approval-pinned pay bucket: " <> tshow (Id firstEntryId :: Id TimesheetEntry))
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] staffMap bucketMap Map.empty
                `shouldBe` Left ("Payroll Workbook entry has no sealed wage calculation: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

            let outsideSegment = paidSegment Worked day (testUtc 2025 1 5 21) (testUtc 2025 1 5 22)
            let outsideCalculation = calculation firstEntryId day [outsideSegment] [hourlyComponent outsideSegment 3000]
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] staffMap bucketMap (Map.singleton firstEntryId outsideCalculation)
                `shouldBe` Left ("Payroll Workbook worked segment falls outside its timesheet interval: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

            let validSegment = paidSegment Worked day entry.startsAt entry.endsAt
            let validCalculation = calculation firstEntryId day [validSegment] [hourlyComponent validSegment 3000]
            let missingDateCalculation = validCalculation { WageEngine.publishedOperationalDate = Nothing }
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] staffMap bucketMap (Map.singleton firstEntryId missingDateCalculation)
                `shouldBe` Left ("Payroll Workbook sealed wage calculation has a missing or mismatched Operational date: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

            let baseComponent :: EarningsComponent
                baseComponent = hourlyComponent validSegment 3000
            let negativeComponent = baseComponent { WageEngine.amount = -1 }
            let unreconciledCalculation = calculation firstEntryId day [validSegment] [negativeComponent]
            buildPayrollWorkbookHourlyModel day day testVenueConfig [entry] staffMap bucketMap (Map.singleton firstEntryId unreconciledCalculation)
                `shouldBe` Left ("Payroll Workbook hourly wages do not reconcile to sealed earnings: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

            let secondEntry = testEntry secondEntryId testStaffId secondShiftTypeId day (testUtc 2025 1 5 23) (testUtc 2025 1 6 0)
            let secondSegment = paidSegment Worked day secondEntry.startsAt secondEntry.endsAt
            let secondCalculation = calculation secondEntryId day [secondSegment] [hourlyComponent secondSegment 3000]
            buildPayrollWorkbookHourlyModel
                day
                day
                testVenueConfig
                [secondEntry, entry]
                staffMap
                (Map.fromList [(secondEntryId, bucket), (firstEntryId, bucket)])
                (Map.fromList [(secondEntryId, secondCalculation), (firstEntryId, unreconciledCalculation)])
                `shouldBe` Left ("Payroll Workbook hourly wages do not reconcile to sealed earnings: " <> tshow (Id firstEntryId :: Id TimesheetEntry))

expectRight :: (HasCallStack, Show left) => Either left right -> IO right
expectRight value =
    case value of
        Left err     -> expectationFailure (cs (show err)) >> error "unreachable"
        Right result -> pure result

valueAt :: PayrollWorkbookHourlyModel -> PayrollWorkbookRow -> Int -> HourlyOccurrence -> Rational
valueAt model row hour occurrence =
    maybe 0 (row.payrollRowHours !!) (slotIndex model hour occurrence)

centsAt :: PayrollWorkbookHourlyModel -> PayrollWorkbookRow -> Int -> HourlyOccurrence -> Integer
centsAt model row hour occurrence =
    maybe 0 (row.payrollRowWageCents !!) (slotIndex model hour occurrence)

slotIndex :: PayrollWorkbookHourlyModel -> Int -> HourlyOccurrence -> Maybe Int
slotIndex model hour occurrence =
    findIndex (== PayrollWorkbookHourSlot hour occurrence) model.payrollModelHourSlots

roundSix :: Rational -> Rational
roundSix value = fromInteger (round (value * 1000000)) / 1000000

dstModel :: Day -> UTCTime -> UTCTime -> IO PayrollWorkbookHourlyModel
dstModel day startsAt endsAt = do
    let staff = testStaff testStaffId "Dorothy" "Vaughan"
    let bucket = PayrollWorkbookPayBucket (PayrollWorkbookAwardLevel payLevelId) "LVL 4"
    let entry = testEntry firstEntryId testStaffId firstShiftTypeId day startsAt endsAt
    let segment = paidSegment Worked day startsAt endsAt
    buildPayrollWorkbookHourlyModel
        day
        day
        testVenueConfig
        [entry]
        (Map.singleton testStaffId staff)
        (Map.singleton firstEntryId bucket)
        (Map.singleton firstEntryId (calculation firstEntryId day [segment] [hourlyComponent segment (round (paidTimeDurationSeconds segment / 3600) * 3000)]))
        |> expectRight

calculation :: UUID -> Day -> [PaidTimeSegment] -> [EarningsComponent] -> WageCalculation
calculation entryId day segments components =
    WageCalculation
        { calculatedEntryId = CalculationEntryId (tshow entryId)
        , calculationVersion = currentWageCalculationVersion
        , calculationRateBookVersion = Nothing
        , publishedOperationalDate = Just day
        , paidTimeSegments = segments
        , earningsComponents = components
        }

hourlyComponent :: PaidTimeSegment -> Integer -> EarningsComponent
hourlyComponent segment cents =
    EarningsComponent
        { quantity = paidTimeDurationSeconds segment / 3600
        , unitType = Hours
        , ratePerUnit = 30
        , amount = fromInteger cents / 100
        , publishedComponentDate = Just segment.paidTimeLocalDate
        , publishedRateBoundaryDate = Nothing
        , publishedXeroLocalBucketKey = Nothing
        , publishedXeroEarningsRateId = Nothing
        , publishedXeroMappingLegacyFallback = False
        , sourceCondition = segment.paidTimeSourceCondition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Nothing
        }

paidSegment :: PaidTimeKind -> Day -> UTCTime -> UTCTime -> PaidTimeSegment
paidSegment kind day startsAt endsAt =
    PaidTimeSegment
        { paidTimeKind = kind
        , paidTimeStart = startsAt
        , paidTimeEnd = endsAt
        , paidTimeLocalDate = day
        , paidTimeSourceCondition = OrdinaryCondition
        }

testEntry :: UUID -> UUID -> UUID -> Day -> UTCTime -> UTCTime -> TimesheetEntry
testEntry entryId testStaffId' shiftTypeId' day startsAt endsAt =
    newRecord @TimesheetEntry
        |> set #id (Id entryId)
        |> set #staffId testStaffId'
        |> set #shiftTypeId shiftTypeId'
        |> set #operationalDate day
        |> set #startsAt startsAt
        |> set #endsAt endsAt
        |> set #timezone "Australia/Melbourne"

testStaff :: UUID -> Text -> Text -> Staff
testStaff id' firstName lastName =
    newRecord @Staff
        |> set #id (Id id')
        |> set #firstName firstName
        |> set #lastName lastName

testVenueConfig :: VenueConfig
testVenueConfig =
    newRecord @VenueConfig
        |> set #timezone "Australia/Melbourne"
        |> set #timePickerStartMinuteOfDay (6 * 60)
        |> set #timePickerFinalSelectableMinuteOfDay (5 * 60)

testUtc :: Integer -> Int -> Int -> Integer -> UTCTime
testUtc year month day hour = testUtcMinute year month day hour 0

testUtcMinute :: Integer -> Int -> Int -> Integer -> Integer -> UTCTime
testUtcMinute year month day hour minute = UTCTime (fromGregorian year month day) (secondsToDiffTime (hour * 3600 + minute * 60))

testStaffId, payLevelId, firstEntryId, secondEntryId, firstShiftTypeId, secondShiftTypeId :: UUID
testStaffId = "10000000-0000-0000-0000-000000000001"
payLevelId = "20000000-0000-0000-0000-000000000001"
firstEntryId = "30000000-0000-0000-0000-000000000001"
secondEntryId = "30000000-0000-0000-0000-000000000002"
firstShiftTypeId = "40000000-0000-0000-0000-000000000001"
secondShiftTypeId = "40000000-0000-0000-0000-000000000002"
