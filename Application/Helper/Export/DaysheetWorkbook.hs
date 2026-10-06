-- | Values-only XLSX adaptation of the selected report boundary. Reuses the
-- shared typed worksheet renderer, never the payroll model or formula builder.
module Application.Helper.Export.DaysheetWorkbook
    ( DaysheetWorkbook, WorkbookIdentity (..), buildDaysheetWorkbook
    , renderDaysheetWorkbook, daysheetWorkbookFileName
    ) where

import Prelude
import Control.Monad (foldM)
import Application.Daysheet.Report
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Saved as Saved
import Application.Helper.Export.PayrollWorkbook
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Char as Char
import qualified Data.Set as Set
import Data.Time (Day, UTCTime, defaultTimeLocale, formatTime)
import Text.Read (readMaybe)

-- Frozen identity is supplied only by a persisted capture owner, never a form.
data WorkbookIdentity = DraftWorkbook Day | LiveWorkbook Day | FrozenWorkbook Day UTCTime deriving (Eq, Show)
newtype DaysheetWorkbook = DaysheetWorkbook PayrollWorkbook

buildDaysheetWorkbook :: WorkbookIdentity -> ReportContent -> Either Text DaysheetWorkbook
buildDaysheetWorkbook identity (ReportContent title sections)
    | null sections = Left "Select at least one report section before downloading Excel."
    | otherwise = do
        let sheets = zipWith makeSheet (sheetNames sections) sections
        let cells = take 1000001 (concatMap (.cells) sheets)
        if length cells > 1000000 then Left "The report exceeds the supported workbook size." else Right ()
        _ <- foldM validateCell (0 :: Int) cells
        pure (DaysheetWorkbook (PayrollWorkbook sheets))
  where
    makeSheet name (ReportSection label blocks) = PayrollWorkbookSheet
        { name, hidden = False, hiddenColumns = [], tabColor = Nothing, autoFilter = Nothing
        , frozenRows = 3, frozenColumns = 0, columnWidths = [(1, 36), (2, 28)]
        , cells = concat (zipWith renderRow [1 ..] ([(True, [plain title]), (False, [plain (identityText identity)]), (True, [plain label])] <> concatMap blockRows blocks))
        }
    renderRow row (bold, values) = zipWith (renderCell row bold) [1 ..] values
    renderCell row bold column (value, format) = PayrollWorkbookCell row column value
        (defaultPayrollWorkbookCellStyle { bold, numberFormat = format })
    validateCell total cell
        | cell.row > 1048576 || cell.column > 16384 = Left "The report exceeds Excel worksheet dimensions."
        | otherwise = case cell.value of
            PayrollWorkbookText text
                | not (validCellText text) -> Left "Selected report text exceeds Excel limits or contains an unsupported control character."
                | total + Text.length text > 16777216 -> Left "The report exceeds the supported workbook text size."
                | otherwise -> Right (total + Text.length text)
            PayrollWorkbookFormula _ -> Left "Daysheet workbooks cannot contain formulas."
            _ -> Right total

renderDaysheetWorkbook :: DaysheetWorkbook -> LBS.ByteString
renderDaysheetWorkbook (DaysheetWorkbook workbook) = renderPayrollWorkbook workbook

type OutputCell = (PayrollWorkbookCellValue, Maybe Text)
type OutputRow = (Bool, [OutputCell])

plain :: Text -> OutputCell
plain text = (PayrollWorkbookText text, Nothing)

blockRows :: ReportBlock -> [OutputRow]
blockRows = \case
    ReportInstructions text -> [(False, [plain text])]
    ReportField label value -> [(False, [plain label, reportCell value])]
    ReportAdvisory check -> [(False, [plain (checkText check)])]
    ReportRowAdvisories label rows -> (True, [plain label]) : [(False, [plain name, plain (checkText check)]) | (name, check) <- rows]
    ReportTable label columns grouping groups ->
        [(True, [plain label]), (True, map plain columns)]
            <> if null groups then [(False, [plain "No rows."])] else concatMap (groupRows grouping) groups
  where
    groupRows grouping (ReportGroup value rows) =
        (case (grouping, value) of
            (Just label, Just value) -> [(True, [plain label, reportCell value])]
            _ -> []) <> if null rows then [(False, [plain "No rows."])] else [(False, map reportCell values) | values <- rows]

