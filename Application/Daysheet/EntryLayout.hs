-- | Server-only entry-layout identities. An occurrence identifies one place in
-- the immutable authored layout, not a new field or browser-owned document.
-- Repeated fields/tables remain distinct DOM locations over the same saved cell.
module Application.Daysheet.EntryLayout
    ( EntrySection (..), EntryBlock (..), EntryOccurrence (..), EntryLayout (..)
    , EntryCell (..), prepareEntryLayout, resolveEntryCell, entryRowIds
    ) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, put)
import Control.Monad.Trans.Class (lift)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.List (find)
import Data.Text (Text)

-- No arbitrary render document crosses the browser boundary.
data EntrySection = EntrySection SectionId Text [EntryBlock] deriving (Eq, Show)
data EntryBlock
    = EntryInstructions Text
    | EntryField EntryOccurrence
    | EntryAdvisory Advisory
    | EntryRowAdvisory RecordList Advisory
    | EntryTable RecordList [EntryOccurrence] (Maybe FieldId) [(FieldId, SortDirection)]
    deriving (Eq, Show)
data EntryOccurrence = EntryOccurrence
    { occurrenceIndex :: Int
    , occurrenceList :: Maybe RecordList
    , occurrenceField :: Field
    } deriving (Eq, Show)
data EntryLayout = EntryLayout
    { entrySections :: [EntrySection]
    , entryOccurrences :: Map.Map Int EntryOccurrence
    } deriving (Eq, Show)
data EntryCell = EntryCell
    { entryOccurrence :: EntryOccurrence
    , entryRow :: Maybe E.RowId
    , entryTarget :: E.Target
    , entryAddress :: Daily.CellAddress
    , entrySavedCell :: Maybe Daily.Cell
    } deriving (Eq, Show)

prepareEntryLayout :: Definition -> Either Daily.DailyError EntryLayout
prepareEntryLayout definition = do
    sections <- evalStateT (mapM section (entryLayout definition)) 0
    let occurrences = concatMap sectionOccurrences sections
    pure (EntryLayout sections (Map.fromList [(occurrenceIndex value, value) | value <- occurrences]))
  where
    section (Section key label blocks) = EntrySection key label <$> mapM block blocks
    requireField fields key = maybe (Left Daily.UnknownDailyField) Right (find ((== key) . fieldId) fields)
    requireList key = maybe (Left Daily.UnknownDailyList) Right (find ((== key) . listId) (recordLists definition))
    allocate :: Maybe RecordList -> Field -> StateT Int (Either Daily.DailyError) EntryOccurrence
    allocate source field = do
        index <- get
        put (index + 1)
        pure (EntryOccurrence index source field)
    block = \case
        Instructions text -> pure (EntryInstructions text)
        FieldBlock key -> lift (requireField (rootFields definition) key) >>= fmap EntryField . allocate Nothing
        AdvisoryBlock advisory -> pure (EntryAdvisory advisory)
        RowAdvisoryBlock key advisory -> do
            source <- lift (requireList key)
            pure (EntryRowAdvisory source advisory)
        TableBlock key columns grouping ordering -> do
            source <- lift (requireList key)
            fields <- lift (mapM (requireField (listFields source)) columns)
            placements <- mapM (allocate (Just source)) fields
            pure (EntryTable source placements grouping ordering)
    sectionOccurrences (EntrySection _ _ blocks) = concatMap (\case
        EntryField placement -> [placement]
        EntryTable _ placements _ _ -> placements
        _ -> []) blocks

-- The caller supplies the authorized saved snapshot. Route row identities must
-- match the occurrence's pinned list; roots cannot be rebound to a row.
resolveEntryCell :: EntryLayout -> E.Snapshot -> Daily.DailyDocument -> Int -> Maybe E.RowId -> Either Daily.DailyError EntryCell
resolveEntryCell layout snapshot document index row = do
    placement <- maybe (Left Daily.UnknownDailyField) Right (Map.lookup index (entryOccurrences layout))
    let field = occurrenceField placement
    (target, address) <- case (occurrenceList placement, row) of
        (Nothing, Nothing) -> Right (E.RootTarget (fieldId field), Daily.RootCell (fieldId field))
        (Just source, Just key)
            | maybe False (Map.member key) (Map.lookup (listId source) (E.savedRows snapshot)) ->
                Right (E.RowTarget (listId source) key (fieldId field), Daily.RowCell (ReferenceKey (listId source) key) (fieldId field))
        (Just _, Just _) -> Left Daily.RowNoLongerExists
        _ -> Left Daily.UnknownDailyField
    let editable = fieldSource field == Entered && maybe True ((/= VenueReference) . listMode) (occurrenceList placement)
    saved <- if editable then Just <$> Daily.readCell document address else Right Nothing
    pure (EntryCell placement row target address saved)

-- Default ordering is the captured/source insertion order, not UUID ordering.
-- Authored grouping/ordering may reorder presentation, never membership.
entryRowIds :: RecordList -> ReferenceData -> Daily.DailyDocument -> [E.RowId]
entryRowIds source (ReferenceData references) document = case listMode source of
    VenueReference -> capturedRows (listId source)
    ReferenceChecklist paired -> filter (\row -> Set.member (ReferenceKey (listId source) row) savedRows) (capturedRows paired)
    OpenDaily -> [row | ReferenceKey list row <- Daily.rowKeys document, list == listId source]
  where
    savedRows = Set.fromList (Daily.rowKeys document)
    capturedRows key = [referenceRecordId row | list <- references, referenceListId list == key,
        row <- referenceRecords list, not (referenceRetired row)]
