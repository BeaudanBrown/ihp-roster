module Test.PayrollWorkbookSpec where

import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.Types
import qualified "zip-archive" Codec.Archive.Zip as Zip
import qualified Codec.Xlsx as Xlsx
import Control.Exception (bracket)
import "crypton" Crypto.Hash (Digest, SHA256, hashlazy)
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isRight)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import Data.Time.Calendar (fromGregorian)
import qualified Data.UUID as UUID
import IHP.Prelude
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory,
                         removeFile)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.IO (hClose, hIsClosed, openBinaryTempFile)
import System.Process (readProcessWithExitCode)
import Test.Hspec

tests :: Spec
tests = do
    describe "Payroll Workbook XLSX foundation" do
        it "renders deterministic typed cells and workbook presentation primitives" do
            let workbook = minimalPayrollWorkbook (fromGregorian 2025 1 6) (fromGregorian 2025 1 12)
            let firstRender = renderPayrollWorkbook workbook
            let secondRender = renderPayrollWorkbook workbook
            firstRender `shouldBe` secondRender
            show (hashlazy firstRender :: Digest SHA256)
                `shouldBe` "36faa7a22e81c63a26546fe5eda735e2c1eb0f16b8c15ce0af6c8f8b8044a784"
            LBS.take 2 firstRender `shouldBe` "PK"
            Xlsx.toXlsxEither firstRender `shouldSatisfy` isRight

            let archive = Zip.toArchive firstRender
            forM_ ["xl/worksheets/sheet1.xml", "xl/styles.xml", "xl/sharedStrings.xml"] \path ->
                Zip.filesInArchive archive `shouldSatisfy` elem path
            sheetXml <- archiveText "xl/worksheets/sheet1.xml" archive
            stylesXml <- archiveText "xl/styles.xml" archive
            sharedStringsXml <- archiveText "xl/sharedStrings.xml" archive

            sheetXml `shouldSatisfy` Text.isInfixOf "<sheetPr><tabColor rgb=\"FF4472C4\"/></sheetPr>"
            sheetXml `shouldSatisfy` Text.isInfixOf "hidden=\"1\""
            sheetXml `shouldSatisfy` Text.isInfixOf "state=\"frozen\""
            sheetXml `shouldSatisfy` Text.isInfixOf "topLeftCell=\"B2\""
            sheetXml `shouldSatisfy` Text.isInfixOf "ref=\"A1:C2\""
            sheetXml `shouldSatisfy` Text.isInfixOf "SUM(B2:B2)"
            stylesXml `shouldSatisfy` Text.isInfixOf "D9EAF7"
            stylesXml `shouldSatisfy` Text.isInfixOf "formatCode=\"0.00\""
            sharedStringsXml `shouldSatisfy` Text.isInfixOf "Payroll Workbook"

        it "normalizes RGB colours and rejects malformed colours" do
            payrollWorkbookColor "4472c4" `shouldBe` payrollWorkbookColor "FF4472C4"
            payrollWorkbookColor "blue" `shouldBe` Left "Workbook colours must be six-digit RGB or eight-digit ARGB hexadecimal values."

    describe "Payroll Workbook locked rendering contract" do
        it "orders partial and multi-week sheets and emits exact daily and stable-key Summary formulas" do
            let rangeStart = fromGregorian 2025 1 6
            let rangeEnd = fromGregorian 2025 1 14
            let slots =
                    [ PayrollWorkbookHourSlot 18 FirstHourlyOccurrence
                    , PayrollWorkbookHourSlot 19 FirstHourlyOccurrence
                    , PayrollWorkbookHourSlot 24 FirstHourlyOccurrence
                    ]
            let row = workbookRow [0, 1.25, 2] [0, 1234, 567]
            let days =
                    [ PayrollWorkbookDay date (if date `elem` [rangeStart, rangeEnd] then [row] else [])
                    | date <- [rangeStart .. rangeEnd]
                    ]
            let model = PayrollWorkbookHourlyModel rangeStart rangeEnd (HourlyReportWindow 18 25) slots days
            let workbook = payrollWorkbookFromHourlyModel 1 model
            map (.name) workbook.sheets
                `shouldBe`
                    [ "Summary 2025-01-06"
                    , "Summary 2025-01-13"
                    , "Hours Mon 2025-01-06"
                    , "Hours Tue 2025-01-07"
                    , "Hours Wed 2025-01-08"
                    , "Hours Thu 2025-01-09"
                    , "Hours Fri 2025-01-10"
                    , "Hours Sat 2025-01-11"
                    , "Hours Sun 2025-01-12"
                    , "Hours Mon 2025-01-13"
                    , "Hours Tue 2025-01-14"
                    , "Wages Mon 2025-01-06"
                    , "Wages Tue 2025-01-07"
                    , "Wages Wed 2025-01-08"
                    , "Wages Thu 2025-01-09"
                    , "Wages Fri 2025-01-10"
                    , "Wages Sat 2025-01-11"
                    , "Wages Sun 2025-01-12"
                    , "Wages Mon 2025-01-13"
                    , "Wages Tue 2025-01-14"
                    ]

            let firstSummary = workbook.sheets !! 0
            forM_ ["Employee", "Pay level / rate", "Tues Ord", "Thurs 7-12", "Sun Ord", "Sun 12+"] \header ->
                textValues firstSummary `shouldSatisfy` (header `elem`)
            textValues firstSummary `shouldNotContain` ["Total"]
            firstSummary.hiddenColumns `shouldBe` [22, 23]
            formulaValues firstSummary `shouldContain`
                [ "SUMIFS('Hours Mon 2025-01-06'!C:C,'Hours Mon 2025-01-06'!$G:$G,$V2,'Hours Mon 2025-01-06'!$H:$H,$W2)"
                , "SUMIFS('Hours Mon 2025-01-06'!D:D,'Hours Mon 2025-01-06'!$G:$G,$V2,'Hours Mon 2025-01-06'!$H:$H,$W2)"
                , "SUMIFS('Hours Mon 2025-01-06'!E:E,'Hours Mon 2025-01-06'!$G:$G,$V2,'Hours Mon 2025-01-06'!$H:$H,$W2)"
                ]

            let firstHours = workbook.sheets !! 2
            firstHours.hiddenColumns `shouldBe` [7, 8]
            firstHours.frozenRows `shouldBe` 1
            firstHours.frozenColumns `shouldBe` 2
            firstHours.autoFilter `shouldBe` Just (PayrollWorkbookFilter 1 1 2 8)
            forM_ ["SUM(C2:E2)", "SUM(C2:C2)", "SUM(C3:E3)"] \formula ->
                formulaValues firstHours `shouldSatisfy` (formula `elem`)
            numberAt 2 3 firstHours `shouldBe` Just (0, "0.000000;-0.000000;;")

            let firstWages = workbook.sheets !! 11
            numberAt 2 4 firstWages `shouldBe` Just (12.34, "$#,##0.00;[Red]-$#,##0.00;;")

            let rendered = renderPayrollWorkbook workbook
            rendered `shouldBe` renderPayrollWorkbook workbook
            show (hashlazy rendered :: Digest SHA256)
                `shouldBe` "f2c25118dfb64c12e848f6b68ff4e666b95d1418374d062451f5edfa8c41df99"
            Xlsx.toXlsxEither rendered `shouldSatisfy` isRight
            let archive = Zip.toArchive rendered
            summaryXml <- archiveText "xl/worksheets/sheet1.xml" archive
            hoursXml <- archiveText "xl/worksheets/sheet3.xml" archive
            wagesXml <- archiveText "xl/worksheets/sheet12.xml" archive
            stylesXml <- archiveText "xl/styles.xml" archive
            summaryXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FFFFC000\"/>"
            hoursXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FF4472C4\"/>"
            wagesXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FF70AD47\"/>"
            summaryXml `shouldSatisfy` Text.isInfixOf "SUMIFS"
            summaryXml `shouldSatisfy` Text.isInfixOf "Hours Mon 2025-01-06"
            hoursXml `shouldSatisfy` Text.isInfixOf "<f>SUM(C2:E2)</f>"
            hoursXml `shouldNotSatisfy` Text.isInfixOf "<f>SUM(C2:E2)</f><v>"
            stylesXml `shouldSatisfy` Text.isInfixOf "FFFFF2CC"
            stylesXml `shouldSatisfy` Text.isInfixOf "FFD9EAF7"
            stylesXml `shouldSatisfy` Text.isInfixOf "FFE2F0D9"
            stylesXml `shouldSatisfy` Text.isInfixOf "0.000000;-0.000000;;"
            stylesXml `shouldSatisfy` Text.isInfixOf "$#,##0.00;[Red]-$#,##0.00;;"

            let partialStart = fromGregorian 2025 1 7
            let partialEnd = fromGregorian 2025 1 8
            let partialModel = PayrollWorkbookHourlyModel partialStart partialEnd (HourlyReportWindow 18 25) slots
                    [PayrollWorkbookDay partialStart [row], PayrollWorkbookDay partialEnd []]
            let partialWorkbook = payrollWorkbookFromHourlyModel 4 partialModel
            map (.name) partialWorkbook.sheets
                `shouldBe`
                    [ "Summary 2025-01-02"
                    , "Hours Tue 2025-01-07"
                    , "Hours Wed 2025-01-08"
                    , "Wages Tue 2025-01-07"
                    , "Wages Wed 2025-01-08"
                    ]
            let partialSummary = fromMaybe (error "expected partial Summary sheet") (head partialWorkbook.sheets)
            take 3 (formulaValues partialSummary) `shouldBe` replicate 3 "SUM()"

            let fullWeekEnd = fromGregorian 2025 1 12
            let fullWeekModel = PayrollWorkbookHourlyModel rangeStart fullWeekEnd (HourlyReportWindow 18 25) slots
                    [PayrollWorkbookDay date (if date == rangeStart then [row] else []) | date <- [rangeStart .. fullWeekEnd]]
            let fullWeekWorkbook = payrollWorkbookFromHourlyModel 1 fullWeekModel
            length fullWeekWorkbook.sheets `shouldBe` 15
            map (.name) (take 2 fullWeekWorkbook.sheets)
                `shouldBe` ["Summary 2025-01-06", "Hours Mon 2025-01-06"]
            let emptyHoursDay = fullWeekWorkbook.sheets !! 2
            formulaValues emptyHoursDay `shouldBe` ["SUM()", "SUM()", "SUM()", "SUM(C2:E2)"]

            let fortnightEnd = fromGregorian 2025 1 19
            let fortnightModel = PayrollWorkbookHourlyModel rangeStart fortnightEnd (HourlyReportWindow 18 25) slots
                    [PayrollWorkbookDay date (if date `elem` [rangeStart, fortnightEnd] then [row] else []) | date <- [rangeStart .. fortnightEnd]]
            let fortnightWorkbook = payrollWorkbookFromHourlyModel 1 fortnightModel
            length fortnightWorkbook.sheets `shouldBe` 30
            map (.name) (take 2 fortnightWorkbook.sheets)
                `shouldBe` ["Summary 2025-01-06", "Summary 2025-01-13"]
            last (map (.name) fortnightWorkbook.sheets) `shouldBe` "Wages Sun 2025-01-19"

        it "recalculates daily and accountant Summary formulas with LibreOffice Calc" do
            let rangeStart = fromGregorian 2025 1 12
            let rangeEnd = fromGregorian 2025 1 13
            let slots = map (`PayrollWorkbookHourSlot` FirstHourlyOccurrence) [18, 19, 24, 25]
            let firstBucket = workbookRowWith
                    "10000000-0000-0000-0000-000000000001"
                    "20000000-0000-0000-0000-000000000001"
                    "LVL 3"
            let secondBucket = workbookRowWith
                    "10000000-0000-0000-0000-000000000001"
                    "20000000-0000-0000-0000-000000000002"
                    "LVL 4"
            let model = PayrollWorkbookHourlyModel rangeStart rangeEnd (HourlyReportWindow 18 26) slots
                    [ PayrollWorkbookDay rangeStart
                        [ firstBucket [1, 2, 3, 4] [100, 200, 300, 400]
                        , secondBucket [5, 6, 7, 8] [500, 600, 700, 800]
                        ]
                    , PayrollWorkbookDay rangeEnd
                        [firstBucket [0.5, 1.25, 2.25, 0] [50, 125, 225, 0]]
                    ]
            let expectedFormulaValues =
                    [ "Summary 2025-01-06\tT2\t3"
                    , "Summary 2025-01-06\tU2\t7"
                    , "Summary 2025-01-06\tT3\t11"
                    , "Summary 2025-01-06\tU3\t15"
                    , "Summary 2025-01-13\tC2\t0.5"
                    , "Summary 2025-01-13\tD2\t1.25"
                    , "Summary 2025-01-13\tE2\t2.25"
                    , "Hours Sun 2025-01-12\tG2\t10"
                    , "Hours Sun 2025-01-12\tG3\t26"
                    , "Hours Sun 2025-01-12\tG4\t36"
                    , "Wages Sun 2025-01-12\tC4\t6"
                    , "Wages Sun 2025-01-12\tD4\t8"
                    , "Wages Sun 2025-01-12\tE4\t10"
                    , "Wages Sun 2025-01-12\tF4\t12"
                    , "Wages Sun 2025-01-12\tG4\t36"
                    , "Hours Mon 2025-01-13\tG2\t4"
                    , "Hours Mon 2025-01-13\tG3\t4"
                    , "Wages Mon 2025-01-13\tG2\t4"
                    , "Wages Mon 2025-01-13\tG3\t4"
                    ]

            let workbookBytes = renderPayrollWorkbook (payrollWorkbookFromHourlyModel 1 model)
            maybeArtifactPath <- lookupEnv "PAYROLL_WORKBOOK_COMPATIBILITY_ARTIFACT"
            forM_ maybeArtifactPath \artifactPath -> do
                createDirectoryIfMissing True (takeDirectory artifactPath)
                LBS.writeFile artifactPath workbookBytes
            assertLibreOfficeFormulaValues workbookBytes expectedFormulaValues

        it "names repeated DST hour columns explicitly on both daily sheet families" do
            let day = fromGregorian 2026 4 4
            let slots =
                    [ PayrollWorkbookHourSlot 26 FirstHourlyOccurrence
                    , PayrollWorkbookHourSlot 26 SecondHourlyOccurrence
                    ]
            let model = PayrollWorkbookHourlyModel day day (HourlyReportWindow 26 27) slots [PayrollWorkbookDay day [workbookRow [1, 1] [3000, 3000]]]
            let workbook = payrollWorkbookFromHourlyModel 1 model
            let summary = workbook.sheets !! 0
            let hoursSheet = workbook.sheets !! 1
            let wagesSheet = workbook.sheets !! 2
            textValues hoursSheet `shouldContain` ["02:00-03:00+1 (first)", "02:00-03:00+1 (second)"]
            textValues wagesSheet `shouldContain` ["02:00-03:00+1 (first)", "02:00-03:00+1 (second)"]
            formulaValues summary `shouldSatisfy` any (\formula ->
                Text.isInfixOf "'Hours Sat 2026-04-04'!C:C" formula
                    && Text.isInfixOf "'Hours Sat 2026-04-04'!D:D" formula
                    && Text.isInfixOf "+" formula
                )

