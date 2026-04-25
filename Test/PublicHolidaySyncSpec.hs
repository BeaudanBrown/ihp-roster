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
                    firstSummary <- importDataVicPublicHolidayRecords [melbourneCupRecord]
                    firstSummary.fetchedCount `shouldBe` 1
                    firstSummary.importedCount `shouldBe` 1
                    firstSummary.insertedCount `shouldBe` 1
                    firstSummary.updatedCount `shouldBe` 0

                    secondSummary <-
                        importDataVicPublicHolidayRecords
                            [updatedMelbourneCupRecord]
                    secondSummary.fetchedCount `shouldBe` 1
                    secondSummary.importedCount `shouldBe` 1
                    secondSummary.insertedCount `shouldBe` 0
                    secondSummary.updatedCount `shouldBe` 1

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
