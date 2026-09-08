module Test.Controller.FixedExportGoldenSpec where

import Application.Fixture.PayrollFixtures
import Application.Helper.Export
import Application.WageEngine (AwardClassification (..))
import qualified "zip-archive" Codec.Archive.Zip as Zip
import Config
import Control.Monad (void)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import qualified Data.Text.IO as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Header (hContentDisposition)
import Network.HTTP.Types.Status (status200, status302)
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.Exports ()
import Web.FrontController ()
import Web.Types

goldenWeekStart :: Day
goldenWeekStart = fromGregorian 2025 1 7

goldenWeekEnd :: Day
goldenWeekEnd = addDays 6 goldenWeekStart

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Fixed export goldens" do
        it "uses canonical Staff Hours labels for every supported Award classification" $ withContext do
            map staffHoursAwardClassificationLabel
                [ HospitalityIntroductory
                , HospitalityLevel1
                , HospitalityLevel2
                , HospitalityLevel3
                , HospitalityLevel4
                , HospitalityLevel5
                , HospitalityLevel6
                ]
                `shouldBe` ["LVL 0", "LVL 1", "LVL 2", "LVL 3", "LVL 4", "LVL 5", "LVL 6"]

        it "renders the canonical staff-hours CSV exactly" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                expectedCsv <- readExportFixtureText "staff_hours-expected.csv"

                get #exportType exportJob `shouldBe` exportJobTypeToText StaffPayCsv
                get #fileName exportJob `shouldBe` Just "staff_hrs_starting-2025-01-07.csv"
                get #payConfigVersionManifest exportJob `shouldBe` Just "mixed"
                unsafeStripCarriageReturns (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

                downloadResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.admin fixture.venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]
                downloadResponse `responseStatusShouldBe` status200
                lookup hContentDisposition (responseHeaders downloadResponse)
                    `shouldBe` Just "attachment; filename=\"staff_hrs_starting-2025-01-07.csv\""

        it "keeps final-day overnight staff hours in the Operational-day position while retaining factual earnings dates" $ withContext do
            withCleanDb do
                let weekStart = fromGregorian 2025 1 6
                    weekEnd = addDays 6 weekStart
                fixture <- seedCanonicalPayrollFixtureForWeek weekStart
                overnightEntry <- createAndApproveEntry fixture.venue fixture.avaStaff weekEnd fixture.snapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.barShift.id)
                    , setTestStartTime (TimeOfDay 15 0 0)
                    , setTestEndTime (TimeOfDay 1 14 0)
                    , setTestHadBreak True
                    , setTestBreakMinutes 30
                    , setTestBreakStartTime (Just (TimeOfDay 20 30 0))
                    , setTestBreakEndTime (Just (TimeOfDay 21 0 0))
                    ]

                expectedStaffHours <- readExportFixtureText "overnight-staff-hours-expected.csv"
                expectedPayrollEarnings <- readExportFixtureText "overnight-payroll-earnings-expected.normalized.csv"
                firstStaffHours <- generatePayrollExportJobForRange fixture.admin fixture.venue weekStart weekEnd StaffPayCsv
                secondStaffHours <- generatePayrollExportJobForRange fixture.admin fixture.venue weekStart weekEnd StaffPayCsv
                firstEarnings <- generatePayrollExportJobForRange fixture.admin fixture.venue weekStart weekEnd PayrollEarningsCsv
                secondEarnings <- generatePayrollExportJobForRange fixture.admin fixture.venue weekStart weekEnd PayrollEarningsCsv

                let actualStaffHours = unsafeStripCarriageReturns (fromMaybe "" firstStaffHours.fileContents)
                    actualEarnings = normalizePayrollEarningsCsv (fromMaybe "" firstEarnings.fileContents)
                    entryRows = filter (Text.isInfixOf (tshow (unpackId overnightEntry.id))) (Text.lines (fromMaybe "" firstEarnings.fileContents))
                actualStaffHours `shouldBe` unsafeStripCarriageReturns expectedStaffHours
                actualEarnings `shouldBe` normalizeExpectedPayrollEarningsCsv expectedPayrollEarnings
                secondStaffHours.fileContents `shouldBe` firstStaffHours.fileContents
                secondEarnings.fileContents `shouldBe` firstEarnings.fileContents
                entryRows `shouldSatisfy` any (Text.isInfixOf ",2025-01-12,")
                entryRows `shouldSatisfy` any (Text.isInfixOf ",2025-01-13,")

        it "includes early-morning work in its selected Operational window" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                _ <- createAndApproveEntry fixture.venue fixture.avaStaff goldenWeekEnd fixture.snapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.barShift.id)
                    , setTestStartTime (TimeOfDay 22 0 0)
                    , setTestEndTime (TimeOfDay 2 0 0)
                    ]
                earlyEntry <- createAndApproveEntry fixture.venue fixture.avaStaff goldenWeekEnd fixture.snapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.barShift.id)
                    , setTestStartTime (TimeOfDay 6 0 0)
                    , setTestEndTime (TimeOfDay 8 0 0)
                    ]
                afterMidnightEntry <- createAndApproveEntry fixture.venue fixture.avaStaff goldenWeekEnd fixture.snapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.barShift.id)
                    , set #calendarDayOffset 1
                    , setTestStartTime (TimeOfDay 2 0 0)
                    , setTestEndTime (TimeOfDay 5 0 0)
                    ]

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                let csvRows = csvRowsByKey (fromMaybe "" exportJob.fileContents)
                    workerHours = lookupCsvRow csvRows "Worker, Ava LVL 2"

                drop (length workerHours - 3) workerHours `shouldBe` ["1.000000", "2.000000", "6.000000"]
                map (.operationalDate) [earlyEntry, afterMidnightEntry] `shouldBe` replicate 2 goldenWeekEnd

        it "aggregates exact staff time before one quarter-hour tie-up transform" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                let fractionalShift =
                        [ set #shiftTypeId (unpackId fixture.kitchenShift.id)
                        , setTestStartTime (TimeOfDay 9 0 0)
                        , setTestEndTime (TimeOfDay 9 3 45)
                        ]
                _ <- createAndApproveEntry fixture.venue fixture.kaiStaff goldenWeekStart fixture.snapshot fixture.admin fixture.approvedAt fractionalShift
                _ <- createAndApproveEntry fixture.venue fixture.kaiStaff goldenWeekStart fixture.snapshot fixture.admin fixture.approvedAt fractionalShift

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                take 3 (lookupCsvRow csvRows "Cook, Kai LVL 1") `shouldBe` ["4.000000", "0.000000", "0.000000"]

        it "renders the canonical payroll earnings CSV shape exactly after normalizing row ids" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue PayrollEarningsCsv
                expectedCsv <- readExportFixtureText "payroll_earnings-expected.normalized.csv"

                get #exportType exportJob `shouldBe` exportJobTypeToText PayrollEarningsCsv
                get #fileName exportJob `shouldBe` Just "payroll_earnings-2025-01-07-to-2025-01-13.csv"
                get #payConfigVersionManifest exportJob `shouldBe` Just "mixed"
                normalizePayrollEarningsCsv (fromMaybe "" (get #fileContents exportJob)) `shouldBe` normalizeExpectedPayrollEarningsCsv expectedCsv

        it "renders canonical hourly staff-hours and wage-total CSV files exactly" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                expectedStaffHours <- readExportFixtureText "hourly_staff_hours-expected.csv"
                expectedWageTotals <- readExportFixtureText "hourly_wage_totals-expected.csv"
                firstStaffHours <- generatePayrollExportJob fixture.admin fixture.venue HourlyBreakdownZip
                secondStaffHours <- generatePayrollExportJob fixture.admin fixture.venue HourlyBreakdownZip
                firstWageTotals <- generatePayrollExportJob fixture.admin fixture.venue HourlyWageTotalsZip
                secondWageTotals <- generatePayrollExportJob fixture.admin fixture.venue HourlyWageTotalsZip
                let staffPath = "2025-01-07_Tuesday_staff_hours.csv"
                    wagePath = "2025-01-07_Tuesday_wage_totals.csv"

                extractZipTextFile staffPath firstStaffHours `shouldBe` expectedStaffHours
                extractZipTextFile wagePath firstWageTotals `shouldBe` expectedWageTotals
                secondStaffHours.fileContents `shouldBe` firstStaffHours.fileContents
                secondWageTotals.fileContents `shouldBe` firstWageTotals.fileContents

        it "renders the canonical Payroll Workbook deterministically through the fixed export lifecycle" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                firstWorkbook <- generatePayrollExportJob fixture.admin fixture.venue PayrollWorkbookXlsx
                secondWorkbook <- generatePayrollExportJob fixture.admin fixture.venue PayrollWorkbookXlsx

                firstWorkbook.id `shouldNotBe` secondWorkbook.id
                firstWorkbook.fileContents `shouldBe` secondWorkbook.fileContents
                let workbookBytes =
                        firstWorkbook.fileContents
                            |> fromMaybe (error "expected Payroll Workbook bytes")
                            |> encodeUtf8
                            |> Base64.decodeLenient
                            |> LBS.fromStrict
                let archive = Zip.toArchive workbookBytes
                forM_ ["xl/worksheets/sheet15.xml", "xl/worksheets/sheet30.xml"] \path ->
                    Zip.filesInArchive archive `shouldSatisfy` (path `elem`)
                let workbookXml = extractArchiveText "xl/workbook.xml" archive
                workbookXml `shouldSatisfy` Text.isInfixOf "Summary 2025-01-07"
                workbookXml `shouldSatisfy` Text.isInfixOf "Hours Tue 2025-01-07"
                workbookXml `shouldSatisfy` Text.isInfixOf "Shift Type Hours Tue 2025-01-07"
                workbookXml `shouldSatisfy` Text.isInfixOf "Wages Mon 2025-01-13"
                workbookXml `shouldSatisfy` Text.isInfixOf "Shift Type Wages Mon 2025-01-13"
                workbookXml `shouldSatisfy` Text.isInfixOf "name=\"Data\""
                workbookXml `shouldSatisfy` Text.isInfixOf "state=\"hidden\""

        it "keeps repeated CSV and ZIP jobs distinct with deterministic contents" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                firstCsv <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                secondCsv <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                firstZip <- generatePayrollExportJob fixture.admin fixture.venue HourlyBreakdownZip
                secondZip <- generatePayrollExportJob fixture.admin fixture.venue HourlyBreakdownZip

                firstCsv.id `shouldNotBe` secondCsv.id
                firstCsv.fileContents `shouldBe` secondCsv.fileContents
                firstZip.id `shouldNotBe` secondZip.id
                firstZip.fileContents `shouldBe` secondZip.fileContents

        it "keeps only approved non-trial hours and buckets canonical rows into the expected days" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                inactiveStaff <- createStaffRecord fixture.venue Nothing "Inactive" "Worker"
                    >>= updateRecord . set #payAssignmentMode AwardRate . set #defaultAwardLevelId (Just fixture.levelOne.id)
                _ <- createAndApproveEntry fixture.venue inactiveStaff goldenWeekStart fixture.snapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.floorShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 11 0 0)
                    ]
                _ <- inactiveStaff |> set #isActive False |> updateRecord
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe` ["Cook, Kai LVL 1", "Worker, Ava LVL 1", "Worker, Ava LVL 2"]
                lookupCsvRow csvRows "Worker, Ava LVL 1" `shouldBe` ["2.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000"]
                lookupCsvRow csvRows "Worker, Ava LVL 2" `shouldBe` ["2.500000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "5.000000", "0.000000", "4.500000", "0.000000", "0.000000", "0.000000"]
                lookupCsvRow csvRows "Cook, Kai LVL 1" `shouldBe` ["0.000000", "0.000000", "0.000000", "4.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000"]

        it "keeps explicit Operational-date export windows stable after the venue roster start day changes" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                beforeChange <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                _ <- venueConfig |> set #rosterWeekStartsOn 5 |> updateRecord

                afterChange <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv

                afterChange.id `shouldNotBe` beforeChange.id
                afterChange.rangeStart `shouldBe` beforeChange.rangeStart
                afterChange.rangeEnd `shouldBe` beforeChange.rangeEnd
                afterChange.fileName `shouldBe` beforeChange.fileName
                afterChange.fileContents `shouldBe` beforeChange.fileContents

        it "keeps relational-version-pinned payroll CSV output stable after later pay-config changes" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                expectedCsv <- readExportFixtureText "staff_hours-expected.csv"

                _ <- fixture.barShift
                    |> set #payAssignmentMode RosterOnly
                    |> set #overrideAwardLevelId Nothing
                    |> updateRecord
                _ <- fixture.avaStaff
                    |> set #payAssignmentMode RosterOnly
                    |> set #defaultAwardLevelId Nothing
                    |> updateRecord

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv

                get #payConfigVersionManifest exportJob `shouldBe` Just "mixed"
                unsafeStripCarriageReturns (fromMaybe "" (get #fileContents exportJob)) `shouldBe` unsafeStripCarriageReturns expectedCsv

        it "marks payroll exports as mixed when approved rows span multiple pay version manifests" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixtureForWeek goldenWeekStart
                secondSnapshot <- createPayrollSnapshotWithVersion fixture.venue fixture.admin 2 [fixture.levelOne, fixture.levelTwo] [fixture.barShift, fixture.floorShift, fixture.kitchenShift] fixture.dayNames []
                _ <- createAndApproveEntry fixture.venue fixture.kaiStaff goldenWeekEnd secondSnapshot fixture.admin fixture.approvedAt
                    [ set #shiftTypeId (unpackId fixture.kitchenShift.id)
                    , setTestStartTime (TimeOfDay 10 0 0)
                    , setTestEndTime (TimeOfDay 12 0 0)
                    ]

                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                get #payConfigVersionManifest exportJob `shouldBe` Just "mixed"
                lookupCsvRow csvRows "Cook, Kai LVL 1" `shouldBe` ["0.000000", "0.000000", "0.000000", "4.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "0.000000", "2.000000", "0.000000", "0.000000"]

        it "aggregates multiple staff, employment bases, roles, breaks, and overnight penalty buckets" $ withContext do
            withCleanDb do
                fixture <- seedPayrollMatrixFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue StaffPayCsv
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe`
                    [ "Casual, Ben LVL 1"
                    , "Casual, Cara LVL 1"
                    , "Cook, Noor LVL 3"
                    , "Manager, Ava LVL 2"
                    , "Manager, Ava LVL 4"
                    ]
                lookupCsvRow csvRows "Manager, Ava LVL 2" `shouldBe`
                    [ "4.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000"
                    , "6.500000"
                    , "0.000000", "0.000000", "1.000000"
                    ]
                lookupCsvRow csvRows "Manager, Ava LVL 4" `shouldBe`
                    [ "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "5.500000", "0.000000"
                    , "2.000000"
                    , "0.000000", "0.000000", "0.000000"
                    ]
                lookupCsvRow csvRows "Casual, Ben LVL 1" `shouldBe`
                    [ "0.000000", "0.000000", "0.000000"
                    , "6.500000", "0.000000", "1.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "5.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000"
                    , "0.000000"
                    ]
                lookupCsvRow csvRows "Casual, Cara LVL 1" `shouldBe`
                    [ "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "3.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000"
                    , "0.000000"
                    ]
                lookupCsvRow csvRows "Cook, Noor LVL 3" `shouldBe`
                    [ "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000", "0.000000"
                    , "0.000000", "0.000000"
                    , "0.000000"
                    , "5.666667", "0.000000", "0.000000"
                    ]

    where
        unsafeStripCarriageReturns = Text.replace "\r" ""

