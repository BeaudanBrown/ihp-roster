module Test.PublicHolidaySyncSpec where

import Application.PublicHolidays.Coverage
import Application.PublicHolidays.Sync
import Config
import qualified Control.Exception as Exception
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.DataVicFixture (loadDataVicHolidayFixture)
import Web.FrontController ()
import Web.Routes
import Web.Types

pureTests :: Spec
pureTests = do
    describe "DataVic public holiday parsing" do
        it "parses D/MM/YYYY dates" do
            parseDataVicDate "3/11/2026" `shouldBe` Right (fromGregorian 2026 11 3)
            parseDataVicDate "25/12/2026" `shouldBe` Right (fromGregorian 2026 12 25)

        it "normalizes statewide DataVic public holiday records" do
            publicHolidayImportFromDataVic melbourneCupRecord
                `shouldBe`
                    Right
                        PublicHolidayImport
                            { jurisdiction = "VIC"
                            , holidayDate = fromGregorian 2026 11 3
                            , name = "Melbourne Cup"
                            , region = Nothing
                            , isRegional = False
                            , source = Just "Business Victoria"
                            , sourceId = Just "data-vic-row-1"
                            , sourceUrl = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
                            , description = Just "Melbourne Cup Day is a public holiday across all of Victoria unless alternate local holiday has been arranged by a non-metro council."
                            }

        it "skips non-public-holiday records" do
            publicHolidayImportFromDataVic melbourneCupRecord { dateType = "SCHOOL_TERM" }
                `shouldSatisfy` isLeft

        it "decodes the dated DataVic response fixture without a live request" do
            records <- loadDataVicHolidayFixture

            length records `shouldBe` 13
            map (.dateType) records `shouldSatisfy` all (== "PUBLIC_HOLIDAY")
            map (.importantDate) records
                `shouldSatisfy` \dates -> all (`elem` dates) ["3/11/2026", "25/12/2026", "28/12/2026"]
            map (.publisher) records `shouldSatisfy` all (== Just "Business Victoria")

