module Test.Controller.PayrollExportParitySpec where

import Application.Helper.Export
import Config
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (status302)
import Test.Hspec
import Test.Support
import Test.Support.PayrollFixtures
import Web.Controller.Exports ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "Payroll export parity" do
        it "renders the canonical staff-hours CSV exactly" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0
                expectedCsv <- readExportFixtureText "staff_hours-expected.csv"

                get #exportType exportJob `shouldBe` exportJobTypeToText StaffPayCsv
                get #fileName exportJob `shouldBe` Just "staff_hours-2025-01-06.csv"
                get #payConfigSnapshotVersion exportJob `shouldBe` Just "v1"
                unsafeStripCarriageReturns (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

        it "preserves the historical filtered kitchen CSV exactly" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "kitchen" 0
                expectedCsv <- readExportFixtureText "kitchen-expected.csv"

                get #exportType exportJob `shouldBe` exportJobTypeToText StaffPayCsv
                get #fileName exportJob `shouldBe` Just "kitchen-2025-01-06.csv"
                unsafeStripCarriageReturns (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

        it "renders the canonical payroll earnings CSV shape exactly after normalizing row ids" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "payroll_earnings" 0
                expectedCsv <- readExportFixtureText "payroll_earnings-expected.normalized.csv"

                get #exportType exportJob `shouldBe` exportJobTypeToText PayrollEarningsCsv
                get #fileName exportJob `shouldBe` Just "payroll_earnings-2025-01-06.csv"
                get #payConfigSnapshotVersion exportJob `shouldBe` Just "v1"
                normalizePayrollEarningsCsv (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

        it "keeps only approved non-trial hours and buckets canonical rows into the expected days" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe` ["Ava LVL 1", "Ava LVL 2", "Kai LVL 1"]
                lookupCsvRow csvRows "Ava LVL 1" `shouldBe` ["2.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00"]
                lookupCsvRow csvRows "Ava LVL 2" `shouldBe` ["2.50", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "5.00", "0.00", "3.50", "1.00", "0.00"]
                lookupCsvRow csvRows "Kai LVL 1" `shouldBe` ["0.00", "0.00", "0.00", "4.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00"]

        it "keeps snapshot-pinned payroll CSV output stable after later pay-config changes" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                expectedCsv <- readExportFixtureText "staff_hours-expected.csv"

                _ <- fixture.barShift
                    |> set #overrideAwardLevelId (Just fixture.levelTwo.id)
                    |> updateRecord

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0

                get #payConfigSnapshotVersion exportJob `shouldBe` Just "v1"
                unsafeStripCarriageReturns (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

        it "marks payroll exports as mixed when approved rows span multiple pay snapshots" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                secondSnapshot <- createPayrollSnapshotWithVersion fixture.venue fixture.admin 2 [fixture.levelOne, fixture.levelTwo] [fixture.barShift, fixture.floorShift, fixture.kitchenShift] fixture.dayNames []
                _ <- createAndApproveEntry fixture.venue fixture.kaiStaff (fromGregorian 2025 1 12) secondSnapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.kitchenShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
                    ]

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                get #payConfigSnapshotVersion exportJob `shouldBe` Just "mixed"
                lookupCsvRow csvRows "Kai LVL 1" `shouldBe` ["0.00", "0.00", "0.00", "4.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "2.00"]

        it "aggregates multiple staff, employment bases, roles, breaks, and overnight penalty buckets" $ withContext do
            withCleanDb do
                fixture <- seedPayrollMatrixFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe`
                    [ "Ava LVL 2"
                    , "Ava LVL 4"
                    , "Ben LVL 1"
                    , "Cara LVL 1"
                    , "Noor LVL 3"
                    ]
                lookupCsvRow csvRows "Ava LVL 2" `shouldBe`
                    [ "4.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "6.50", "0.00"
                    , "1.00"
                    ]
                lookupCsvRow csvRows "Ava LVL 4" `shouldBe`
                    [ "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "1.00", "4.50", "0.00"
                    , "0.00", "2.00"
                    , "0.00"
                    ]
                lookupCsvRow csvRows "Ben LVL 1" `shouldBe`
                    [ "0.00", "0.00", "0.00"
                    , "6.50", "0.00", "1.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "5.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00"
                    , "0.00"
                    ]
                lookupCsvRow csvRows "Cara LVL 1" `shouldBe`
                    [ "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "3.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00"
                    , "0.00"
                    ]
                lookupCsvRow csvRows "Noor LVL 3" `shouldBe`
                    [ "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00"
                    , "5.67"
                    ]

        it "keeps filtered payroll exports grouped by staff while still using FWC-derived segment buckets" $ withContext do
            withCleanDb do
                fixture <- seedPayrollMatrixFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "supervisor" 0
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe` ["Ava"]
                lookupCsvRow csvRows "Ava" `shouldBe`
                    [ "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "0.00", "0.00", "0.00"
                    , "1.00", "4.50", "0.00"
                    , "0.00", "2.00"
                    , "0.00"
                    ]
    where
        unsafeStripCarriageReturns = Text.replace "\r" ""

normalizePayrollEarningsCsv :: Text -> Text
normalizePayrollEarningsCsv csvText =
    csvText
        |> Text.replace "\r" ""
        |> Text.lines
        |> map normalizeRow
        |> Text.unlines
    where
        normalizeRow row =
            if Text.isPrefixOf "staff_first_name," row
                then row
                else case Text.splitOn "," row of
                firstName : lastName : workDate : earningsRateName : hours : trackingCode : _description : _staffId : _entryIds : snapshot : penaltyKind : payLevelName : shiftTypeName : [] ->
                    Text.intercalate ","
                        [ firstName
                        , lastName
                        , workDate
                        , earningsRateName
                        , hours
                        , trackingCode
                        , "<description>"
                        , "<staff_id>"
                        , "<timesheet_entry_ids>"
                        , snapshot
                        , penaltyKind
                        , payLevelName
                        , shiftTypeName
                        ]
                _ -> row

data PayrollMatrixFixture = PayrollMatrixFixture
    { venue :: !Venue
    , admin :: !User
    }

seedPayrollMatrixFixture :: (?modelContext :: ModelContext) => IO PayrollMatrixFixture
seedPayrollMatrixFixture = do
    let weekStart = defaultWeekEpoch
    let dayAt offset = addDays offset weekStart
    let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
    venue <- createVenueWithConfig "Payroll Matrix Venue"
    admin <- createUserRecord "payroll-matrix-admin@example.com" "staff" True
    _ <- createVenueMembershipRecord venue admin "venue_admin"
    dayNames <- seedWeekDayNames venue
    levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 3 6 1 1.5 1.75
    levelTwo <- createPayLevelRecordWithRates venue "LVL 2" 36 4 8 1 1.5 1.75
    levelThree <- createPayLevelRecordWithRates venue "LVL 3" 42 5 10 1 1.5 1.75
    levelFour <- createPayLevelRecordWithRates venue "LVL 4" 48 6 12 1 1.5 1.75
    barShift <- createShiftTypeRecord venue levelTwo "Bar"
        >>= updateRecord
            . set #sortOrder 10
            . set #overrideAwardLevelId Nothing
    supervisorShift <- createShiftTypeRecord venue levelFour "Supervisor"
        >>= updateRecord . set #sortOrder 20
    kitchenShift <- createShiftTypeRecord venue levelThree "Kitchen"
        >>= updateRecord . set #sortOrder 30
    _ <- createReportDefinitionRecord venue "staff_hours" "Staff Hours Report" StaffPayCsvReport 20
    _ <- createReportDefinitionRecord venue "supervisor" "Supervisor Report" StaffPayCsvReport 40
        >>= createReportDefinitionShiftTypeFilterRecord supervisorShift

    avaUser <- createUserRecord "payroll-matrix-ava@example.com" "staff" True
    benUser <- createUserRecord "payroll-matrix-ben@example.com" "staff" True
    caraUser <- createUserRecord "payroll-matrix-cara@example.com" "staff" True
    noorUser <- createUserRecord "payroll-matrix-noor@example.com" "staff" True
    ava <- createStaffRecord venue (Just avaUser) "Ava" "Manager"
        >>= updateRecord
            . set #employmentBasis Permanent
            . set #defaultAwardLevelId (Just levelTwo.id)
    ben <- createStaffRecord venue (Just benUser) "Ben" "Casual"
        >>= updateRecord
            . set #employmentBasis Casual
            . set #defaultAwardLevelId (Just levelOne.id)
    cara <- createStaffRecord venue (Just caraUser) "Cara" "Casual"
        >>= updateRecord
            . set #employmentBasis Casual
            . set #defaultAwardLevelId (Just levelOne.id)
    noor <- createStaffRecord venue (Just noorUser) "Noor" "Cook"
        >>= updateRecord
            . set #employmentBasis Permanent
            . set #defaultAwardLevelId (Just levelOne.id)
    seedCasualBaseRate levelOne 37.5
    snapshot <- createPayrollSnapshot venue admin [levelOne, levelTwo, levelThree, levelFour] [barShift, supervisorShift, kitchenShift] dayNames []

    _ <- createAndApproveEntry venue ava (dayAt 0) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 8 0 0)
        , set #endTime (TimeOfDay 12 0 0)
        ]
    _ <- createAndApproveEntry venue ava (dayAt 4) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId supervisorShift.id)
        , set #startTime (TimeOfDay 18 0 0)
        , set #endTime (TimeOfDay 2 0 0)
        , set #hadBreak True
        , set #breakMinutes 30
        , set #breakStartTime (Just (TimeOfDay 22 0 0))
        , set #breakEndTime (Just (TimeOfDay 22 30 0))
        ]
    _ <- createAndApproveEntry venue ava (dayAt 5) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 17 0 0)
        , set #endTime (TimeOfDay 1 0 0)
        , set #hadBreak True
        , set #breakMinutes 30
        , set #breakStartTime (Just (TimeOfDay 21 0 0))
        , set #breakEndTime (Just (TimeOfDay 21 30 0))
        ]
    _ <- createAndApproveEntry venue ben (dayAt 1) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 6 0 0)
        , set #endTime (TimeOfDay 14 0 0)
        , set #hadBreak True
        , set #breakMinutes 30
        , set #breakStartTime (Just (TimeOfDay 10 0 0))
        , set #breakEndTime (Just (TimeOfDay 10 30 0))
        ]
    _ <- createAndApproveEntry venue ben (dayAt 3) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 19 0 0)
        , set #endTime (TimeOfDay 0 0 0)
        ]
    _ <- createAndApproveEntry venue cara (dayAt 2) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 9 0 0)
        , set #endTime (TimeOfDay 12 0 0)
        ]
    _ <- createAndApproveEntry venue noor (dayAt 6) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId kitchenShift.id)
        , set #startTime (TimeOfDay 11 0 0)
        , set #endTime (TimeOfDay 17 0 0)
        , set #hadBreak True
        , set #breakMinutes 20
        , set #breakStartTime (Just (TimeOfDay 13 30 0))
        , set #breakEndTime (Just (TimeOfDay 13 50 0))
        ]

    pure PayrollMatrixFixture { venue, admin }

createReportDefinitionRecord :: (?modelContext :: ModelContext) => Venue -> Text -> Text -> ReportDefinitionEngine -> Int -> IO ReportDefinition
createReportDefinitionRecord venue slug name engine sortOrder =
    newRecord @ReportDefinition
        |> set #venueId (unpackId venue.id)
        |> set #slug slug
        |> set #name name
        |> set #description Nothing
        |> set #engine (reportDefinitionEngineToText engine)
        |> set #sortOrder sortOrder
        |> set #isActive True
        |> createRecord

createReportDefinitionShiftTypeFilterRecord :: (?modelContext :: ModelContext) => ShiftType -> ReportDefinition -> IO ReportDefinitionShiftTypeFilter
createReportDefinitionShiftTypeFilterRecord shiftType reportDefinition =
    newRecord @ReportDefinitionShiftTypeFilter
        |> set #reportDefinitionId (unpackId reportDefinition.id)
        |> set #shiftTypeId (unpackId shiftType.id)
        |> createRecord

seedCasualBaseRate :: (?modelContext :: ModelContext) => AwardLevel -> Scientific -> IO ()
seedCasualBaseRate awardLevel hourlyRate = do
    payRate <- newRecord @FwcMapdPayRate
        |> set #awardFixedId awardLevel.awardFixedId
        |> set #classificationFixedId (Just awardLevel.classificationFixedId)
        |> set #classification awardLevel.classification
        |> set #employeeRateTypeCode (Just "AD")
        |> set #calculatedRate (Just hourlyRate)
        |> set #calculatedRateType (Just "Casual Hourly")
        |> createRecord
    void
        ( newRecord @AwardLevelBaseRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis Casual
            |> set #fwcMapdPayRateId (unpackId payRate.id)
            |> set #hourlyRate hourlyRate
            |> set #rateLabel ("Casual Hourly" :: Text)
            |> createRecord
        )

csvRowsByKey :: Text -> Map.Map Text [Text]
csvRowsByKey csvText =
    csvText
        |> unsafeStripCarriageReturns
        |> Text.lines
        |> drop 1
        |> filter (not . Text.null)
        |> map parseCsvRow
        |> Map.fromList
    where
        parseCsvRow row =
            case Text.splitOn "," row of
                nameType : values -> (nameType, values)
                _ -> error ("Unexpected payroll CSV row: " <> row)

        unsafeStripCarriageReturns = Text.replace "\r" ""

lookupCsvRow :: Map.Map Text [Text] -> Text -> [Text]
lookupCsvRow csvRows nameType =
    csvRows
        |> Map.lookup nameType
        |> fromMaybe (error ("Missing payroll CSV row for " <> nameType))

generatePayrollExportJob ::
    (?mocking :: MockContext WebApplication, ?request :: Request, ?respond :: Respond, ?modelContext :: ModelContext, ?application :: WebApplication) =>
    User ->
    Venue ->
    Text ->
    Int ->
    IO ExportJob
generatePayrollExportJob user venue reportSlug weekOffset = do
    response <- withUserAndCurrentVenue user venue.id do
        callActionWithParams CreateExportJobAction
            [ ("reportSlug", cs reportSlug)
            , ("weekOffset", cs (tshow weekOffset))
            ]

    response `responseStatusShouldBe` status302

    query @ExportJob
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#requestedByUserId, unpackId user.id)
        |> orderByDesc #createdAt
        |> fetchOne

readExportFixtureText :: FilePath -> IO Text
readExportFixtureText fixtureName =
    Text.readFile ("Test/Fixtures/exports/" <> fixtureName)
