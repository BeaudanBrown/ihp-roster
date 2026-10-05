-- | Single-page, server-owned daily entry. All figures use the complete saved
-- snapshot; neither browser state nor a displayed subset is calculation input.
module Web.Daysheets.ReadModel
    ( EntryModel (..), prepareEntryModel, resolveCell, resultFor, tableRows
    , referenceLabel, valueText, numberText, percentageText
    ) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.EntryLayout
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Number as Number
import qualified Data.Map.Strict as Map
import Data.List (find, sortBy)
import qualified Data.Text as Text
import IHP.Prelude
import IHP.ModelSupport (unpackId)
import Generated.Types
import Data.Foldable (foldMap)

-- Authorization remains with DailyStorage. This value promises only a
-- projection of the particular saved state supplied by its caller.
data EntryModel = EntryModel
    { state :: Storage.DailyState
    , layout :: EntryLayout
    , snapshot :: E.Snapshot
    , evaluation :: E.Evaluation
    , rows :: Map.Map D.ListId [E.RowId]
    , values :: Map.Map E.Target (D.Result E.Value)
    , bindings :: [EntryCell]
    }

prepareEntryModel :: Storage.DailyState -> Either Daily.DailyError EntryModel
prepareEntryModel state = do
    let owner = E.SnapshotKey (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)
    layout <- prepareEntryLayout state.definition
    snapshot <- Daily.dailySnapshot state.definition state.references owner state.content
    evaluation <- either (Left . Daily.InvalidDailyInput) Right (E.prepareEvaluation state.definition snapshot)
    let rows = Map.fromList [(D.listId source, entryRowIds source state.references state.content) | source <- D.recordLists state.definition]
    let targets = map (E.RootTarget . D.fieldId) (D.rootFields state.definition)
            <> [E.RowTarget (D.listId source) row (D.fieldId field) | source <- D.recordLists state.definition,
                row <- Map.findWithDefault [] (D.listId source) rows, field <- D.listFields source]
    results <- either (Left . Daily.InvalidDailyInput) Right (E.evaluate evaluation targets)
    let values = Map.fromList (zip targets results)
    bindings <- sequence [resolveEntryCell layout snapshot state.content (occurrenceIndex placement) row
        | placement <- Map.elems (entryOccurrences layout), row <- case occurrenceList placement of
            Nothing -> [Nothing]
            Just source -> map Just (Map.findWithDefault [] (D.listId source) rows)]
    pure EntryModel { .. }

resolveCell :: EntryModel -> Int -> Maybe UUID -> Either Daily.DailyError EntryCell
resolveCell model occurrence row = resolveEntryCell model.layout model.snapshot model.state.content occurrence (E.RowId <$> row)

resultFor :: EntryModel -> E.Target -> D.Result E.Value
resultFor model target = Map.findWithDefault (D.Unavailable D.EvaluationLimit) target model.values

-- Stable ties retain captured/insertion order. Unavailable values remain last
-- in either direction, never becoming numeric zero or an empty grouping key.
tableRows :: EntryModel -> D.RecordList -> Maybe D.FieldId -> [(D.FieldId, D.SortDirection)] -> [E.RowId]
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
        (D.OperationalTimeLiteral x, D.OperationalTimeLiteral y) -> compare x y
        (D.BooleanLiteral x, D.BooleanLiteral y) -> compare x y
        (D.TextLiteral x, D.TextLiteral y) -> compare x y
        _ -> compare (tshow a) (tshow b)
    compareKnown a b = compare (tshow a) (tshow b)

referenceLabel :: EntryModel -> D.ListId -> E.RowId -> Text
referenceLabel model source row = fromMaybe "Record" do
    list <- find ((== source) . D.listId) (D.recordLists model.state.definition)
    let labels = [text | field <- D.listFields list, D.fieldType field == D.TextType,
            D.Known (E.Scalar (D.TextLiteral text)) <- [resultFor model (E.RowTarget source row (D.fieldId field))], not (Text.null text)]
    pure (fromMaybe (D.listLabel list <> " record " <> tshow (fromMaybe 0 (lookup row (zip (Map.findWithDefault [] source model.rows) [1 :: Int ..])))) (headMay labels))

valueText :: EntryModel -> D.Field -> E.Value -> Text
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
