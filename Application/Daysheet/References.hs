-- | Venue reference data staged with definitions. Links are local to the
-- containing venue document; snapshot identity is attached only on capture.
module Application.Daysheet.References
    ( ReferenceKey (..), ReferenceValue (..), ReferenceRecord (..)
    , ReferenceList (..), ReferenceData (..), ReferenceError (..)
    , ReferenceChange (..), Dependency (..)
    , validateReferences, captureReferences, retirementDependencies, retireReferences
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
    | list <- lists])
  where
    convert (ReferenceScalar literal) = E.Scalar literal
    convert (ReferenceLink (ReferenceKey list row)) = E.Reference (E.RecordReference owner list row)

captureReferences :: Definition -> E.SnapshotKey -> ReferenceData -> Either ReferenceError E.Snapshot
captureReferences definition owner dataValue = do
    validateReferences definition owner dataValue
    pure (snapshot owner dataValue)

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
