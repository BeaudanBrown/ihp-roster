module Test.DaysheetWorkbookSpec where

import Prelude
import Application.Daysheet.Report
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Number as Number
import Application.Helper.Export.DaysheetWorkbook
import qualified Codec.Xlsx as X
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time (fromGregorian, UTCTime (..))
import Data.Either (isLeft)
import Test.Hspec

parseWorkbook :: WorkbookIdentity -> ReportContent -> IO X.Xlsx
parseWorkbook identity report = do
    Right workbook <- pure (buildDaysheetWorkbook identity report)
    let bytes = renderDaysheetWorkbook workbook
    bytes `shouldBe` renderDaysheetWorkbook workbook
    Right parsed <- pure (X.toXlsxEither bytes)
    pure parsed

cellValue :: X.Worksheet -> Int -> Int -> Maybe X.CellValue
cellValue sheet row column = X._cellValue =<< Map.lookup (X.RowIndex row, X.ColumnIndex column) (X._wsCells sheet)

tests :: Spec
tests = describe "Daysheet Excel workbook" do
    it "emits only selected sections in order with visible sheets, identity and literal text" do
        let report = ReportContent "Closing report"
                [ReportSection "Summary" [ReportField "Comment" (ReportValue (D.TextLiteral "=HYPERLINK(unsafe)") "=HYPERLINK(unsafe)")]
                , ReportSection "Notes" [ReportInstructions "<script>& plain text"]]
        parsed <- parseWorkbook (DraftWorkbook (fromGregorian 2026 10 1)) report
        map fst (X._xlSheets parsed) `shouldBe` ["Summary", "Notes"]
        let [( _, summary), (_, notes)] = X._xlSheets parsed
        cellValue summary 2 1 `shouldBe` Just (X.CellText "Draft — Operational date 2026-10-01. Saved data, not a sent report.")
        cellValue summary 4 2 `shouldBe` Just (X.CellText "=HYPERLINK(unsafe)")
        cellValue notes 4 1 `shouldBe` Just (X.CellText "<script>& plain text")
        map (X._wsState . snd) (X._xlSheets parsed) `shouldBe` [X.Visible, X.Visible]
        [X._cellFormula cell | (_, sheet) <- X._xlSheets parsed, cell <- Map.elems (X._wsCells sheet)] `shouldSatisfy` all (== Nothing)
        [X.cpHidden column | (_, sheet) <- X._xlSheets parsed, column <- X._wsColumnsProperties sheet] `shouldSatisfy` all not
    it "keeps zero numeric, explicit cents exact and higher precision/rationals as honest values" do
        Right cents <- pure (Number.number 1005 1000)
        Right third <- pure (Number.number 1 3)
        let report = ReportContent "Figures" [ReportSection "Figures"
                [ReportField "Zero" (ReportValue (D.WholeLiteral 0) "0")
                , ReportField "Unrounded" (ReportValue (D.MoneyLiteral cents) "1.005 AUD")
                , ReportField "Exact fraction" (ReportValue (D.MoneyLiteral third) "1/3 AUD")
                , ReportField "Large" (ReportValue (D.WholeLiteral 1234567890123456) "1234567890123456")
                , ReportField "Missing" (ReportUnavailable "Required input has not been entered.")
                , ReportAdvisory (ReportConcern "Review variance")
                , ReportAdvisory (ReportNotEvaluated "Missing count")]]
        parsed <- parseWorkbook (LiveWorkbook (fromGregorian 2026 10 1)) report
        let [(_, sheet)] = X._xlSheets parsed
        cellValue sheet 4 2 `shouldBe` Just (X.CellDouble 0)
        cellValue sheet 5 2 `shouldBe` Just (X.CellDouble 1.005)
        cellValue sheet 6 2 `shouldBe` Just (X.CellText "1/3 AUD")
        cellValue sheet 7 2 `shouldBe` Just (X.CellText "1234567890123456")
        cellValue sheet 8 2 `shouldBe` Just (X.CellText "Unavailable: Required input has not been entered.")
        cellValue sheet 9 1 `shouldBe` Just (X.CellText "Concern: Review variance")
        cellValue sheet 10 1 `shouldBe` Just (X.CellText "Not evaluated: Missing count")
    it "sanitizes and disambiguates worksheet names without dropping selected sections" do
        let labels = ["'Bad/name:*?[]\\'", "SAME", "same", Text.replicate 50 "x", Text.replicate 50 "x", "History"]
        parsed <- parseWorkbook (DraftWorkbook (fromGregorian 2026 10 1)) (ReportContent "Names" [ReportSection label [] | label <- labels])
        map fst (X._xlSheets parsed) `shouldBe` ["Bad-name------", "SAME", "same (2)", Text.replicate 31 "x", Text.replicate 27 "x" <> " (2)", "Section"]
    it "bounds Unicode worksheet names and total selected text before ZIP generation" do
        let day = fromGregorian 2026 10 1
        parsed <- parseWorkbook (DraftWorkbook day) (ReportContent "Unicode" [ReportSection (Text.replicate 31 "😀") []])
        map fst (X._xlSheets parsed) `shouldBe` [Text.replicate 15 "😀"]
        let oversized = ReportContent "Large" [ReportSection "Selected" (replicate 1700 (ReportInstructions (Text.replicate 10000 "x")))]
        isLeft (buildDaysheetWorkbook (DraftWorkbook day) oversized) `shouldBe` True
    it "identifies frozen captures and makes filenames safe" do
        let day = fromGregorian 2026 10 1
            identity = FrozenWorkbook day (UTCTime day 21600)
        parsed <- parseWorkbook identity (ReportContent "Frozen" [ReportSection "Selected" []])
        let [(_, sheet)] = X._xlSheets parsed
        cellValue sheet 2 1 `shouldBe` Just (X.CellText "Frozen report — Operational date 2026-10-01; captured 2026-10-01T06:00:00Z")
        daysheetWorkbookFileName identity "../../Closing\r\n\" pack" `shouldBe` "daysheet-closing-pack-2026-10-01-frozen.xlsx"
    it "rejects empty selections and non-XML text without persisting invented worksheets" do
        isLeft (buildDaysheetWorkbook (DraftWorkbook (fromGregorian 2026 10 1)) (ReportContent "Empty" [])) `shouldBe` True
        isLeft (buildDaysheetWorkbook (DraftWorkbook (fromGregorian 2026 10 1)) (ReportContent "Control" [ReportSection "Selected" [ReportInstructions "bad\x01"]])) `shouldBe` True
