-- | Single-page entry adapter over the shared authoritative saved model.
module Web.Daysheets.ReadModel
    ( EntryModel (..), prepareEntryModel, resolveCell, resultFor, tableRows
    , referenceLabel, valueText, numberText, percentageText
    ) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.EntryLayout
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Saved as Saved
import Application.Daysheet.Saved (numberText, percentageText)
import qualified Data.Map.Strict as Map
import IHP.Prelude
import IHP.ModelSupport (unpackId)
import Generated.Types

-- Authorization remains with DailyStorage. The shared model promises only an
-- evaluation of the particular saved state supplied by its caller.
data EntryModel = EntryModel
    { state :: Storage.DailyState
    , layout :: EntryLayout
    , saved :: Saved.Saved
    , snapshot :: E.Snapshot
    , evaluation :: E.Evaluation
    , rows :: Map.Map D.ListId [E.RowId]
    , bindings :: [EntryCell]
    }

prepareEntryModel :: Storage.DailyState -> Either Daily.DailyError EntryModel
prepareEntryModel state = do
    let owner = E.SnapshotKey (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)
    layout <- prepareEntryLayout state.definition
    saved <- Saved.prepareSaved state.definition state.references owner state.content
    let snapshot = Saved.snapshot saved
    let evaluation = Saved.evaluation saved
    let rows = Saved.rows saved
    bindings <- sequence [resolveEntryCell layout snapshot state.content (occurrenceIndex placement) row
        | placement <- Map.elems (entryOccurrences layout), row <- case occurrenceList placement of
            Nothing -> [Nothing]
            Just source -> map Just (Map.findWithDefault [] (D.listId source) rows)]
    pure EntryModel { .. }

resolveCell :: EntryModel -> Int -> Maybe UUID -> Either Daily.DailyError EntryCell
resolveCell model occurrence row = resolveEntryCell model.layout model.snapshot model.state.content occurrence (E.RowId <$> row)

resultFor :: EntryModel -> E.Target -> D.Result E.Value
resultFor model = Saved.resultFor model.saved

tableRows :: EntryModel -> D.RecordList -> Maybe D.FieldId -> [(D.FieldId, D.SortDirection)] -> [E.RowId]
tableRows model = Saved.tableRows model.saved

referenceLabel :: EntryModel -> D.ListId -> E.RowId -> Text
referenceLabel model = Saved.referenceLabel model.saved

valueText :: EntryModel -> D.Field -> E.Value -> Text
valueText model = Saved.valueText model.saved
