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
import Data.Ratio ((%))
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import Data.Time.Calendar (Day, fromGregorian)
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
                `shouldBe` "7c7e2494576bded7741bafb96703759148824590448cc635438fae1f57ed6ffa"
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

        it "publishes deterministic normalized facts as a typed Data worksheet" do
            let (day, factModel) = oneHourFactModel
            let workbook = payrollWorkbookFromFactModel 1 factModel
            map (.name) workbook.sheets
                `shouldBe`
                    [ "Summary 2025-01-06"
                    , "Hours Mon 2025-01-06"
                    , "Shift Type Hours Mon 2025-01-06"
                    , "Wages Mon 2025-01-06"
                    , "Shift Type Wages Mon 2025-01-06"
                    , "Data"
                    ]
            let factsSheet = fromMaybe (error "expected Data sheet") (last workbook.sheets)
            factsSheet.frozenRows `shouldBe` 1
            factsSheet.autoFilter `shouldBe` Just (PayrollWorkbookFilter 1 1 2 20)
            forM_
                [ "Operational Date", "Entry ID", "Shift Type", "Bar"
                , "Pay Bucket Type", "award_level", "Calculation Version"
                , "hospitality-award-v1"
                ] \value -> textValues factsSheet `shouldSatisfy` (value `elem`)
            numberAt 2 12 factsSheet `shouldBe` Just (1, "0.000000;-0.000000;;")
            numberAt 2 13 factsSheet `shouldBe` Just (1.5, "0.000000;-0.000000;;")
            numberAt 2 14 factsSheet `shouldBe` Just (4500, "0")
            numberAt 2 15 factsSheet `shouldBe` Just (45, "$#,##0.00;[Red]-$#,##0.00;;")
            let rendered = renderPayrollWorkbook workbook
            rendered `shouldBe` renderPayrollWorkbook workbook
            Xlsx.toXlsxEither rendered `shouldSatisfy` isRight
            workbookXml <- archiveText "xl/workbook.xml" (Zip.toArchive rendered)
            workbookXml `shouldSatisfy` Text.isInfixOf "name=\"Data\""
            workbookXml `shouldSatisfy` Text.isInfixOf "state=\"hidden\""

    describe "Payroll Workbook composable definitions" do
        it "expands valid presentation families in declared order and always appends hidden Data" do
            let (_, factModel) = oneHourFactModel
            let definition = PayrollWorkbookDefinition
                    { payrollWorkbookDefinitionKey = "wages-first"
                    , payrollWorkbookDefinitionVersion = 1
                    , payrollWorkbookDefinitionSheetFamilies =
                        [ PayrollWorkbookShiftTypeWages
                        , PayrollWorkbookSummary
                        ]
                    }
            workbook <- expectRight (payrollWorkbookFromDefinition definition 1 factModel)
            map (.name) workbook.sheets
                `shouldBe` ["Shift Type Wages Mon 2025-01-06", "Summary 2025-01-06", "Data"]
            map (.hidden) workbook.sheets `shouldBe` [False, False, True]

        it "rejects duplicate, empty, unknown, and unsupported-version definitions" do
            let (_, factModel) = oneHourFactModel
            let definition families = PayrollWorkbookDefinition "custom" 1 families
            payrollWorkbookFromDefinition (definition []) 1 factModel
                `shouldBe` Left "Payroll Workbook definitions require at least one presentation sheet family."
            payrollWorkbookFromDefinition
                (definition [PayrollWorkbookSummary, PayrollWorkbookSummary])
                1
                factModel
                `shouldBe` Left "Payroll Workbook definitions cannot contain duplicate sheet families: summary."
            payrollWorkbookFromDefinition
                (PayrollWorkbookDefinition "custom" 2 [PayrollWorkbookSummary])
                1
                factModel
                `shouldBe` Left "Unsupported Payroll Workbook definition version: 2."
            payrollWorkbookSheetFamilyFromText "shift-type-wages"
                `shouldBe` Right PayrollWorkbookShiftTypeWages
            payrollWorkbookSheetFamilyFromText "arbitrary-formula"
                `shouldBe` Left "Unsupported Payroll Workbook sheet family: arbitrary-formula."

        it "keeps the built-in definition versioned, ordered, and behavior-compatible" do
            defaultPayrollWorkbookDefinition
                `shouldBe` PayrollWorkbookDefinition
                    { payrollWorkbookDefinitionKey = "builtin-default"
                    , payrollWorkbookDefinitionVersion = 1
                    , payrollWorkbookDefinitionSheetFamilies =
                        [ PayrollWorkbookSummary
                        , PayrollWorkbookEmployeePayBucketHours
                        , PayrollWorkbookShiftTypeHours
                        , PayrollWorkbookEmployeePayBucketWages
                        , PayrollWorkbookShiftTypeWages
                        ]
                    }
            let (_, factModel) = oneHourFactModel
            payrollWorkbookFromDefinition defaultPayrollWorkbookDefinition 1 factModel
                `shouldBe` Right (payrollWorkbookFromFactModel 1 factModel)

        it "locks every individual family and representative ordered subsets to deterministic XLSX goldens" do
            let (_, factModel) = oneHourFactModel
            let variants =
                    [ ("summary", [PayrollWorkbookSummary], ["Summary 2025-01-06", "Data"])
                    , ("employee-hours", [PayrollWorkbookEmployeePayBucketHours], ["Hours Mon 2025-01-06", "Data"])
                    , ("shift-hours", [PayrollWorkbookShiftTypeHours], ["Shift Type Hours Mon 2025-01-06", "Data"])
                    , ("employee-wages", [PayrollWorkbookEmployeePayBucketWages], ["Wages Mon 2025-01-06", "Data"])
                    , ("shift-wages", [PayrollWorkbookShiftTypeWages], ["Shift Type Wages Mon 2025-01-06", "Data"])
                    , ("wages-summary", [PayrollWorkbookShiftTypeWages, PayrollWorkbookSummary], ["Shift Type Wages Mon 2025-01-06", "Summary 2025-01-06", "Data"])
                    , ("hours-pair", [PayrollWorkbookEmployeePayBucketHours, PayrollWorkbookShiftTypeHours], ["Hours Mon 2025-01-06", "Shift Type Hours Mon 2025-01-06", "Data"])
                    ]
            renderedVariants <- forM variants \(key, families, expectedSheets) -> do
                workbook <- expectRight (payrollWorkbookFromDefinition (PayrollWorkbookDefinition key 1 families) 1 factModel)
                map (.name) workbook.sheets `shouldBe` expectedSheets
                map (.hidden) workbook.sheets `shouldBe` replicate (length expectedSheets - 1) False <> [True]
                let rendered = renderPayrollWorkbook workbook
                rendered `shouldBe` renderPayrollWorkbook workbook
                Xlsx.toXlsxEither rendered `shouldSatisfy` isRight
                pure (key, show (hashlazy rendered :: Digest SHA256))
            renderedVariants `shouldBe`
                [ ("summary", "687a14792cfb7e288c72cc51c6255988b11ce378fa887f4b8ffdd93ae10d090b")
                , ("employee-hours", "9c43cdade8174da86d199712337f2f3fc52b767b3aa943af64ea01a0434250b5")
                , ("shift-hours", "4335e83f30e873c13d2bd34e88afec938d8ecdc23c8e1c26c4ed96616ff15cec")
                , ("employee-wages", "82915619cc77ef41a3b2e900793586d017e2c4c4f2e233dfa087066007d73dac")
                , ("shift-wages", "415ce75be3337448123055b81dff322923405235ff8025415ec5e35807b54b87")
                , ("wages-summary", "cb9dd95dff26e171b54d8bedd6cd6f779bfd0af4ba83375ea5003390af286d53")
                , ("hours-pair", "06501d0304c125e8fb1cc34a4da8e8d2c027f0a3032d0dea1213a5c9364d7c0b")
                ]

        it "recalculates default and representative configured variants directly from authoritative Data facts" do
            let (_, factModel) = oneHourFactModel
            defaultWorkbook <- expectRight (payrollWorkbookFromDefinition defaultPayrollWorkbookDefinition 1 factModel)
            configuredWorkbook <- expectRight
                (payrollWorkbookFromDefinition
                    (PayrollWorkbookDefinition "wages-summary" 1 [PayrollWorkbookShiftTypeWages, PayrollWorkbookSummary])
                    1
                    factModel
                )
            let defaultBytes = renderPayrollWorkbook defaultWorkbook
            let configuredBytes = renderPayrollWorkbook configuredWorkbook
            maybeArtifactDirectory <- lookupEnv "PAYROLL_WORKBOOK_COMPATIBILITY_DIRECTORY"
            forM_ maybeArtifactDirectory \artifactDirectory -> do
                createDirectoryIfMissing True artifactDirectory
                LBS.writeFile (artifactDirectory <> "/payroll_workbook-default.xlsx") defaultBytes
                LBS.writeFile (artifactDirectory <> "/payroll_workbook-wages-summary.xlsx") configuredBytes
            assertLibreOfficeFormulaValues defaultBytes
                [ "Summary 2025-01-06\tC2\t1.5"
                , "Hours Mon 2025-01-06\tC2\t1.5"
                , "Hours Mon 2025-01-06\tB3\t1.5"
                , "Hours Mon 2025-01-06\tC3\t1.5"
                , "Shift Type Hours Mon 2025-01-06\tC2\t1"
                , "Shift Type Hours Mon 2025-01-06\tB3\t1"
                , "Shift Type Hours Mon 2025-01-06\tC3\t1"
                , "Wages Mon 2025-01-06\tC2\t45"
                , "Wages Mon 2025-01-06\tB3\t45"
                , "Wages Mon 2025-01-06\tC3\t45"
                , "Shift Type Wages Mon 2025-01-06\tC2\t45"
                , "Shift Type Wages Mon 2025-01-06\tB3\t45"
                , "Shift Type Wages Mon 2025-01-06\tC3\t45"
                ]
            assertLibreOfficeFormulaValues configuredBytes
                [ "Shift Type Wages Mon 2025-01-06\tC2\t45"
                , "Shift Type Wages Mon 2025-01-06\tB3\t45"
                , "Shift Type Wages Mon 2025-01-06\tC3\t45"
                , "Summary 2025-01-06\tC2\t1.5"
                ]

        it "renders shift-type Hours and Wages from shared facts with blank zero details and formula totals" do
            let (_, factModel) = oneHourFactModel
            workbook <- expectRight (payrollWorkbookFromDefinition defaultPayrollWorkbookDefinition 1 factModel)
            let shiftHours = workbook.sheets !! 2
            let shiftWages = workbook.sheets !! 4
            textValues shiftHours `shouldContain` ["Time", "Bar", "Total", "18:00-19:00", "Total"]
            numberAt 2 2 shiftHours `shouldBe` Just (1, "0.000000;-0.000000;;")
            formulaValues shiftHours `shouldContain` ["SUM(B2:B2)", "SUM(B2:B2)", "SUM(B3:B3)"]
            textValues shiftWages `shouldContain` ["Time", "Bar", "Total", "18:00-19:00", "Total"]
            numberAt 2 2 shiftWages `shouldBe` Just (45, "$#,##0.00;[Red]-$#,##0.00;;")
            formulaValues shiftWages `shouldContain` ["SUM(B2:B2)", "SUM(B2:B2)", "SUM(B3:B3)"]
            assertLibreOfficeFormulaValues
                (renderPayrollWorkbook workbook)
                [ "Shift Type Hours Mon 2025-01-06\tC2\t1"
                , "Shift Type Hours Mon 2025-01-06\tB3\t1"
                , "Shift Type Hours Mon 2025-01-06\tC3\t1"
                , "Shift Type Wages Mon 2025-01-06\tC2\t45"
                , "Shift Type Wages Mon 2025-01-06\tB3\t45"
                , "Shift Type Wages Mon 2025-01-06\tC3\t45"
                ]

        it "renders Staff Hours and Wages with hourly rows, collision-safe headings, blank zeros, and fixed hidden metadata columns" do
            let day = fromGregorian 2025 1 6
            let slots = map (`PayrollWorkbookHourSlot` FirstHourlyOccurrence) [18, 19]
            let firstStaff =
                    workbookRowWith
                        "10000000-0000-0000-0000-000000000001"
                        "20000000-0000-0000-0000-000000000001"
                        "Level 2"
                        [1, 0]
                        [3150, 0]
            let secondStaff =
                    workbookRowWith
                        "10000000-0000-0000-0000-000000000002"
                        "20000000-0000-0000-0000-000000000002"
                        "Level 2"
                        [0, 2]
                        [0, 6500]
            let model = PayrollWorkbookHourlyModel day day (HourlyReportWindow 18 20) slots [PayrollWorkbookDay day [firstStaff, secondStaff]]
            let workbook = payrollWorkbookFromHourlyModel 1 model
            let hoursSheet = workbook.sheets !! 1
            let wagesSheet = workbook.sheets !! 2

            forM_
                [ "Time"
                , "Ada, Lovelace, LVL 2"
                , "Ada, Lovelace, LVL 2 (2)"
                , "Staff column"
                , "Staff ID"
                , "Pay bucket key"
                ] \value -> textValues hoursSheet `shouldSatisfy` (value `elem`)
            hoursSheet.hiddenColumns `shouldBe` [5, 6, 7]
            hoursSheet.frozenRows `shouldBe` 1
            hoursSheet.frozenColumns `shouldBe` 1
            numberAt 2 2 hoursSheet `shouldBe` Just (1, "0.000000;-0.000000;;")
            numberAt 2 3 hoursSheet `shouldBe` Nothing
            numberAt 3 2 hoursSheet `shouldBe` Nothing
            numberAt 3 3 hoursSheet `shouldBe` Just (2, "0.000000;-0.000000;;")
            formulaAt 2 4 hoursSheet `shouldBe` Just ("SUM(B2:C2)", "0.000000;-0.000000;;")
            formulaAt 4 2 hoursSheet `shouldBe` Just ("SUM(B2:B3)", "0.000000;-0.000000;;")
            textAt 2 5 hoursSheet `shouldBe` Just "B"
            textAt 3 5 hoursSheet `shouldBe` Just "C"
            textAt 2 6 hoursSheet `shouldBe` Just "10000000-0000-0000-0000-000000000001"
            textAt 3 7 hoursSheet `shouldBe` Just "award_level:20000000-0000-0000-0000-000000000002"
            numberAt 2 2 wagesSheet `shouldBe` Just (31.5, "$#,##0.00;[Red]-$#,##0.00;;")
            numberAt 2 3 wagesSheet `shouldBe` Nothing
            numberAt 3 3 wagesSheet `shouldBe` Just (65, "$#,##0.00;[Red]-$#,##0.00;;")

        it "aggregates repeated civil-hour occurrences at legacy precision and leaves skipped detail blank" do
            let (day, oneHourModel) = oneHourFactModel
            let firstSlot = PayrollWorkbookHourSlot 18 FirstHourlyOccurrence
            let secondSlot = PayrollWorkbookHourSlot 18 SecondHourlyOccurrence
            let skippedSlot = PayrollWorkbookHourSlot 19 FirstHourlyOccurrence
            let firstFact = (workbookFact day firstSlot) { payrollFactWorkedHours = 1 % 3 }
            let secondFact =
                    (workbookFact day secondSlot)
                        { payrollFactWorkedHours = 1 % 3
                        , payrollFactWageCents = 123
                        }
            let skippedFact =
                    (workbookFact day skippedSlot)
                        { payrollFactWorkedHours = 0
                        , payrollFactPaidHours = 0
                        , payrollFactWageCents = 0
                        }
            let factModel =
                    oneHourModel
                        { payrollFactModelWindow = HourlyReportWindow 18 20
                        , payrollFactModelHourSlots = [firstSlot, secondSlot, skippedSlot]
                        , payrollFactModelShiftTypeColumns =
                            oneHourModel.payrollFactModelShiftTypeColumns
                                <> [HourlyShiftTypeColumn (uuid "40000000-0000-0000-0000-000000000002") "Kitchen"]
                        , payrollFactModelFacts = [firstFact, secondFact, skippedFact]
                        }
            workbook <- expectRight (payrollWorkbookFromDefinition defaultPayrollWorkbookDefinition 1 factModel)
            let summary = fromMaybe (error "expected Summary sheet") (head workbook.sheets)
            let shiftHours = workbook.sheets !! 2
            let shiftWages = workbook.sheets !! 4
            formulaValues summary `shouldSatisfy` any (Text.isInfixOf "'Data'!$K:$K,\"first\"")
            formulaValues summary `shouldSatisfy` any (Text.isInfixOf "'Data'!$K:$K,\"second\"")
            numberAt 2 2 shiftHours `shouldBe` Just (0.666667, "0.000000;-0.000000;;")
            numberAt 3 2 shiftHours `shouldBe` Nothing
            numberAt 2 3 shiftHours `shouldBe` Nothing
            numberAt 2 2 shiftWages `shouldBe` Just (46.23, "$#,##0.00;[Red]-$#,##0.00;;")
            numberAt 3 2 shiftWages `shouldBe` Nothing
            numberAt 2 3 shiftWages `shouldBe` Nothing
            formulaAt 3 4 shiftHours `shouldBe` Just ("SUM(B3:C3)", "0.000000")
            formulaAt 3 4 shiftWages `shouldBe` Just ("SUM(B3:C3)", "$#,##0.00;[Red]-$#,##0.00;$0.00;")
            forM_ ["Kitchen", "19:00-20:00"] \value ->
                textValues shiftHours `shouldSatisfy` (value `elem`)

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
            firstSummary.columnWidths `shouldBe` [(1, 24), (2, 18)] <> [(column, 13) | column <- [3 .. 21]]
            firstSummary.autoFilter `shouldBe` Nothing
            firstSummary.frozenRows `shouldBe` 0
            firstSummary.frozenColumns `shouldBe` 0
            formulaValues firstSummary `shouldContain`
                [ "'Hours Mon 2025-01-06'!B2"
                , "'Hours Mon 2025-01-06'!B3"
                , "'Hours Mon 2025-01-06'!B4"
                ]

            let firstHours = workbook.sheets !! 2
            firstHours.hiddenColumns `shouldBe` [4, 5, 6]
            firstHours.columnWidths `shouldBe` [(1, 22), (2, 28), (3, 14), (4, 14), (5, 38), (6, 42)]
            firstHours.frozenRows `shouldBe` 1
            firstHours.frozenColumns `shouldBe` 1
            firstHours.autoFilter `shouldBe` Nothing
            forM_ ["SUM(B2:B2)", "SUM(B3:B3)", "SUM(B4:B4)", "SUM(B2:B4)", "SUM(B5:B5)"] \formula ->
                formulaValues firstHours `shouldSatisfy` (formula `elem`)
            numberAt 2 2 firstHours `shouldBe` Nothing

            let firstWages = workbook.sheets !! 11
            firstWages.columnWidths `shouldBe` firstHours.columnWidths
            firstWages.autoFilter `shouldBe` Nothing
            firstWages.frozenRows `shouldBe` 1
            firstWages.frozenColumns `shouldBe` 1
            numberAt 3 2 firstWages `shouldBe` Just (12.34, "$#,##0.00;[Red]-$#,##0.00;;")

            let rendered = renderPayrollWorkbook workbook
            rendered `shouldBe` renderPayrollWorkbook workbook
            show (hashlazy rendered :: Digest SHA256)
                `shouldBe` "818c1dadc894ed2cbf8cdc6d51d82beee1952a7f7dc499ce25be0b2afc2e1f3f"
            Xlsx.toXlsxEither rendered `shouldSatisfy` isRight
            let archive = Zip.toArchive rendered
            summaryXml <- archiveText "xl/worksheets/sheet1.xml" archive
            hoursXml <- archiveText "xl/worksheets/sheet3.xml" archive
            wagesXml <- archiveText "xl/worksheets/sheet12.xml" archive
            stylesXml <- archiveText "xl/styles.xml" archive
            summaryXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FFFFC000\"/>"
            hoursXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FF4472C4\"/>"
            wagesXml `shouldSatisfy` Text.isInfixOf "<tabColor rgb=\"FF70AD47\"/>"
            summaryXml `shouldSatisfy` Text.isInfixOf "Hours Mon 2025-01-06"
            summaryXml `shouldNotSatisfy` Text.isInfixOf "<autoFilter"
            summaryXml `shouldNotSatisfy` Text.isInfixOf "state=\"frozen\""
            summaryXml `shouldSatisfy` Text.isInfixOf "width=\"24"
            hoursXml `shouldSatisfy` Text.isInfixOf "<f>SUM(B2:B2)</f>"
            hoursXml `shouldNotSatisfy` Text.isInfixOf "<autoFilter"
            hoursXml `shouldSatisfy` Text.isInfixOf "state=\"frozen\""
            hoursXml `shouldSatisfy` Text.isInfixOf "width=\"28"
            hoursXml `shouldNotSatisfy` Text.isInfixOf "<f>SUM(B2:B2)</f><v>"
            stylesXml `shouldNotSatisfy` Text.isInfixOf "FFFFF2CC"
            stylesXml `shouldNotSatisfy` Text.isInfixOf "FFD9EAF7"
            stylesXml `shouldNotSatisfy` Text.isInfixOf "FFE2F0D9"
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
            formulaValues emptyHoursDay `shouldBe` replicate 4 "SUM()"

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
                    , "Hours Sun 2025-01-12\tB6\t10"
                    , "Hours Sun 2025-01-12\tC6\t26"
                    , "Hours Sun 2025-01-12\tD6\t36"
                    , "Wages Sun 2025-01-12\tD2\t6"
                    , "Wages Sun 2025-01-12\tD3\t8"
                    , "Wages Sun 2025-01-12\tD4\t10"
                    , "Wages Sun 2025-01-12\tD5\t12"
                    , "Wages Sun 2025-01-12\tD6\t36"
                    , "Hours Mon 2025-01-13\tB6\t4"
                    , "Hours Mon 2025-01-13\tC6\t4"
                    , "Wages Mon 2025-01-13\tB6\t4"
                    , "Wages Mon 2025-01-13\tC6\t4"
                    ]

            let workbookBytes = renderPayrollWorkbook (payrollWorkbookFromHourlyModel 1 model)
            maybeArtifactPath <- lookupEnv "PAYROLL_WORKBOOK_COMPATIBILITY_ARTIFACT"
            forM_ maybeArtifactPath \artifactPath -> do
                createDirectoryIfMissing True (takeDirectory artifactPath)
                LBS.writeFile artifactPath workbookBytes
            assertLibreOfficeFormulaValues workbookBytes expectedFormulaValues

        it "names repeated DST hour rows explicitly on both daily Staff sheet families" do
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
                Text.isInfixOf "'Hours Sat 2026-04-04'!B2" formula
                    && Text.isInfixOf "'Hours Sat 2026-04-04'!B3" formula
                    && Text.isInfixOf "+" formula
                )