normalizePayrollEarningsCsv :: Text -> Text
normalizePayrollEarningsCsv csvText =
    csvText
        |> Text.replace "\r" ""
        |> normalizeRateBookVersions
        |> Text.lines
        |> map normalizeRow
        |> Text.unlines
    where
        normalizeRow row
            | Text.isPrefixOf "staff_first_name," row = row
            | otherwise =
                let fields = Text.splitOn "," row
                 in if length fields /= 26
                        then row
                        else Text.intercalate "," (normalizeField <$> zip [0 :: Int ..] fields)

        normalizeField (index, value)
            | index == 12 = "<description>"
            | index == 13 = "<staff_id>"
            | index == 14 = "<timesheet_entry_ids>"
            | index == payConfigVersionManifestColumn = "<pay_config_version_manifest>"
            | index == rateBookVersionColumn = "<rate_book_version>"
            | index == sourceRateIdentityColumn = "<source_rate_identity>"
            | index == approvedByUserIdsColumn = "<approved_by_user_ids>"
            | index == activePayCalculationIdsColumn = "<active_pay_calculation_ids>"
            | otherwise = value

payConfigVersionManifestColumn, rateBookVersionColumn, sourceRateIdentityColumn, approvedByUserIdsColumn, activePayCalculationIdsColumn :: Int
payConfigVersionManifestColumn = 15
rateBookVersionColumn = 18
sourceRateIdentityColumn = 20
approvedByUserIdsColumn = 24
activePayCalculationIdsColumn = 25