databaseTests :: Spec
databaseTests = do
    aroundAll withDatabaseTestContext do
        describe "DataVic public holiday import" do
            it "projects the dated statewide fixture, including its additional public holiday, into the 2026 cache" $ withContext do
                withCleanDb do
                    records <- loadDataVicHolidayFixture

                    summary <- importDataVicPublicHolidayRecordsForYears [2026] records
                    holidays <- query @PublicHoliday |> orderByAsc #holidayDate |> fetch

                    summary.fetchedCount `shouldBe` 13
                    summary.importedCount `shouldBe` 13
                    summary.skippedCount `shouldBe` 0
                    length holidays `shouldBe` 13
                    map (.jurisdiction) holidays `shouldSatisfy` all (== "VIC")
                    map (.isRegional) holidays `shouldSatisfy` all not
                    map (.source) holidays `shouldSatisfy` all (== Just "Business Victoria")
                    map (.holidayDate) holidays
                        `shouldSatisfy` \dates ->
                            all
                                (`elem` dates)
                                [ fromGregorian 2026 11 3
                                , fromGregorian 2026 12 25
                                , fromGregorian 2026 12 28
                                ]

            it "replaces matching statewide holiday rows from the latest API read" $ withContext do
                withCleanDb do
                    firstSummary <- importDataVicPublicHolidayRecordsForYears [2026] [melbourneCupRecord]
                    firstSummary.targetYears `shouldBe` [2026]
                    firstSummary.fetchedCount `shouldBe` 1
                    firstSummary.importedCount `shouldBe` 1
                    firstSummary.insertedCount `shouldBe` 1
                    firstSummary.updatedCount `shouldBe` 0
                    firstSummary.skippedCount `shouldBe` 0
                    firstSummary.prunedCount `shouldBe` 0

                    secondSummary <-
                        importDataVicPublicHolidayRecordsForYears [2026]
                            [updatedMelbourneCupRecord]
                    secondSummary.fetchedCount `shouldBe` 1
                    secondSummary.importedCount `shouldBe` 1
                    secondSummary.insertedCount `shouldBe` 1
                    secondSummary.updatedCount `shouldBe` 0
                    secondSummary.skippedCount `shouldBe` 0
                    secondSummary.prunedCount `shouldBe` 1

                    holidays <- query @PublicHoliday |> fetch
                    length holidays `shouldBe` 1
                    case holidays of
                        [holiday] -> do
                            holiday.jurisdiction `shouldBe` "VIC"
                            holiday.holidayDate `shouldBe` fromGregorian 2026 11 3
                            holiday.name `shouldBe` "Melbourne Cup"
                            holiday.source `shouldBe` Just "Business Victoria"
                            holiday.sourceId `shouldBe` Just "data-vic-row-1"
                            holiday.description `shouldBe` Just "Updated description"
                            holiday.importedAt `shouldSatisfy` isJust
                        _ -> expectationFailure "Expected exactly one public holiday"

            it "skips upstream rows outside target years and reconciles stale cached VIC statewide rows" $ withContext do
                withCleanDb do
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "VIC"
                            |> set #holidayDate (fromGregorian 2025 12 25)
                            |> set #name "Christmas Day"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "NSW"
                            |> set #holidayDate (fromGregorian 2025 12 25)
                            |> set #name "Christmas Day"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord

                    summary <-
                        importDataVicPublicHolidayRecordsForYears [2026, 2027]
                            [ melbourneCupRecord
                            , melbourneCupRecord { importantDate = "25/12/2025", name = "Christmas Day" }
                            ]

                    summary.targetYears `shouldBe` [2026, 2027]
                    summary.fetchedCount `shouldBe` 2
                    summary.importedCount `shouldBe` 1
                    summary.insertedCount `shouldBe` 1
                    summary.updatedCount `shouldBe` 0
                    summary.skippedCount `shouldBe` 1
                    summary.prunedCount `shouldBe` 0

                    vicHolidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> orderBy #holidayDate |> fetch
                    map (.holidayDate) vicHolidays `shouldBe` [fromGregorian 2025 12 25, fromGregorian 2026 11 3]

                    nswHolidayCount <- query @PublicHoliday |> filterWhere (#jurisdiction, "NSW" :: Text) |> fetchCount
                    nswHolidayCount `shouldBe` 1

            it "fails the whole import before mutating cached target years when any record is invalid" $ withContext do
                withCleanDb do
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "VIC"
                            |> set #holidayDate (fromGregorian 2026 11 3)
                            |> set #name "Existing Melbourne Cup"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord

                    result <- Exception.try (importDataVicPublicHolidayRecordsForYears [2026] [melbourneCupRecord { importantDate = "not-a-date" }])
                    case result of
                        Left (_ :: Exception.SomeException) -> pure ()
                        Right _ -> expectationFailure "Expected invalid DataVic record to fail the import"

                    holidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> fetch
                    map (.name) holidays `shouldBe` ["Existing Melbourne Cup"]

            it "reports missing public holiday coverage as warnings" $ withContext do
                withCleanDb do
                    coverage <- fetchPublicHolidayCoverage
                    length coverage `shouldBe` 3
                    map (.status) coverage `shouldSatisfy` all (== PublicHolidayCoverageMissing)

melbourneCupRecord :: DataVicHolidayRecord
melbourneCupRecord =
    DataVicHolidayRecord
        { arun = Just "data-vic-row-1"
        , dateType = "PUBLIC_HOLIDAY"
        , name = " Melbourne Cup "
        , importantDate = "3/11/2026"
        , publisher = Just "Business Victoria"
        , description = Just "Melbourne Cup Day is a public holiday across all of Victoria unless alternate local holiday has been arranged by a non-metro council."
        , source = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
        }

updatedMelbourneCupRecord :: DataVicHolidayRecord
updatedMelbourneCupRecord =
    DataVicHolidayRecord
        { arun = Just "data-vic-row-1"
        , dateType = "PUBLIC_HOLIDAY"
        , name = " Melbourne Cup "
        , importantDate = "3/11/2026"
        , publisher = Just "Business Victoria"
        , description = Just "Updated description"
        , source = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
        }