expectRight :: Either Text value -> IO value
expectRight = \case
    Left message -> expectationFailure (cs message) >> fail "expected Right"
    Right value  -> pure value

oneHourFactModel :: (Day, PayrollWorkbookFactModel)
oneHourFactModel =
    let day = fromGregorian 2025 1 6
        slot = PayrollWorkbookHourSlot 18 FirstHourlyOccurrence
     in ( day
        , PayrollWorkbookFactModel
            { payrollFactModelRangeStart = day
            , payrollFactModelRangeEnd = day
            , payrollFactModelWindow = HourlyReportWindow 18 19
            , payrollFactModelHourSlots = [slot]
            , payrollFactModelShiftTypeColumns =
                [HourlyShiftTypeColumn (uuid "40000000-0000-0000-0000-000000000001") "Bar"]
            , payrollFactModelFacts = [workbookFact day slot]
            }
        )

workbookFact :: Day -> PayrollWorkbookHourSlot -> PayrollWorkbookFact
workbookFact day slot =
    PayrollWorkbookFact
        { payrollFactOperationalDate = day
        , payrollFactEntryId = uuid "30000000-0000-0000-0000-000000000001"
        , payrollFactStaffId = uuid "10000000-0000-0000-0000-000000000001"
        , payrollFactStaffFirstName = "Ada"
        , payrollFactStaffLastName = "Lovelace"
        , payrollFactShiftTypeId = uuid "40000000-0000-0000-0000-000000000001"
        , payrollFactShiftTypeLabel = "Bar"
        , payrollFactPayBucket = PayrollWorkbookPayBucket
            (PayrollWorkbookAwardLevel (uuid "20000000-0000-0000-0000-000000000001"))
            "LVL 3"
        , payrollFactHourSlot = slot
        , payrollFactWorkedHours = 1
        , payrollFactPaidHours = 1.5
        , payrollFactWageCents = 4500
        , payrollFactActiveCalculationId = Just (uuid "50000000-0000-0000-0000-000000000001")
        , payrollFactStaffPayVersionId = Just (uuid "60000000-0000-0000-0000-000000000001")
        , payrollFactShiftTypePayVersionId = Just (uuid "70000000-0000-0000-0000-000000000001")
        , payrollFactCalculationVersion = "hospitality-award-v1"
        , payrollFactRateBookVersion = Just "fwc-mapd-2025-07"
        }

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

textAt :: Int -> Int -> PayrollWorkbookSheet -> Maybe Text
textAt row column sheet =
    listToMaybe
        [ value
        | PayrollWorkbookCell { row = cellRow, column = cellColumn, value = PayrollWorkbookText value } <- sheet.cells
        , cellRow == row
        , cellColumn == column
        ]

formulaValues :: PayrollWorkbookSheet -> [Text]
formulaValues sheet = [value | PayrollWorkbookCell { value = PayrollWorkbookFormula value } <- sheet.cells]

formulaAt :: Int -> Int -> PayrollWorkbookSheet -> Maybe (Text, Text)
formulaAt row column sheet =
    listToMaybe
        [ (value, fromMaybe "" style.numberFormat)
        | PayrollWorkbookCell { row = cellRow, column = cellColumn, value = PayrollWorkbookFormula value, style } <- sheet.cells
        , cellRow == row
        , cellColumn == column
        ]

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