normalizeRateBookVersions :: Text -> Text
normalizeRateBookVersions input =
    case Text.breakOn ",\"MA000009:" input of
        (before, rest)
            | Text.null rest -> input
            | otherwise ->
                let afterPrefix = Text.drop (Text.length (",\"MA000009:" :: Text)) rest
                    (_, afterVersion) = Text.breakOn "\"," afterPrefix
                 in before <> ",<rate_book_version>" <> normalizeRateBookVersions (Text.drop 1 afterVersion)

normalizeExpectedPayrollEarningsCsv :: Text -> Text
normalizeExpectedPayrollEarningsCsv =
    Text.replace "\r" ""

data PayrollMatrixFixture = PayrollMatrixFixture
    { venue :: !Venue
    , admin :: !User
    }

seedPayrollMatrixFixture :: (?modelContext :: ModelContext) => IO PayrollMatrixFixture
seedPayrollMatrixFixture = do
    let weekStart = goldenWeekStart
    let dayAt offset = addDays offset weekStart
    let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
    venue <- createVenueWithConfig "Payroll Matrix Venue"
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    _ <- venueConfig |> set #rosterWeekStartsOn 2 |> updateRecord
    admin <- createUserRecord "payroll-matrix-admin@example.com" "staff" True
    _ <- createVenueMembershipRecord venue admin VenueAdmin
    dayNames <- seedWeekDayNames venue
    levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 3 6 1 1.5 1.75
    levelTwo <- createPayLevelRecordWithRates venue "LVL 2" 36 4 8 1 1.5 1.75
    levelThree <- createPayLevelRecordWithRates venue "LVL 3" 42 5 10 1 1.5 1.75
    levelFour <- createPayLevelRecordWithRates venue "LVL 4" 48 6 12 1 1.5 1.75
    barShift <- createShiftTypeRecord venue levelTwo "Bar"
        >>= updateRecord
            . set #sortOrder 10
            . set #payAssignmentMode StaffDefault
            . set #overrideAwardLevelId Nothing
    supervisorShift <- createShiftTypeRecord venue levelFour "Supervisor"
        >>= updateRecord . set #sortOrder 20
    kitchenShift <- createShiftTypeRecord venue levelThree "Kitchen"
        >>= updateRecord . set #sortOrder 30

    avaUser <- createUserRecord "payroll-matrix-ava@example.com" "staff" True
    benUser <- createUserRecord "payroll-matrix-ben@example.com" "staff" True
    caraUser <- createUserRecord "payroll-matrix-cara@example.com" "staff" True
    noorUser <- createUserRecord "payroll-matrix-noor@example.com" "staff" True
    ava <- createStaffRecord venue (Just avaUser) "Ava" "Manager"
        >>= updateRecord
            . set #employmentBasis Permanent
            . set #payAssignmentMode AwardRate
            . set #defaultAwardLevelId (Just levelTwo.id)
    ben <- createStaffRecord venue (Just benUser) "Ben" "Casual"
        >>= updateRecord
            . set #employmentBasis Casual
            . set #payAssignmentMode AwardRate
            . set #defaultAwardLevelId (Just levelOne.id)
    cara <- createStaffRecord venue (Just caraUser) "Cara" "Casual"
        >>= updateRecord
            . set #employmentBasis Casual
            . set #payAssignmentMode AwardRate
            . set #defaultAwardLevelId (Just levelOne.id)
    noor <- createStaffRecord venue (Just noorUser) "Noor" "Cook"
        >>= updateRecord
            . set #employmentBasis Permanent
            . set #payAssignmentMode AwardRate
            . set #defaultAwardLevelId (Just levelOne.id)
    seedCasualBaseRate levelOne 37.5
    snapshot <- createPayrollSnapshot venue admin [levelOne, levelTwo, levelThree, levelFour] [barShift, supervisorShift, kitchenShift] dayNames []

    _ <- createAndApproveEntry venue ava (dayAt 0) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , setTestStartTime (TimeOfDay 8 0 0)
        , setTestEndTime (TimeOfDay 12 0 0)
        ]
    _ <- createAndApproveEntry venue ava (dayAt 4) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId supervisorShift.id)
        , setTestStartTime (TimeOfDay 18 0 0)
        , setTestEndTime (TimeOfDay 2 0 0)
        , setTestHadBreak True
        , setTestBreakMinutes 30
        , setTestBreakStartTime (Just (TimeOfDay 22 0 0))
        , setTestBreakEndTime (Just (TimeOfDay 22 30 0))
        ]
    _ <- createAndApproveEntry venue ava (dayAt 5) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , setTestStartTime (TimeOfDay 17 0 0)
        , setTestEndTime (TimeOfDay 1 0 0)
        , setTestHadBreak True
        , setTestBreakMinutes 30
        , setTestBreakStartTime (Just (TimeOfDay 21 0 0))
        , setTestBreakEndTime (Just (TimeOfDay 21 30 0))
        ]
    _ <- createAndApproveEntry venue ben (dayAt 1) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , setTestStartTime (TimeOfDay 6 0 0)
        , setTestEndTime (TimeOfDay 14 0 0)
        , setTestHadBreak True
        , setTestBreakMinutes 30
        , setTestBreakStartTime (Just (TimeOfDay 10 0 0))
        , setTestBreakEndTime (Just (TimeOfDay 10 30 0))
        ]
    _ <- createAndApproveEntry venue ben (dayAt 3) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , setTestStartTime (TimeOfDay 19 0 0)
        , setTestEndTime (TimeOfDay 0 0 0)
        ]
    _ <- createAndApproveEntry venue cara (dayAt 2) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , setTestStartTime (TimeOfDay 9 0 0)
        , setTestEndTime (TimeOfDay 12 0 0)
        ]
    _ <- createAndApproveEntry venue noor (dayAt 6) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId kitchenShift.id)
        , setTestStartTime (TimeOfDay 11 0 0)
        , setTestEndTime (TimeOfDay 17 0 0)
        , setTestHadBreak True
        , setTestBreakMinutes 20
        , setTestBreakStartTime (Just (TimeOfDay 13 30 0))
        , setTestBreakEndTime (Just (TimeOfDay 13 50 0))
        ]

    pure PayrollMatrixFixture { venue, admin }

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
        parseCsvRow row
            | Text.isPrefixOf "\"" row =
                let (quotedName, remainder) = Text.breakOn "\"," (Text.drop 1 row)
                 in if Text.null remainder
                        then error ("Unexpected quoted payroll CSV row: " <> row)
                        else (Text.replace "\"\"" "\"" quotedName, Text.splitOn "," (Text.drop 2 remainder))
            | otherwise =
                let (nameType, remainder) = Text.breakOn "," row
                 in (nameType, Text.splitOn "," (Text.drop 1 remainder))

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
    ExportJobType ->
    IO ExportJob
