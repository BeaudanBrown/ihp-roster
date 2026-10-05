-- | Venue reference data staged with definitions. Links are local to the
-- containing venue document; snapshot identity is attached only on capture.
module Application.Daysheet.References
    ( ReferenceKey (..), ReferenceValue (..), ReferenceRecord (..)
    , ReferenceList (..), ReferenceData (..), ReferenceError (..)
    , ReferenceChange (..), Dependency (..), ReferenceEdit (..), editReferenceData
    , validateReferences, captureReferences, retirementDependencies, retireReferences
    , preservesReferences, activeReferenceData, preservesRetirementState
    ) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Evaluation as E
import qualified Data.Map.Strict as Map
import Data.List (nub)

-- Full scope includes the list even where record UUIDs happen to coincide.
data ReferenceKey = ReferenceKey ListId E.RowId deriving (Eq, Ord, Show)
data ReferenceValue = ReferenceScalar Literal | ReferenceLink ReferenceKey deriving (Eq, Show)
data ReferenceRecord = ReferenceRecord
    { referenceRecordId :: E.RowId
    , referenceRetired :: Bool
    , referenceValues :: [(FieldId, ReferenceValue)]
    } deriving (Eq, Show)
data ReferenceList = ReferenceList
    { referenceListId :: ListId
    , referenceRecords :: [ReferenceRecord]
    } deriving (Eq, Show)
newtype ReferenceData = ReferenceData [ReferenceList] deriving (Eq, Show)
data ReferenceError
    = ReferenceLimit
    | DuplicateReferenceIdentity
    | UnknownReferenceList ListId
    | MissingReferenceRecord ReferenceKey
    | DanglingActiveReference ReferenceKey FieldId ReferenceKey
    | InvalidReferenceValues E.EvaluationError
    | InvalidReferenceChange
    deriving (Eq, Show)
data ReferenceChange
    = RetireReference ReferenceKey
    | ReassignReference ReferenceKey FieldId ReferenceKey
    deriving (Eq, Show)
data Dependency = Dependency ReferenceKey FieldId deriving (Eq, Ord, Show)

-- Typed staging operations, not a replacement document supplied by a browser.
-- Retirement retains the existing explicit dependency-resolution operation.
data ReferenceEdit
    = AddReferenceRecord ListId E.RowId
    | SetReferenceValue ReferenceKey FieldId (Maybe ReferenceValue)
    | RetireReferenceRecord ReferenceKey [ReferenceChange]
    deriving (Eq, Show)

