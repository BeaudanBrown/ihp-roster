module Test.Controller.PayrollExportParitySpec where

import Application.Helper.Export
import Config
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time.Calendar (fromGregorian)
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

        it "keeps only approved non-trial hours and buckets canonical rows into the expected days" $ withContext do
            withCleanDb do
                fixture <- seedCanonicalPayrollFixture
                exportJob <- generatePayrollExportJob fixture.admin fixture.venue "staff_hours" 0
                let csvRows = csvRowsByKey (fromMaybe "" (get #fileContents exportJob))

                Map.keys csvRows `shouldBe` [("Ava", "LVL 1"), ("Ava", "LVL 2"), ("Kai", "LVL 1")]
                lookupCsvRow csvRows "Ava" "LVL 1" `shouldBe` ["2.00", "0.00", "0.00", "0.00", "0.00", "0.00", "0.00", "2.00"]
                lookupCsvRow csvRows "Ava" "LVL 2" `shouldBe` ["2.50", "0.00", "0.00", "0.00", "6.00", "3.50", "0.00", "12.00"]
                lookupCsvRow csvRows "Kai" "LVL 1" `shouldBe` ["0.00", "4.00", "0.00", "0.00", "0.00", "0.00", "0.00", "4.00"]

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
                lookupCsvRow csvRows "Kai" "LVL 1" `shouldBe` ["0.00", "4.00", "0.00", "0.00", "0.00", "0.00", "2.00", "6.00"]
    where
        unsafeStripCarriageReturns = Text.replace "\r" ""

csvRowsByKey :: Text -> Map.Map (Text, Text) [Text]
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
                name : label : values -> ((name, label), values)
                _ -> error ("Unexpected payroll CSV row: " <> row)

        unsafeStripCarriageReturns = Text.replace "\r" ""

lookupCsvRow :: Map.Map (Text, Text) [Text] -> Text -> Text -> [Text]
lookupCsvRow csvRows staffName label =
    csvRows
        |> Map.lookup (staffName, label)
        |> fromMaybe (error ("Missing payroll CSV row for " <> staffName <> " / " <> label))

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
