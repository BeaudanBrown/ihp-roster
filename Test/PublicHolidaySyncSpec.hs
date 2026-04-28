module Test.PublicHolidaySyncSpec where

import Application.PublicHolidays.Sync
import Config
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
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = do
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

    beforeAll testContext do
        describe "DataVic public holiday import" do
            it "inserts and then updates matching statewide holiday rows" $ withContext do
                withCleanDb do
                    firstSummary <- importDataVicPublicHolidayRecordsForYear 2026 [melbourneCupRecord]
                    firstSummary.targetYear `shouldBe` 2026
                    firstSummary.fetchedCount `shouldBe` 1
                    firstSummary.importedCount `shouldBe` 1
                    firstSummary.insertedCount `shouldBe` 1
                    firstSummary.updatedCount `shouldBe` 0
                    firstSummary.skippedCount `shouldBe` 0
                    firstSummary.prunedCount `shouldBe` 0

                    secondSummary <-
                        importDataVicPublicHolidayRecordsForYear 2026
                            [updatedMelbourneCupRecord]
                    secondSummary.fetchedCount `shouldBe` 1
                    secondSummary.importedCount `shouldBe` 1
                    secondSummary.insertedCount `shouldBe` 0
                    secondSummary.updatedCount `shouldBe` 1
                    secondSummary.skippedCount `shouldBe` 0
                    secondSummary.prunedCount `shouldBe` 0

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

            it "skips upstream rows outside the target year and prunes stale cached VIC rows" $ withContext do
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
                        importDataVicPublicHolidayRecordsForYear 2026
                            [ melbourneCupRecord
                            , melbourneCupRecord { importantDate = "25/12/2025", name = "Christmas Day" }
                            ]

                    summary.targetYear `shouldBe` 2026
                    summary.fetchedCount `shouldBe` 2
                    summary.importedCount `shouldBe` 1
                    summary.insertedCount `shouldBe` 1
                    summary.updatedCount `shouldBe` 0
                    summary.skippedCount `shouldBe` 1
                    summary.prunedCount `shouldBe` 1

                    vicHolidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> fetch
                    map (.holidayDate) vicHolidays `shouldBe` [fromGregorian 2026 11 3]

                    nswHolidayCount <- query @PublicHoliday |> filterWhere (#jurisdiction, "NSW" :: Text) |> fetchCount
                    nswHolidayCount `shouldBe` 1

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