-- A draft can contain values made incompatible by a definition change. Validate
-- each new value with the canonical reference/evaluation authority, without
-- requiring all other old values to be repaired in the same browser request.
-- Publication still validates the complete document. No operation resurrects
-- or silently removes an identity, changes a different cell, or edits history.
editReferenceData :: Definition -> E.SnapshotKey -> ReferenceData -> ReferenceEdit -> Either ReferenceError ReferenceData
editReferenceData definition owner original@(ReferenceData lists) edit = case edit of
    AddReferenceRecord source identity -> do
        _ <- sourceList source
        case [row | list <- lists, referenceListId list == source, row <- referenceRecords list, referenceRecordId row == identity] of
            [] -> Right ()
            _ -> Left DuplicateReferenceIdentity
        let row = ReferenceRecord identity False []
        case [list | list <- lists, referenceListId list == source] of
            [] | length lists < maxLists limits -> Right (ReferenceData (lists <> [ReferenceList source [row]]))
            [list] | length (referenceRecords list) < maxRowsPerList limits ->
                Right (ReferenceData (map (\value -> if referenceListId value == source then value { referenceRecords = referenceRecords value <> [row] } else value) lists))
            _ -> Left ReferenceLimit
    SetReferenceValue key@(ReferenceKey source identity) field value -> do
        row <- activeRow key
        case value of
            Nothing -> case lookup field (referenceValues row) of
                Just _ -> Right () -- Explicit correction of a removed/retyped field.
                Nothing -> do
                    declared <- sourceList source
                    case [entry | entry <- listFields declared, fieldId entry == field, fieldSource entry == Entered] of
                        [_] -> Right ()
                        _ -> Left InvalidReferenceChange
            Just entered -> do
                -- Include only the changed cell and, for a link, its real active
                -- destination identity. Other stored values need not yet match
                -- the draft, but cannot make a forged new value permissible.
                destination <- case entered of
                    ReferenceScalar _ -> Right []
                    ReferenceLink target@(ReferenceKey targetList targetRow) -> do
                        _ <- activeRow target
                        pure [(targetList, targetRow) | target /= key]
                let changedRow = ReferenceRecord identity False [(field, entered)]
                    selected = case destination of
                        [(targetList, targetRow)] | targetList == source ->
                            [ReferenceList source [changedRow, ReferenceRecord targetRow False []]]
                        [(targetList, targetRow)] ->
                            [ReferenceList source [changedRow], ReferenceList targetList [ReferenceRecord targetRow False []]]
                        _ -> [ReferenceList source [changedRow]]
                validateReferences definition owner (ReferenceData selected)
        let changed = row { referenceValues = filter ((/= field) . fst) (referenceValues row) <> maybe [] (\entered -> [(field, entered)]) value }
        pure (ReferenceData (map (\list -> if referenceListId list == source
            then list { referenceRecords = map (\record -> if referenceRecordId record == identity then changed else record) (referenceRecords list) }
            else list) lists))
    RetireReferenceRecord key changes -> retireReferences definition owner original key changes
  where
    sourceList source = case [list | list <- recordLists definition, listId list == source, listMode list == VenueReference] of
        [list] -> Right list
        _ -> Left (UnknownReferenceList source)
    activeRow key@(ReferenceKey source identity) = case
        [row | list <- lists, referenceListId list == source, row <- referenceRecords list, referenceRecordId row == identity, not (referenceRetired row)] of
        [row] -> Right row
        _ -> Left (MissingReferenceRecord key)

validateReferences :: Definition -> E.SnapshotKey -> ReferenceData -> Either ReferenceError ()
validateReferences definition owner dataValue@(ReferenceData lists) = do
    if length lists > maxLists limits then Left ReferenceLimit else Right ()
    unique (map referenceListId lists)
    mapM_ validateList lists
    mapM_ validateLinks active
    either (Left . InvalidReferenceValues) (const (Right ())) (E.prepareEvaluation definition (snapshot owner dataValue))
  where
    unique keys = if length keys == length (nub keys) then Right () else Left DuplicateReferenceIdentity
    active = [(ReferenceKey (referenceListId list) (referenceRecordId row), row) | list <- lists, row <- referenceRecords list, not (referenceRetired row)]
    activeKeys = Map.fromList [(key, ()) | (key, _) <- active]
    validateList list = do
        case filter ((== referenceListId list) . listId) (recordLists definition) of
            [source] | listMode source == VenueReference -> Right ()
            _ | all referenceRetired (referenceRecords list) -> Right ()
            _ -> Left (UnknownReferenceList (referenceListId list))
        if length (referenceRecords list) > maxRowsPerList limits then Left ReferenceLimit else Right ()
        unique (map referenceRecordId (referenceRecords list))
        mapM_ (\row -> do
            if length (referenceValues row) > maxFields limits then Left ReferenceLimit else Right ()
            unique (map fst (referenceValues row))) (referenceRecords list)
    validateLinks (source, row) = mapM_ (\(field, value) -> case value of
        ReferenceLink target | not (Map.member target activeKeys) -> Left (DanglingActiveReference source field target)
        _ -> Right ()) (referenceValues row)

snapshot :: E.SnapshotKey -> ReferenceData -> E.Snapshot
snapshot owner (ReferenceData lists) = E.Snapshot owner Map.empty (Map.fromList
    [(referenceListId list, Map.fromList
        [(referenceRecordId row, Map.fromList [(field, convert value) | (field, value) <- referenceValues row])
        | row <- referenceRecords list, not (referenceRetired row)])
    | list <- lists, any (not . referenceRetired) (referenceRecords list)])
  where
    convert (ReferenceScalar literal) = E.Scalar literal
    convert (ReferenceLink (ReferenceKey list row)) = E.Reference (E.RecordReference owner list row)