generatePayrollExportJob user venue =
    generatePayrollExportJobForRange user venue goldenWeekStart goldenWeekEnd

generatePayrollExportJobForRange ::
    (?mocking :: MockContext WebApplication, ?request :: Request, ?respond :: Respond, ?modelContext :: ModelContext, ?application :: WebApplication) =>
    User ->
    Venue ->
    Day ->
    Day ->
    ExportJobType ->
    IO ExportJob
generatePayrollExportJobForRange user venue rangeStart rangeEnd exportType = do
    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
        callActionWithParams CreateExportJobAction
            [ ("exportType", cs (exportJobTypeToText exportType))
            , ("rangeStart", cs (tshow rangeStart))
            , ("rangeEnd", cs (tshow rangeEnd))
            ]

    response `responseStatusShouldBe` status302

    query @ExportJob
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#requestedByUserId, unpackId user.id)
        |> orderByDesc #createdAt
        |> fetchOne

extractZipTextFile :: FilePath -> ExportJob -> Text
extractZipTextFile filePath exportJob =
    case Base64.decode (encodeUtf8 (fromMaybe "" exportJob.fileContents)) of
        Left message -> error ("Invalid export ZIP base64: " <> cs message)
        Right bytes ->
            Zip.toArchive (LBS.fromStrict bytes)
                |> Zip.findEntryByPath filePath
                |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                |> fromMaybe (error ("Missing export ZIP file: " <> cs filePath))

extractArchiveText :: FilePath -> Zip.Archive -> Text
extractArchiveText filePath archive =
    archive
        |> Zip.findEntryByPath filePath
        |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
        |> fromMaybe (error ("Missing workbook archive file: " <> cs filePath))

readExportFixtureText :: FilePath -> IO Text
readExportFixtureText fixtureName =
    Text.readFile ("Test/Fixtures/exports/" <> fixtureName)