reportCell :: ReportCell -> OutputCell
reportCell (ReportUnavailable reason) = plain ("Unavailable: " <> reason)
reportCell (ReportValue literal text) = case literal of
    D.WholeLiteral value -> numeric (Text.pack (show value)) "0"
    D.DecimalLiteral value -> let raw = Saved.numberText value in numeric raw (decimalFormat 0 raw)
    D.MoneyLiteral value -> let raw = Saved.numberText value in numeric raw (decimalFormat 2 raw <> "\" AUD\"")
    D.PercentageLiteral value -> numeric (Saved.numberText value) (decimalFormat 0 (Saved.percentageText value) <> "%")
    _ -> plain text
  where
    -- Excel numbers have at most 15 significant decimal digits. Nonterminating
    -- rationals and values beyond that fidelity remain exact displayed text.
    -- No Double conversion is ever fed back into authoritative calculations.
    numeric raw format
        | Text.any (== '/') raw || Text.length (Text.filter Char.isDigit raw) > 15 = plain text
        | otherwise = case readMaybe (Text.unpack raw) of
            Just value | not (isInfinite value || isNaN value) -> (PayrollWorkbookNumber value, Just format)
            _ -> plain text

decimalFormat :: Int -> Text -> Text
decimalFormat minimum raw = "0" <> if places == 0 then "" else "." <> Text.replicate places "0"
  where places = max minimum (max 0 (Text.length (snd (Text.breakOn "." raw)) - 1))

checkText :: ReportCheck -> Text
checkText = \case
    ReportPassed text -> "Passed: " <> text
    ReportConcern text -> "Concern: " <> text
    ReportNotEvaluated reason -> "Not evaluated: " <> reason

identityText :: WorkbookIdentity -> Text
identityText identity = case identity of
    DraftWorkbook day -> "Draft — Operational date " <> Text.pack (show day) <> ". Saved data, not a sent report."
    LiveWorkbook day -> "Live — Operational date " <> Text.pack (show day) <> ". Saved data, not a sent report."
    FrozenWorkbook day captured -> "Frozen report — Operational date " <> Text.pack (show day)
        <> "; captured " <> Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" captured)

validCellText :: Text -> Bool
validCellText text = Text.all xmlCharacter text
    && Text.foldl' (\size char -> size + if Char.ord char > 65535 then 2 else 1) (0 :: Int) text <= 32767

xmlCharacter :: Char -> Bool
xmlCharacter char = let code = Char.ord char in code `elem` [9, 10, 13]
    || code >= 32 && code <= 55295 || code >= 57344 && code <= 65533 || code >= 65536 && code <= 1114111

sheetNames :: [ReportSection] -> [Text]
sheetNames = go Set.empty
  where
    go _ [] = []
    go used (ReportSection label _ : rest) =
        let base = Text.dropAround (== '\'') (Text.strip (Text.map safe label))
            usable = if Text.null base || Text.toCaseFold base == "history" then "Section" else base
            choose number =
                let suffix = if number == 1 then "" else " (" <> Text.pack (show number) <> ")"
                    candidate = Text.dropAround (== '\'') (takeSheetName (31 - Text.length suffix) usable) <> suffix
                in if Set.member (Text.toCaseFold candidate) used then choose (number + 1) else candidate
            name = choose (1 :: Int)
        in name : go (Set.insert (Text.toCaseFold name) used) rest
    safe char | char `elem` ("[]:*?/\\" :: String) || Char.isControl char || not (xmlCharacter char) = '-'
              | otherwise = char

-- Conservative UTF-16 bound also covers Excel versions counting surrogate pairs.
takeSheetName :: Int -> Text -> Text
takeSheetName capacity = Text.pack . takeUnits capacity . Text.unpack
  where
    takeUnits _ [] = []
    takeUnits remaining (char : rest)
        | remaining < width = []
        | otherwise = char : takeUnits (remaining - width) rest
      where width = if Char.ord char > 65535 then 2 else 1

daysheetWorkbookFileName :: WorkbookIdentity -> Text -> Text
daysheetWorkbookFileName identity label = "daysheet-" <> name <> "-" <> Text.pack (show day) <> "-" <> kind <> ".xlsx"
  where
    normalized = Text.intercalate "-" (Text.words (Text.map (\char -> if Char.isAlphaNum char then Char.toLower char else ' ') label))
    name = if Text.null normalized then "report" else Text.take 80 normalized
    (day, kind) = case identity of
        DraftWorkbook day -> (day, "draft")
        LiveWorkbook day -> (day, "live")
        FrozenWorkbook day _ -> (day, "frozen")
