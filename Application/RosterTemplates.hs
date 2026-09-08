{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.RosterTemplates
    ( RosterTemplateActor
    , RosterTemplateColumnInput (..)
    , RosterTemplateContent (..)
    , RosterTemplateDayInput (..)
    , RosterTemplateError (..)
    , RosterTemplateLibrary (..)
    , RosterTemplateShiftInput (..)
    , RosterTemplateSnapshot (..)
    , createRosterTemplate
    , createRosterTemplateInCurrentTransaction
    , currentRosterTemplateActor
    , fetchRosterTemplate
    , fetchRosterTemplateLibrary
    , fetchSavedRosterTemplate
    , remediateRosterTemplateAssignmentsInCurrentTransaction
    , replaceRosterTemplateContent
    , replaceRosterTemplateContentInCurrentTransaction
    , rosterTemplateActor
    , rosterTemplateActorCanEditRosters
    , rosterTemplateActorUserId
    , rosterTemplateActorVenueId
    , rosterTemplateContentRevision
    , rosterTemplateSnapshotRevision
    , softDeleteRosterTemplate
    , softDeleteRosterTemplateInCurrentTransaction
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.ControllerAccess (hasRole,
                                            isCurrentVenueManuallyReadOnly)
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentVenue)
import Application.PayAssignment (EffectivePayAssignment (..),
                                  ShiftPayAssignment (..),
                                  StaffPayAssignment (..), resolvePayAssignment,
                                  shiftPayAssignmentRequiresRemediation,
                                  staffPayAssignmentRequiresRemediation)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates.Mutations (lockRosterTemplate,
                                              lockRosterTemplateContentReferenceRows,
                                              lockRosterTemplateName)
import Control.Monad (void)
import qualified "crypton" Crypto.Hash as Hash
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude

data RosterTemplateActor = RosterTemplateActor
    { actorUserId         :: !(Id User)
    , actorVenueId        :: !(Id Venue)
    , actorCanEditRosters :: !Bool
    }
    deriving (Eq, Show)

data RosterTemplateDayInput = RosterTemplateDayInput
    { inputDayIndex        :: !Int
    , inputDayWeekdayIndex :: !(Maybe Int)
    , inputDayIsClosed     :: !Bool
    , inputDayRowCount     :: !Int
    }
    deriving (Eq, Show)

data RosterTemplateColumnInput = RosterTemplateColumnInput
    { inputColumnName      :: !Text
    , inputColumnSortOrder :: !Int
    }
    deriving (Eq, Show)

data RosterTemplateShiftInput = RosterTemplateShiftInput
    { inputShiftDayIndex        :: !Int
    , inputShiftColumnSortOrder :: !Int
    , inputShiftRowIndex        :: !Int
    , inputShiftStartMinute     :: !Int
    , inputShiftEndMinute       :: !Int
    , inputShiftTypeId          :: !(Id ShiftType)
    , inputShiftAssignment      :: !RosterShiftAssignment
    }
    deriving (Eq, Show)

data RosterTemplateContent = RosterTemplateContent
    { contentDays    :: ![RosterTemplateDayInput]
    , contentColumns :: ![RosterTemplateColumnInput]
    , contentShifts  :: ![RosterTemplateShiftInput]
    }
    deriving (Eq, Show)

data RosterTemplateSnapshot = RosterTemplateSnapshot
    { snapshotTemplate :: !RosterTemplate
    , snapshotDays     :: ![RosterTemplateDay]
    , snapshotColumns  :: ![RosterTemplateColumn]
    , snapshotShifts   :: ![RosterTemplateShift]
    }
    deriving (Eq, Show)

data RosterTemplateLibrary = RosterTemplateLibrary
    { libraryTemplates   :: ![RosterTemplate]
    , libraryShiftCounts :: !(Map.Map (Id RosterTemplate) Int)
    }
    deriving (Eq, Show)

data RosterTemplateError
    = RosterTemplateForbidden
    | RosterTemplateInvalidName
    | RosterTemplateDuplicateName
    | RosterTemplateScopeMismatch
    | RosterTemplateUnsupportedScale
    | RosterTemplateInvalidContent !Text
    | RosterTemplateNotFound
    | RosterTemplateInvalidShiftTypes ![Id ShiftType]
    deriving (Eq, Show)

currentRosterTemplateActor ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO RosterTemplateActor
currentRosterTemplateActor = do
    venueReadOnly <- isCurrentVenueManuallyReadOnly
    pure (rosterTemplateActor authenticatedCurrentUser currentVenue (hasRole Manager && not venueReadOnly))

rosterTemplateActor :: User -> Venue -> Bool -> RosterTemplateActor
rosterTemplateActor user venue canEditRosters =
    RosterTemplateActor
        { actorUserId = user.id
        , actorVenueId = venue.id
        , actorCanEditRosters = canEditRosters
        }

rosterTemplateActorCanEditRosters :: RosterTemplateActor -> Bool
rosterTemplateActorCanEditRosters = (.actorCanEditRosters)

rosterTemplateActorUserId :: RosterTemplateActor -> Id User
rosterTemplateActorUserId = (.actorUserId)

rosterTemplateActorVenueId :: RosterTemplateActor -> Id Venue
rosterTemplateActorVenueId = (.actorVenueId)

createRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateSnapshot)
createRosterTemplate actor rosterGroup scale requestedName content =
    withTransaction (createRosterTemplateInCurrentTransaction actor rosterGroup scale requestedName content)

createRosterTemplateInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateSnapshot)
createRosterTemplateInCurrentTransaction actor rosterGroup scale requestedName content
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | rosterGroup.venueId /= unpackId actor.actorVenueId = pure (Left RosterTemplateScopeMismatch)
    | scale /= Week = pure (Left RosterTemplateUnsupportedScale)
    | invalidTemplateName normalizedName = pure (Left RosterTemplateInvalidName)
    | otherwise = case validateTemplateContent content of
        Left problem -> pure (Left problem)
        Right () -> do
            references <- validateContentReferences actor rosterGroup.id content
            case references of
                Left problem -> pure (Left problem)
                Right () -> do
                    available <- rosterTemplateNameAvailable rosterGroup.id normalizedName
                    if not available
                        then pure (Left RosterTemplateDuplicateName)
                        else do
                            template <-
                                newRecord @RosterTemplate
                                    |> set #rosterGroupId (unpackId rosterGroup.id)
                                    |> set #name normalizedName
                                    |> set #scale scale
                                    |> set #createdByUserId (unpackId actor.actorUserId)
                                    |> createRecord
                            persistTemplateContent template content
                            Right <$> loadRosterTemplate template
  where
    normalizedName = Text.strip requestedName

replaceRosterTemplateContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateSnapshot)
replaceRosterTemplateContent actor templateId content =
    withTransaction (replaceRosterTemplateContentInCurrentTransaction actor templateId content)

replaceRosterTemplateContentInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateSnapshot)
replaceRosterTemplateContentInCurrentTransaction actor templateId content
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = case validateTemplateContent content of
        Left problem -> pure (Left problem)
        Right () -> do
            exists <- lockRosterTemplate templateId
            maybeTemplate <- if exists then fetchScopedTemplate actor templateId else pure Nothing
            case maybeTemplate of
                Nothing -> pure (Left RosterTemplateNotFound)
                Just template -> do
                    references <- validateContentReferences actor (Id template.rosterGroupId) content
                    case references of
                        Left problem -> pure (Left problem)
                        Right () -> do
                            persistTemplateContent template content
                            now <- getCurrentTime
                            updated <- template |> set #updatedAt now |> updateRecord
                            Right <$> loadRosterTemplate updated

remediateRosterTemplateAssignmentsInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateSnapshot ->
    [Id RosterTemplateShift] ->
    IO (Either RosterTemplateError RosterTemplateSnapshot)