workbookRow :: [Rational] -> [Integer] -> PayrollWorkbookRow
workbookRow = workbookRowWith
    "10000000-0000-0000-0000-000000000001"
    "20000000-0000-0000-0000-000000000001"
    "LVL 3"

workbookRowWith :: Text -> Text -> Text -> [Rational] -> [Integer] -> PayrollWorkbookRow
workbookRowWith staffId payBucketId payBucketLabel hours wages =
    PayrollWorkbookRow
        { payrollRowStaffId = uuid staffId
        , payrollRowStaffFirstName = "Ada"
        , payrollRowStaffLastName = "Lovelace"
        , payrollRowPayBucket =
            PayrollWorkbookPayBucket
                (PayrollWorkbookAwardLevel (uuid payBucketId))
                payBucketLabel
        , payrollRowHours = hours
        , payrollRowWageCents = wages
        , payrollRowEntryCount = 1
        }

assertLibreOfficeFormulaValues :: LBS.ByteString -> [String] -> IO ()
assertLibreOfficeFormulaValues workbookBytes expectedFormulaValues = do
    temporaryDirectory <- getTemporaryDirectory
    bracket
        (openBinaryTempFile temporaryDirectory "bepis-payroll-workbook.xlsx")
        (\(workbookPath, workbookHandle) -> do
            handleClosed <- hIsClosed workbookHandle
            unless handleClosed (hClose workbookHandle)
            removeFile workbookPath
        )
        (\(workbookPath, workbookHandle) -> do
            LBS.hPut workbookHandle workbookBytes
            hClose workbookHandle
            (exitCode, standardOutput, standardError) <-
                readProcessWithExitCode
                    "timeout"
                    (["--kill-after=5s", "40s", "python3", "Config/nix/scripts/payroll-workbook/libreoffice-recalculate.py", workbookPath] <> expectedFormulaValues)
                    ""
            case exitCode of
                ExitSuccess -> standardOutput `shouldContain` "LibreOffice formula reconciliation passed"
                ExitFailure _ -> expectationFailure (standardOutput <> standardError)
        )

uuid :: Text -> UUID
uuid value = fromMaybe (error "invalid test UUID") (UUID.fromText value)

textValues :: PayrollWorkbookSheet -> [Text]
textValues sheet = [value | PayrollWorkbookCell { value = PayrollWorkbookText value } <- sheet.cells]

formulaValues :: PayrollWorkbookSheet -> [Text]
formulaValues sheet = [value | PayrollWorkbookCell { value = PayrollWorkbookFormula value } <- sheet.cells]

numberAt :: Int -> Int -> PayrollWorkbookSheet -> Maybe (Double, Text)
numberAt row column sheet =
    listToMaybe
        [ (value, fromMaybe "" style.numberFormat)
        | PayrollWorkbookCell { row = cellRow, column = cellColumn, value = PayrollWorkbookNumber value, style } <- sheet.cells
        , cellRow == row
        , cellColumn == column
        ]

archiveText :: FilePath -> Zip.Archive -> IO Text
archiveText path archive =
    case Zip.findEntryByPath path archive of
        Nothing -> expectationFailure ("Missing XLSX archive entry: " <> path) >> pure ""
        Just entry -> pure (decodeUtf8 (LBS.toStrict (Zip.fromEntry entry)))
