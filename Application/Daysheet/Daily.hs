{-# LANGUAGE DeriveGeneric #-}
-- | Saved daily content and field-granular optimistic edits. This module has no
-- database authority: persistence must supply one authorized immutable capture.
-- Documents are server-owned; browser mutations must use typed commands.
module Application.Daysheet.Daily
    ( DailyDocument, Cell (..), CellAddress (..), DeletionPlan (..), DailyError (..)
    , emptyDaily, dailySnapshot, readCell, rowKeys
    , saveCell, addOpenRow, planDeletion, confirmDeletion
    , encodeDaily, decodeDaily
    ) where

import Prelude
import Application.Error.Parser (parserFailure)
import Application.Daysheet.Contract
import Application.Daysheet.Daily.Types
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Daysheet.ReferenceCodec ()
import Control.Monad (unless, when)
import Data.Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as ByteString
import Data.List (find)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import GHC.Generics (Generic)

-- Even blank cells retain their revision: clear-and-reenter must not allow an
-- old editor's ABA write. Deleted rows retain identity only, never old content.
data Cell = Cell { cellRevision :: Integer, cellValue :: Maybe ReferenceValue }
    deriving (Eq, Show, Generic)
data DailyRow = DailyRow
    { rowKey :: ReferenceKey, rowRevision :: Integer, rowCells :: [(FieldId, Cell)] }
    deriving (Eq, Generic)
data DailyDocument = DailyDocument
    { rootCells :: [(FieldId, Cell)], rows :: [DailyRow], deleted :: [ReferenceKey] }
    deriving (Eq)
instance Show DailyDocument where show _ = "DailyDocument <redacted>"
data DailyError
    = InvalidDailyDocument | DailyLimit | UnknownDailyField | UnknownDailyList
    | ReadOnlyDailyField | RowNoLongerExists | ChecklistRowsAreFixed
    | CellRevisionConflict | DeletionConfirmationChanged | InvalidDailyReference
    | InvalidDailyInput E.EvaluationError
    deriving (Eq, Show)

options :: Options
options = defaultOptions { rejectUnknownFields = True }
instance ToJSON Cell where toJSON = genericToJSON options
instance FromJSON Cell where parseJSON = genericParseJSON options
instance ToJSON DailyRow where toJSON = genericToJSON options
instance FromJSON DailyRow where parseJSON = genericParseJSON options

maxDailyBytes :: Int
maxDailyBytes = 4194304

encodeDaily :: DailyDocument -> Either DailyError Value
encodeDaily document = do
    let value = object ["version" .= (1 :: Int), "cells" .= rootCells document, "rows" .= rows document, "deleted" .= deleted document]
    unless (ByteString.length (encode value) <= fromIntegral maxDailyBytes) (Left DailyLimit)
    pure value

decodeDaily :: Definition -> ReferenceData -> E.SnapshotKey -> Value -> Either DailyError DailyDocument
decodeDaily definition references owner value = do
    unless (ByteString.length (encode value) <= fromIntegral maxDailyBytes) (Left DailyLimit)
    document <- either (const (Left InvalidDailyDocument)) Right (Aeson.parseEither parser value)
    _ <- dailySnapshot definition references owner document
    pure document
  where
    parser = withObject "daily document" \record -> do
        version <- record .: "version"
        unless (length record == 4 && version == (1 :: Int)) (parserFailure "invalid daily version")
        DailyDocument <$> record .: "cells" <*> record .: "rows" <*> record .: "deleted"

emptyDaily :: Definition -> ReferenceData -> E.SnapshotKey -> Either DailyError DailyDocument
emptyDaily definition references owner = do
    captured <- either (const (Left InvalidDailyDocument)) Right (captureReferences definition owner references)
    let document = DailyDocument []
            [DailyRow (ReferenceKey (listId list) key) 0 []
            | list <- recordLists definition, ReferenceChecklist source <- [listMode list]
            , key <- Map.keys (Map.findWithDefault Map.empty source (E.savedRows captured))] []
    _ <- dailySnapshot definition references owner document
    pure document

rowKeys :: DailyDocument -> [ReferenceKey]
rowKeys = map rowKey . rows

readCell :: DailyDocument -> CellAddress -> Either DailyError Cell
readCell document address = do
    cells <- case address of
        RootCell _ -> Right (rootCells document)
        RowCell key _ -> rowCells <$> findRow document key
    pure (maybe (Cell 0 Nothing) id (lookup (addressField address) cells))

addressField :: CellAddress -> FieldId
addressField (RootCell field) = field
addressField (RowCell _ field) = field

findRow :: DailyDocument -> ReferenceKey -> Either DailyError DailyRow
findRow document key = maybe (Left RowNoLongerExists) Right (find ((== key) . rowKey) (rows document))

findList :: Definition -> ListId -> Either DailyError RecordList
findList definition key = maybe (Left UnknownDailyList) Right (find ((== key) . listId) (recordLists definition))

editable :: Definition -> CellAddress -> Either DailyError ()
editable definition address = do
    fields <- case address of
        RootCell _ -> Right (rootFields definition)
        RowCell (ReferenceKey list _) _ -> do
            source <- findList definition list
            when (listMode source == VenueReference) (Left ReadOnlyDailyField)
            pure (listFields source)
    field <- maybe (Left UnknownDailyField) Right (find ((== addressField address) . fieldId) fields)
    unless (fieldSource field == Entered) (Left ReadOnlyDailyField)

nextRevision :: Integer -> Either DailyError Integer
nextRevision revision
    | revision < 0 || revision >= 2147483647 = Left DailyLimit
    | otherwise = Right (revision + 1)

-- Validation precedes projection so missing/blank values cannot hide unknown,
-- calculated, duplicate, or venue-owned cells in a persisted document.
dailySnapshot :: Definition -> ReferenceData -> E.SnapshotKey -> DailyDocument -> Either DailyError E.Snapshot
dailySnapshot definition references owner document = do
    captured <- either (const (Left InvalidDailyDocument)) Right (captureReferences definition owner references)
    _ <- encodeDaily document
    unique (rowKeys document <> deleted document)
    when (length (deleted document) > 100000) (Left DailyLimit)
    validateCells RootCell (rootCells document)
    mapM_ validateRow (rows document)
    mapM_ (\(ReferenceKey list _) -> findList definition list >>= \source -> unless (listMode source == OpenDaily) (Left InvalidDailyDocument)) (deleted document)
    mapM_ (checkChecklist captured) (recordLists definition)
    let snapshot = captured
            { E.savedRoot = values (rootCells document)
            , E.savedRows = Map.unionWith Map.union (Map.fromListWith Map.union
                [(list, Map.singleton key (values (rowCells row))) | row <- rows document, let ReferenceKey list key = rowKey row]) (E.savedRows captured) }
    mapM_ (checkStoredValue snapshot) (allCells document)
    either (Left . InvalidDailyInput) (const (Right snapshot)) (E.prepareEvaluation definition snapshot)
  where
    unique keys = unless (length keys == Set.size (Set.fromList keys)) (Left InvalidDailyDocument)
    validateCells address cells = do
        when (length cells > maxFields limits) (Left DailyLimit)
        unique (map fst cells)
        mapM_ (\(key, cell) -> editable definition (address key) >> validRevision (cellRevision cell)) cells
    validRevision revision = unless (revision >= 0 && revision <= 2147483647) (Left InvalidDailyDocument)
    validateRow row = do
        let ReferenceKey list _ = rowKey row
        source <- findList definition list
        when (listMode source == VenueReference) (Left InvalidDailyDocument)
        validRevision (rowRevision row)
        validateCells (RowCell (rowKey row)) (rowCells row)
    checkChecklist captured list = case listMode list of
        ReferenceChecklist source -> unless
            (Map.fromList [(key, ()) | ReferenceKey listKey key <- rowKeys document, listKey == listId list]
                == Map.map (const ()) (Map.findWithDefault Map.empty source (E.savedRows captured))) (Left ChecklistRowsAreFixed)
        _ -> Right ()
    values = Map.fromList . mapMaybe (\(field, cell) -> fmap (\value -> (field, scoped value)) (cellValue cell))
    scoped (ReferenceScalar literal) = E.Scalar literal
    scoped (ReferenceLink (ReferenceKey list row)) = E.Reference (E.RecordReference owner list row)
    checkStoredValue snapshot (_, Cell _ (Just (ReferenceLink (ReferenceKey list row)))) =
        unless (maybe False (Map.member row) (Map.lookup list (E.savedRows snapshot))) (Left InvalidDailyReference)
    -- PostgreSQL JSONB cannot represent NUL. Reject it at the typed boundary,
    -- not as a database exception after an otherwise valid edit.
    checkStoredValue _ (address, Cell _ (Just (ReferenceScalar (TextLiteral value)))) =
        when (Text.any (== '\NUL') value) (Left (InvalidDailyInput (E.InvalidInput (addressField address))))
    checkStoredValue _ _ = Right ()

saveCell :: Definition -> ReferenceData -> E.SnapshotKey -> CellAddress -> Integer -> Maybe ReferenceValue -> DailyDocument -> Either DailyError DailyDocument
saveCell definition references owner address expected value document = do
    editable definition address
    previous <- readCell document address
    unless (cellRevision previous == expected) (Left CellRevisionConflict)
    revision <- nextRevision expected
    updated <- replaceCell address (Cell revision value) document
    _ <- dailySnapshot definition references owner updated
    pure updated

replaceCell :: CellAddress -> Cell -> DailyDocument -> Either DailyError DailyDocument
replaceCell address cell document = case address of
    RootCell key -> Right document { rootCells = setCell key (rootCells document) }
    RowCell key field -> do
        row <- findRow document key
        revision <- nextRevision (rowRevision row)
        pure document { rows = map (\candidate -> if rowKey candidate == key then row { rowRevision = revision, rowCells = setCell field (rowCells row) } else candidate) (rows document) }
  where
    setCell key cells = (key, cell) : filter ((/= key) . fst) cells

addOpenRow :: Definition -> ReferenceData -> E.SnapshotKey -> ReferenceKey -> DailyDocument -> Either DailyError DailyDocument
addOpenRow definition references owner key@(ReferenceKey list _) document = do
    source <- findList definition list
    unless (listMode source == OpenDaily) (Left ChecklistRowsAreFixed)
    when (key `elem` deleted document) (Left RowNoLongerExists)
    let updated = if key `elem` rowKeys document then document else document { rows = rows document <> [DailyRow key 0 []] }
    _ <- dailySnapshot definition references owner updated
    pure updated

allCells :: DailyDocument -> [(CellAddress, Cell)]
allCells document = [(RootCell key, cell) | (key, cell) <- rootCells document]
    <> [(RowCell (rowKey row) key, cell) | row <- rows document, (key, cell) <- rowCells row]

planDeletion :: Definition -> ReferenceKey -> DailyDocument -> Either DailyError DeletionPlan
planDeletion definition key@(ReferenceKey list _) document = do
    source <- findList definition list
    unless (listMode source == OpenDaily) (Left ChecklistRowsAreFixed)
    row <- findRow document key
    pure (DeletionPlan key (rowRevision row) (Map.toAscList (Map.fromList
        [(address, cellRevision cell) | (address, cell) <- allCells document
        , cellValue cell == Just (ReferenceLink key), outsideTarget address])))
  where
    outsideTarget (RowCell source _) = source /= key
    outsideTarget (RootCell _) = True

confirmDeletion :: Definition -> ReferenceData -> E.SnapshotKey -> DeletionPlan -> DailyDocument -> Either DailyError DailyDocument
confirmDeletion definition references owner approved document = do
    current <- planDeletion definition (deletionTarget approved) document
    unless (current == approved) (Left DeletionConfirmationChanged)
    cleared <- clear (incomingCells current) document
    let updated = cleared { rows = filter ((/= deletionTarget current) . rowKey) (rows cleared), deleted = deletionTarget current : deleted cleared }
    _ <- dailySnapshot definition references owner updated
    pure updated
  where
    clear [] saved = Right saved
    clear ((address, revision) : rest) saved = do
        next <- nextRevision revision
        updated <- replaceCell address (Cell next Nothing) saved
        clear rest updated