captureReferences :: Definition -> E.SnapshotKey -> ReferenceData -> Either ReferenceError E.Snapshot
captureReferences definition owner dataValue = do
    validateReferences definition owner dataValue
    pure (snapshot owner dataValue)

-- Retired identities survive configuration changes, even if their list has
-- been removed from the future definition. They never enter new captures.
activeReferenceData :: ReferenceData -> ReferenceData
activeReferenceData (ReferenceData lists) = ReferenceData
    [list { referenceRecords = rows } | list <- lists, let rows = filter (not . referenceRetired) (referenceRecords list), not (null rows)]

preservesReferences :: ReferenceData -> ReferenceData -> Bool
preservesReferences (ReferenceData before) (ReferenceData after) = all retained oldRows
  where
    oldRows = [(ReferenceKey (referenceListId list) (referenceRecordId row), referenceRetired row) | list <- before, row <- referenceRecords list]
    newRows = Map.fromList [(ReferenceKey (referenceListId list) (referenceRecordId row), referenceRetired row) | list <- after, row <- referenceRecords list]
    retained (key, wasRetired) = case Map.lookup key newRows of
        Nothing -> False
        Just isRetired -> not wasRetired || isRetired

preservesRetirementState :: ReferenceData -> ReferenceData -> Bool
preservesRetirementState (ReferenceData before) (ReferenceData after) =
    all (\(key, state) -> Map.lookup key newRows == Just state) (Map.toList oldRows)
        && all (\(key, state) -> Map.member key oldRows || not state) (Map.toList newRows)
  where
    states lists = Map.fromList [(ReferenceKey (referenceListId list) (referenceRecordId row), referenceRetired row) | list <- lists, row <- referenceRecords list]
    oldRows = states before
    newRows = states after

retirementDependencies :: ReferenceData -> ReferenceKey -> [Dependency]
retirementDependencies (ReferenceData lists) target =
    [Dependency (ReferenceKey (referenceListId list) (referenceRecordId row)) field
    | list <- lists, row <- referenceRecords list, not (referenceRetired row)
    , (field, ReferenceLink linked) <- referenceValues row, linked == target]

-- | Every additional retirement/reassignment is an explicit caller choice.
-- No cascade is inferred from dependencies. The caller must hold/check the
-- observed configuration revision before applying the returned document.
retireReferences :: Definition -> E.SnapshotKey -> ReferenceData -> ReferenceKey -> [ReferenceChange] -> Either ReferenceError ReferenceData
retireReferences definition owner original target changes = do
    validateReferences definition owner original
    -- Apply the requested row and all confirmed choices only in memory. If any
    -- active dangling reference remains, no changed document escapes.
    changed <- foldChanges original (RetireReference target : changes)
    validateReferences definition owner changed
    pure changed
  where
    foldChanges dataValue [] = Right dataValue
    foldChanges dataValue (change : rest) = applyChange dataValue change >>= \next -> foldChanges next rest
    applyChange (ReferenceData lists) change = do
        let source = case change of RetireReference key -> key; ReassignReference key _ _ -> key
        let ReferenceKey listId rowId = source
        case [row | list <- lists, referenceListId list == listId, row <- referenceRecords list, referenceRecordId row == rowId, not (referenceRetired row)] of
            [_] -> Right ()
            _ -> Left (MissingReferenceRecord source)
        ReferenceData <$> traverse (updateList listId rowId change) lists
    updateList listId rowId change list
        | referenceListId list /= listId = Right list
        | otherwise = do
            rows <- traverse (updateRow rowId change) (referenceRecords list)
            pure (list { referenceRecords = rows })
    updateRow rowId change row
        | referenceRecordId row /= rowId = Right row
        | otherwise = case change of
            RetireReference _ -> Right (row { referenceRetired = True })
            ReassignReference _ field targetKey ->
                case lookup field (referenceValues row) of
                    Just (ReferenceLink _) -> Right (row { referenceValues = [(key, if key == field then ReferenceLink targetKey else value) | (key, value) <- referenceValues row] })
                    _ -> Left InvalidReferenceChange
