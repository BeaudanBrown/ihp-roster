-- | One authoritative saved-state evaluation shared by entry and reports.
-- This internal model is not a report/output document: it includes source data.
module Application.Daysheet.Saved
    ( Saved, prepareSaved, definition, snapshot, evaluation, rows
    , resultFor, tableRows, referenceLabel, valueText, numberText, percentageText
    ) where

import Prelude
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.EntryLayout (entryRowIds)
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Number as Number
import Application.Daysheet.References (ReferenceData)
import qualified Data.Map.Strict as Map
import Data.List (find, sortBy)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Foldable (foldMap)

data Saved = Saved
    { definition :: D.Definition
    , snapshot :: E.Snapshot
    , evaluation :: E.Evaluation
    , rows :: Map.Map D.ListId [E.RowId]
    , values :: Map.Map E.Target (D.Result E.Value)
    }

prepareSaved :: D.Definition -> ReferenceData -> E.SnapshotKey -> Daily.DailyDocument -> Either Daily.DailyError Saved
prepareSaved definition references owner document = do
    snapshot <- Daily.dailySnapshot definition references owner document
    evaluation <- either (Left . Daily.InvalidDailyInput) Right (E.prepareEvaluation definition snapshot)
    let rows = Map.fromList [(D.listId source, entryRowIds source references document) | source <- D.recordLists definition]
    let targets = map (E.RootTarget . D.fieldId) (D.rootFields definition)
            <> [E.RowTarget (D.listId source) row (D.fieldId field) | source <- D.recordLists definition,
                row <- Map.findWithDefault [] (D.listId source) rows, field <- D.listFields source]
    results <- either (Left . Daily.InvalidDailyInput) Right (E.evaluate evaluation targets)
    pure Saved { values = Map.fromList (zip targets results), .. }

resultFor :: Saved -> E.Target -> D.Result E.Value
resultFor model target = Map.findWithDefault (D.Unavailable D.EvaluationLimit) target model.values

-- Stable ties retain captured/insertion order. Missing results stay last in
-- either direction. Operational times use the evaluator's 06:00 day boundary.
tableRows :: Saved -> D.RecordList -> Maybe D.FieldId -> [(D.FieldId, D.SortDirection)] -> [E.RowId]
tableRows model source grouping ordering = sortBy compareRows (Map.findWithDefault [] (D.listId source) model.rows)
  where
    keys = case grouping of
        Nothing -> ordering
        Just key -> (key, fromMaybe D.Ascending (lookup key ordering)) : filter ((/= key) . fst) ordering
    compareRows left right = foldMap (\(key, direction) -> compareValue direction
        (resultFor model (E.RowTarget (D.listId source) left key))
        (resultFor model (E.RowTarget (D.listId source) right key))) keys
    compareValue direction left right = case (left, right) of
        (D.Unavailable _, D.Unavailable _) -> EQ
        (D.Unavailable _, _) -> GT
        (_, D.Unavailable _) -> LT
        (D.Known a, D.Known b) -> if direction == D.Descending then compareKnown b a else compareKnown a b
    compareKnown (E.Scalar a) (E.Scalar b) = case (a, b) of
        (D.WholeLiteral x, D.WholeLiteral y) -> compare x y
        (D.DecimalLiteral x, D.DecimalLiteral y) -> compare x y
        (D.MoneyLiteral x, D.MoneyLiteral y) -> compare x y
        (D.PercentageLiteral x, D.PercentageLiteral y) -> compare x y
        (D.DateLiteral x, D.DateLiteral y) -> compare x y
        (D.OperationalTimeLiteral x, D.OperationalTimeLiteral y) -> compare (E.operationalSeconds x) (E.operationalSeconds y)
        (D.BooleanLiteral x, D.BooleanLiteral y) -> compare x y
        (D.TextLiteral x, D.TextLiteral y) -> compare x y
        _ -> compare (show a) (show b)
    compareKnown a b = compare (show a) (show b)

referenceLabel :: Saved -> D.ListId -> E.RowId -> Text
referenceLabel model source row = fromMaybe "Record" do
    list <- find ((== source) . D.listId) (D.recordLists model.definition)
    let labels = [text | field <- D.listFields list, D.fieldType field == D.TextType,
            D.Known (E.Scalar (D.TextLiteral text)) <- [resultFor model (E.RowTarget source row (D.fieldId field))], not (Text.null text)]
    pure (fromMaybe (D.listLabel list <> " record " <> tshow (fromMaybe 0 (lookup row (zip (Map.findWithDefault [] source model.rows) [1 :: Int ..])))) (listToMaybe labels))

valueText :: Saved -> D.Field -> E.Value -> Text
valueText model field = \case
    E.Reference (E.RecordReference _ source row) -> referenceLabel model source row
    E.Scalar literal -> case literal of
        D.TextLiteral value -> value
        D.BooleanLiteral value -> if value then "Yes" else "No"
        D.ChoiceLiteral key -> case D.fieldType field of
            D.ChoiceType choices -> maybe "Unavailable choice" D.choiceLabel (find ((== key) . D.choiceId) choices)
            _ -> "Unavailable choice"
        D.WholeLiteral value -> tshow value
        D.DecimalLiteral value -> numberText value
        D.MoneyLiteral value -> numberText value <> " AUD"
        D.PercentageLiteral value -> percentageText value <> "%"
        D.DateLiteral value -> tshow value
        D.OperationalTimeLiteral value -> tshow value

numberText :: Number.Number -> Text
numberText value = let (n, d) = Number.fraction value in fractionText n d
percentageText :: Number.Number -> Text
percentageText value = let (n, d) = Number.fraction value in fractionText (100 * n) d

-- Exact display: never silently round an intermediate financial calculation.
-- A non-terminating rational is shown as a fraction rather than a guessed float.
fractionText :: Integer -> Integer -> Text
fractionText numerator denominator
    | stripFactor 5 (stripFactor 2 denominator) /= 1 = tshow numerator <> "/" <> tshow denominator
    | otherwise = (if numerator < 0 then "-" else "") <> tshow whole
        <> if remainder == 0 then "" else "." <> digits remainder
  where
    (whole, remainder) = abs numerator `quotRem` denominator
    stripFactor factor value | value `mod` factor == 0 = stripFactor factor (value `div` factor)
                             | otherwise = value
    digits 0 = ""
    digits rest = let (digit, next) = (rest * 10) `quotRem` denominator in tshow digit <> digits next

tshow :: Show a => a -> Text
tshow = Text.pack . show