remediateRosterTemplateAssignmentsInCurrentTransaction actor snapshot invalidShiftIds
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = do
        let templateId = snapshot.snapshotTemplate.id
        exists <- lockRosterTemplate templateId
        maybeTemplate <- if exists then fetchScopedTemplate actor templateId else pure Nothing
        case maybeTemplate of
            Nothing -> pure (Left RosterTemplateNotFound)
            Just template -> do
                _ :: Bool <- unsafeSqlQueryScalar
                    "SELECT remediate_roster_template_assignments(?, ?)"
                    (unpackId template.id, map unpackId invalidShiftIds)
                Right <$> loadRosterTemplate template

fetchRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Maybe RosterTemplateSnapshot)
fetchRosterTemplate actor templateId
    | not actor.actorCanEditRosters = pure Nothing
    | otherwise = do
        maybeTemplate <- fetchScopedTemplate actor templateId
        case maybeTemplate of
            Nothing       -> pure Nothing
            Just template -> Just <$> loadRosterTemplate template

fetchSavedRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Maybe RosterTemplateSnapshot)
fetchSavedRosterTemplate = fetchRosterTemplate

fetchRosterTemplateLibrary ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    IO (Maybe RosterTemplateLibrary)
fetchRosterTemplateLibrary actor rosterGroup
    | not actor.actorCanEditRosters = pure Nothing
    | rosterGroup.venueId /= unpackId actor.actorVenueId = pure Nothing
    | otherwise = do
        templates <-
            query @RosterTemplate
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhere (#deletedAt, Nothing)
                |> filterWhere (#scale, Week)
                |> orderByAsc #name
                |> fetch
        shifts <- if null templates
            then pure []
            else query @RosterTemplateShift
                |> filterWhereIn (#rosterTemplateId, map (unpackId . (.id)) templates)
                |> fetch
        pure (Just RosterTemplateLibrary
            { libraryTemplates = sortOn (Text.toCaseFold . (.name)) templates
            , libraryShiftCounts = Map.fromListWith (+) [(Id shift.rosterTemplateId, 1) | shift <- shifts]
            })

softDeleteRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplate actor templateId reason =
    withTransaction (softDeleteRosterTemplateInCurrentTransaction actor templateId reason)

softDeleteRosterTemplateInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplateInCurrentTransaction actor templateId reason
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = do
        exists <- lockRosterTemplate templateId
        maybeTemplate <- if exists then fetchScopedTemplate actor templateId else pure Nothing
        case maybeTemplate of
            Nothing -> pure (Left RosterTemplateNotFound)
            Just template -> do
                now <- getCurrentTime
                template
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId actor.actorUserId))
                    |> set #deleteReason (Just (Text.take 500 (Text.strip reason)))
                    |> set #updatedAt now
                    |> updateRecord
                    |> void
                pure (Right ())

fetchScopedTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Maybe RosterTemplate)
fetchScopedTemplate actor templateId = do
    maybeTemplate <-
        query @RosterTemplate
            |> filterWhere (#id, templateId)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOneOrNothing
    case maybeTemplate of
        Nothing -> pure Nothing
        Just template -> do
            inVenue <-
                query @RosterGroup
                    |> filterWhere (#id, Id template.rosterGroupId)
                    |> filterWhere (#venueId, unpackId actor.actorVenueId)
                    |> fetchExists
            pure (if inVenue then Just template else Nothing)

loadRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplate ->
    IO RosterTemplateSnapshot
loadRosterTemplate template = do
    days <- query @RosterTemplateDay |> filterWhere (#rosterTemplateId, unpackId template.id) |> orderByAsc #dayIndex |> fetch
    columns <- query @RosterTemplateColumn |> filterWhere (#rosterTemplateId, unpackId template.id) |> orderByAsc #sortOrder |> fetch
    shifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateId, unpackId template.id) |> orderByAsc #rowIndex |> fetch
    pure RosterTemplateSnapshot
        { snapshotTemplate = template
        , snapshotDays = days
        , snapshotColumns = columns
        , snapshotShifts = shifts
        }

persistTemplateContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplate ->
    RosterTemplateContent ->
    IO ()
persistTemplateContent template content = do
    oldShifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateId, unpackId template.id) |> fetch
    oldDays <- query @RosterTemplateDay |> filterWhere (#rosterTemplateId, unpackId template.id) |> fetch
    oldColumns <- query @RosterTemplateColumn |> filterWhere (#rosterTemplateId, unpackId template.id) |> fetch
    deleteRecords oldShifts
    deleteRecords oldDays
    deleteRecords oldColumns
    days <- forM content.contentDays (createTemplateDay template)
    columns <- forM content.contentColumns (createTemplateColumn template)
    let daysByIndex = Map.fromList [(day.dayIndex, day) | day <- days]
    let columnsBySortOrder = Map.fromList [(column.sortOrder, column) | column <- columns]
    forM_ content.contentShifts (createTemplateShift template daysByIndex columnsBySortOrder)
    newRecord @RosterTemplateCompletion
        |> set #id template.completionId
        |> set #rosterTemplateId (unpackId template.id)
        |> createRecord
        |> void

createTemplateDay ::
    (?modelContext :: ModelContext) =>
    RosterTemplate ->
    RosterTemplateDayInput ->
    IO RosterTemplateDay
createTemplateDay template input =
    newRecord @RosterTemplateDay
        |> set #rosterTemplateId (unpackId template.id)
        |> set #dayIndex input.inputDayIndex
        |> set #weekdayIndex input.inputDayWeekdayIndex
        |> set #isClosed input.inputDayIsClosed
        |> set #rowCount input.inputDayRowCount
        |> createRecord

createTemplateColumn ::
    (?modelContext :: ModelContext) =>
    RosterTemplate ->
    RosterTemplateColumnInput ->
    IO RosterTemplateColumn
createTemplateColumn template input =
    newRecord @RosterTemplateColumn
        |> set #rosterTemplateId (unpackId template.id)
        |> set #name (Text.strip input.inputColumnName)
        |> set #sortOrder input.inputColumnSortOrder
        |> createRecord

createTemplateShift ::
    (?modelContext :: ModelContext) =>
    RosterTemplate ->
    Map.Map Int RosterTemplateDay ->
    Map.Map Int RosterTemplateColumn ->
    RosterTemplateShiftInput ->
    IO RosterTemplateShift
createTemplateShift template daysByIndex columnsBySortOrder input = do
    let day = fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated template day missing") (Map.lookup input.inputShiftDayIndex daysByIndex)
    let column = fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated template column missing") (Map.lookup input.inputShiftColumnSortOrder columnsBySortOrder)
    let (assignmentState, staffId) = case input.inputShiftAssignment of
            StaffAssignment assignedStaffId -> ("staff", Just (unpackId assignedStaffId))
            OpenAssignment -> ("open", Nothing)
    newRecord @RosterTemplateShift
        |> set #rosterTemplateId (unpackId template.id)
        |> set #rosterTemplateDayId (unpackId day.id)
        |> set #rosterTemplateColumnId (unpackId column.id)
        |> set #assignmentState assignmentState
        |> set #staffId staffId
        |> set #rowIndex input.inputShiftRowIndex
        |> set #startMinute input.inputShiftStartMinute
        |> set #endMinute input.inputShiftEndMinute
        |> set #shiftTypeId (unpackId input.inputShiftTypeId)
        |> createRecord

validateTemplateContent :: RosterTemplateContent -> Either RosterTemplateError ()
validateTemplateContent content
    | sort (map (.inputDayIndex) content.contentDays) /= [0 .. 6]
        || sort (mapMaybe (.inputDayWeekdayIndex) content.contentDays) /= [0 .. 6] =
        Left (RosterTemplateInvalidContent "A Week template must contain all seven unique weekdays.")
    | null content.contentColumns = Left (RosterTemplateInvalidContent "A template must contain at least one column.")
    | not (all validDay content.contentDays) = Left invalidStructure
    | not (unique (map (.inputDayIndex) content.contentDays)) = Left invalidStructure
    | not (all validColumn content.contentColumns) = Left invalidStructure
    | not (unique (map (.inputColumnSortOrder) content.contentColumns)) = Left invalidStructure
    | not (unique (map (Text.toCaseFold . Text.strip . (.inputColumnName)) content.contentColumns)) = Left invalidStructure
    | not (unique (map shiftCell content.contentShifts)) = Left invalidStructure
    | not (all validShift content.contentShifts) = Left invalidStructure
    | otherwise = Right ()
  where
    invalidStructure = RosterTemplateInvalidContent "Template columns, shifts, rows, or times are invalid."
    daysByIndex = Map.fromList [(day.inputDayIndex, day) | day <- content.contentDays]
    columnSortOrders = map (.inputColumnSortOrder) content.contentColumns
    validDay day = day.inputDayIndex >= 0 && day.inputDayIndex <= 6 && day.inputDayRowCount >= 0
    validColumn column =
        let normalized = Text.strip column.inputColumnName
         in not (Text.null normalized)
                && Text.length normalized <= 120
                && column.inputColumnSortOrder >= 0
    shiftCell shift = (shift.inputShiftDayIndex, shift.inputShiftColumnSortOrder, shift.inputShiftRowIndex)
    validShift shift = case Map.lookup shift.inputShiftDayIndex daysByIndex of
        Nothing -> False
        Just day ->
            shift.inputShiftColumnSortOrder `elem` columnSortOrders
                && shift.inputShiftRowIndex >= 0
                && shift.inputShiftRowIndex < day.inputDayRowCount
                && shift.inputShiftStartMinute >= 0
                && shift.inputShiftEndMinute > shift.inputShiftStartMinute
                && shift.inputShiftEndMinute <= 2880

validateContentReferences ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterGroup ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError ())
validateContentReferences actor rosterGroupId content = do
    let shiftTypeIds = nub (map (.inputShiftTypeId) content.contentShifts)
    let staffIds = nub [staffId | shift <- content.contentShifts, StaffAssignment staffId <- [shift.inputShiftAssignment]]
    lockRosterTemplateContentReferenceRows rosterGroupId shiftTypeIds staffIds
    shiftTypes <- if null shiftTypeIds then pure [] else query @ShiftType |> filterWhereIn (#id, shiftTypeIds) |> fetch
    let invalidShiftTypes =
            [ shiftTypeId
            | shiftTypeId <- shiftTypeIds
            , case find ((== shiftTypeId) . (.id)) shiftTypes of
                Nothing -> True
                Just shiftType ->
                    shiftType.venueId /= unpackId actor.actorVenueId
                        || not shiftType.isActive
                        || isJust shiftType.archivedAt
            ]
    if not (null invalidShiftTypes)
        then pure (Left (RosterTemplateInvalidShiftTypes invalidShiftTypes))
        else do
            staff <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, staffIds) |> fetch
            memberships <-
                if null staffIds
                    then pure []
                    else query @StaffRosterGroup
                        |> filterWhereIn (#staffId, map unpackId staffIds)
                        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
            activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
            activeImportedPayItems <- query @XeroImportedPayItem
                |> filterWhere (#venueId, unpackId actor.actorVenueId)
                |> filterWhere (#archivedAt, Nothing)
                |> filterWhere (#providerAvailable, True)
                |> fetch
            let staffById = Map.fromList [(unpackId person.id, person) | person <- staff]
            let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
            let eligibleStaffIds = Set.fromList (map (.staffId) memberships)
            let activeAwardIds = map (.id) activeAwardLevels
            let activeImportedPayItemIds = map (.id) activeImportedPayItems
            let validShiftAssignment shift = case shift.inputShiftAssignment of
                    OpenAssignment -> True
                    StaffAssignment staffId ->
                        validStaffAssignment
                            activeAwardIds
                            activeImportedPayItemIds
                            eligibleStaffIds
                            actor.actorVenueId
                            (unpackId staffId)
                            (Map.lookup (unpackId staffId) staffById)
                            (Map.lookup (unpackId shift.inputShiftTypeId) shiftTypeById)
            pure if all validShiftAssignment content.contentShifts
                then Right ()
                else Left (RosterTemplateInvalidContent "Choose an available roster-group Staff member with valid pay configuration.")

validStaffAssignment ::
    [Id AwardLevel] ->
    [Id XeroImportedPayItem] ->
    Set.Set UUID ->
    Id Venue ->
    UUID ->
    Maybe Staff ->
    Maybe ShiftType ->
    Bool
validStaffAssignment activeAwardIds activeImportedPayItemIds eligibleStaffIds venueId staffId maybeStaff maybeShiftType =
    case (maybeStaff, maybeShiftType) of
        (Just staff, Just shiftType) ->
            let staffAssignment = StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId
                shiftAssignment = ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId
                referencesCurrent =
                    not (staffPayAssignmentRequiresRemediation activeAwardIds activeImportedPayItemIds staffAssignment)
                        && not (shiftPayAssignmentRequiresRemediation activeAwardIds activeImportedPayItemIds shiftAssignment)
                payValid = case resolvePayAssignment staffAssignment shiftAssignment of
                    InvalidPayAssignment {} -> False
                    _                       -> True
             in staff.venueId == unpackId venueId
                    && staff.isActive
                    && isNothing staff.archivedAt
                    && Set.member staffId eligibleStaffIds
                    && referencesCurrent
                    && payValid
        _ -> False

rosterTemplateNameAvailable ::
    (?modelContext :: ModelContext) =>
    Id RosterGroup ->
    Text ->
    IO Bool
rosterTemplateNameAvailable rosterGroupId name = do
    lockRosterTemplateName rosterGroupId name
    duplicateExists <-
        query @RosterTemplate
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhereCaseInsensitive (#name, name)
            |> fetchExists
    pure (not duplicateExists)

invalidTemplateName :: Text -> Bool
invalidTemplateName name = Text.null name || Text.length name > 120

unique :: Ord value => [value] -> Bool
unique values = Map.size (Map.fromList [(value, ()) | value <- values]) == length values

rosterTemplateContentRevision :: RosterTemplateContent -> Text
rosterTemplateContentRevision content =
    tshow (Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256)
  where
    payload = tshow
        ( sortOn (.inputDayIndex) content.contentDays
        , sortOn (\column -> (column.inputColumnSortOrder, column.inputColumnName)) content.contentColumns
        , sortOn shiftKey content.contentShifts
        )
    shiftKey shift =
        ( shift.inputShiftDayIndex
        , shift.inputShiftColumnSortOrder
        , shift.inputShiftRowIndex
        , shift.inputShiftStartMinute
        , shift.inputShiftEndMinute
        , tshow shift.inputShiftTypeId
        , tshow shift.inputShiftAssignment
        )

rosterTemplateSnapshotRevision :: RosterTemplateSnapshot -> Text
rosterTemplateSnapshotRevision = rosterTemplateContentRevision . snapshotContent

snapshotContent :: RosterTemplateSnapshot -> RosterTemplateContent
snapshotContent snapshot =
    let dayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- snapshot.snapshotDays]
        columnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- snapshot.snapshotColumns]
     in RosterTemplateContent
            { contentDays = [RosterTemplateDayInput day.dayIndex day.weekdayIndex day.isClosed day.rowCount | day <- snapshot.snapshotDays]
            , contentColumns = [RosterTemplateColumnInput column.name column.sortOrder | column <- snapshot.snapshotColumns]
            , contentShifts = mapMaybe (snapshotShiftInput dayIndexById columnSortById) snapshot.snapshotShifts
            }

snapshotShiftInput :: Map.Map UUID Int -> Map.Map UUID Int -> RosterTemplateShift -> Maybe RosterTemplateShiftInput
snapshotShiftInput dayIndexById columnSortById shift = do
    dayIndex <- Map.lookup shift.rosterTemplateDayId dayIndexById
    columnSort <- Map.lookup shift.rosterTemplateColumnId columnSortById
    assignment <- case (shift.assignmentState, shift.staffId) of
        ("staff", Just staffId) -> Just (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Just OpenAssignment
        _                       -> Nothing
    pure (RosterTemplateShiftInput dayIndex columnSort shift.rowIndex shift.startMinute shift.endMinute (Id shift.shiftTypeId) assignment)
