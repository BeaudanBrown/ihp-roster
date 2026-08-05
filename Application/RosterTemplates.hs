module Application.RosterTemplates
    ( RosterTemplateActor
    , RosterTemplateColumnInput (..)
    , RosterTemplateContent (..)
    , RosterTemplateDayInput (..)
    , RosterTemplateDraft (..)
    , RosterTemplateError (..)
    , RosterTemplateLibrary (..)
    , RosterTemplateSave (..)
    , RosterTemplateSaveWarning (..)
    , RosterTemplateSaved (..)
    , RosterTemplateShiftInput (..)
    , currentRosterTemplateActor
    , discardRosterTemplateDraft
    , fetchPrivateRosterTemplateDraft
    , fetchRosterTemplateLibrary
    , fetchSavedRosterTemplate
    , replaceRosterTemplateDraftContent
    , replaceRosterTemplateDraftWithContent
    , replaceRosterTemplateDraftWithContentInCurrentTransaction
    , rosterTemplateActor
    , rosterTemplateActorCanEditRosters
    , rosterTemplateActorUserId
    , rosterTemplateContentRevision
    , rosterTemplateDraftRevision
    , rosterTemplateActorVenueId
    , rosterTemplateContentIsValid
    , saveRosterTemplateDraft
    , reloadLatestRosterTemplateDraft
    , saveRosterTemplateDraftAsNew
    , softDeleteRosterTemplate
    , startBlankRosterTemplateDraft
    , startRosterTemplateDraftWithContent
    , startRosterTemplateDraftWithContentInCurrentTransaction
    , startRosterTemplateEditDraft
    , updateRosterTemplateDraftContent
    ) where

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
import Application.RosterTemplates.Mutations (lockRosterTemplateContentReferenceRows,
                                              lockRosterTemplateDraftDesign,
                                              lockRosterTemplateDraftSlot,
                                              lockRosterTemplateName,
                                              lockRosterTemplateVersion)
import Control.Monad (void)
import qualified "crypton" Crypto.Hash as Hash
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude

data RosterTemplateActor = RosterTemplateActor
    { actorUserId         :: !(Id User)
    , actorVenueId        :: !(Id Venue)
    , actorCanEditRosters :: !Bool
    }
    deriving (Eq, Show)

data RosterTemplateDayInput = RosterTemplateDayInput
    { inputDayIndex    :: !Int
    , inputDayIsClosed :: !Bool
    , inputDayRowCount :: !Int
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

data RosterTemplateSaved = RosterTemplateSaved
    { savedTemplate :: !RosterTemplate
    , savedDesign   :: !RosterTemplateDesign
    , savedDays     :: ![RosterTemplateDay]
    , savedColumns  :: ![RosterTemplateColumn]
    , savedShifts   :: ![RosterTemplateShift]
    }
    deriving (Eq, Show)

data RosterTemplateSaveWarning
    = RosterTemplateAssignmentConvertedToOpen !(Id RosterTemplateShift)
    deriving (Eq, Show)

data RosterTemplateSave = RosterTemplateSave
    { savedTemplate :: !RosterTemplate
    , savedVersion  :: !Int
    , saveWarnings  :: ![RosterTemplateSaveWarning]
    }
    deriving (Eq, Show)

data RosterTemplateLibrary = RosterTemplateLibrary
    { libraryTemplates    :: ![RosterTemplate]
    , libraryPrivateDraft :: !(Maybe RosterTemplateDraft)
    }
    deriving (Eq, Show)

data RosterTemplateDraft = RosterTemplateDraft
    { draftDesign  :: !RosterTemplateDesign
    , draftName    :: !Text
    , draftDays    :: ![RosterTemplateDay]
    , draftColumns :: ![RosterTemplateColumn]
    , draftShifts  :: ![RosterTemplateShift]
    }
    deriving (Eq, Show)

data RosterTemplateError
    = RosterTemplateForbidden
    | RosterTemplateDraftSlotOccupied
    | RosterTemplateInvalidName
    | RosterTemplateDuplicateName
    | RosterTemplateScopeMismatch
    | RosterTemplateInvalidContent !Text
    | RosterTemplateNotFound
    | RosterTemplateConflict !Int
    | RosterTemplateInvalidShiftTypes ![Id ShiftType]
    deriving (Eq, Show)

currentRosterTemplateActor ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO RosterTemplateActor
currentRosterTemplateActor = do
    venueReadOnly <- isCurrentVenueManuallyReadOnly
    pure (rosterTemplateActor authenticatedCurrentUser currentVenue (hasRole Manager && not venueReadOnly))

rosterTemplateActorCanEditRosters :: RosterTemplateActor -> Bool
rosterTemplateActorCanEditRosters = (.actorCanEditRosters)

rosterTemplateActorUserId :: RosterTemplateActor -> Id User
rosterTemplateActorUserId = (.actorUserId)

rosterTemplateActorVenueId :: RosterTemplateActor -> Id Venue
rosterTemplateActorVenueId = (.actorVenueId)

rosterTemplateActor :: User -> Venue -> Bool -> RosterTemplateActor
rosterTemplateActor user venue canEditRosters =
    RosterTemplateActor
        { actorUserId = user.id
        , actorVenueId = venue.id
        , actorCanEditRosters = canEditRosters
        }

startBlankRosterTemplateDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startBlankRosterTemplateDraft actor rosterGroup scale requestedName =
    withTransaction (startBlankRosterTemplateDraftInCurrentTransaction actor rosterGroup scale requestedName)

startBlankRosterTemplateDraftInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startBlankRosterTemplateDraftInCurrentTransaction actor rosterGroup scale requestedName
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | rosterGroup.venueId /= unpackId actor.actorVenueId = pure (Left RosterTemplateScopeMismatch)
    | Text.null normalizedName || Text.length normalizedName > 120 = pure (Left RosterTemplateInvalidName)
    | otherwise = do
        lockRosterTemplateDraftSlot actor.actorUserId
        existingDesign <- fetchDraftDesignForOwner actor.actorUserId
        case existingDesign of
            Just _ -> pure (Left RosterTemplateDraftSlotOccupied)
            Nothing -> do
                design <-
                    newRecord @RosterTemplateDesign
                        |> set #rosterGroupId (unpackId rosterGroup.id)
                        |> set #scale scale
                        |> set #draftOwnerUserId (Just (unpackId actor.actorUserId))
                        |> set #draftName (Just normalizedName)
                        |> set #createdByUserId (unpackId actor.actorUserId)
                        |> createRecord
                pure (Right (emptyDraft design normalizedName))
  where
    normalizedName = Text.strip requestedName

startRosterTemplateDraftWithContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startRosterTemplateDraftWithContent actor rosterGroup scale requestedName content =
    withTransaction (startRosterTemplateDraftWithContentInCurrentTransaction actor rosterGroup scale requestedName content)

startRosterTemplateDraftWithContentInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startRosterTemplateDraftWithContentInCurrentTransaction actor rosterGroup scale requestedName content
    | not (validTemplateContentForScale scale content) = pure (Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid."))
    | otherwise = do
        references <- validateContentInputReferences actor (unpackId rosterGroup.id) content
        case references of
            Left templateError -> pure (Left templateError)
            Right () -> do
                started <- startBlankRosterTemplateDraftInCurrentTransaction actor rosterGroup scale requestedName
                case started of
                    Left templateError -> pure (Left templateError)
                    Right draft -> do
                        persistRosterTemplateDraftContent draft.draftDesign content
                        reloaded <- loadDraft draft.draftDesign
                        pure (Right reloaded)

replaceRosterTemplateDraftWithContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    Maybe Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
replaceRosterTemplateDraftWithContent actor existingDesignId rosterGroup scale requestedName content expectedDraftRevision =
    withTransaction (replaceRosterTemplateDraftWithContentInCurrentTransaction actor existingDesignId rosterGroup scale requestedName content expectedDraftRevision)

replaceRosterTemplateDraftWithContentInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    RosterTemplateContent ->
    Maybe Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
replaceRosterTemplateDraftWithContentInCurrentTransaction actor existingDesignId rosterGroup scale requestedName content expectedDraftRevision
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | rosterGroup.venueId /= unpackId actor.actorVenueId = pure (Left RosterTemplateScopeMismatch)
    | Text.null normalizedName || Text.length normalizedName > 120 = pure (Left RosterTemplateInvalidName)
    | not (validTemplateContentForScale scale content) = pure (Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid."))
    | otherwise = do
        lockRosterTemplateDraftSlot actor.actorUserId
        designExists <- lockRosterTemplateDraftDesign existingDesignId
        maybeExisting <- if designExists then fetchOwnedDraft actor existingDesignId else pure Nothing
        case maybeExisting of
            Nothing -> pure (Left RosterTemplateForbidden)
            Just existing -> do
                currentDraft <- loadDraft existing
                if maybe False (/= rosterTemplateDraftRevision currentDraft) expectedDraftRevision
                    then pure (Left RosterTemplateDraftSlotOccupied)
                    else do
                        references <- validateContentInputReferences actor (unpackId rosterGroup.id) content
                        case references of
                            Left templateError -> pure (Left templateError)
                            Right () -> do
                                now <- getCurrentTime
                                replacement <-
                                    existing
                                        |> set #rosterGroupId (unpackId rosterGroup.id)
                                        |> set #scale scale
                                        |> set #draftName (Just normalizedName)
                                        |> set #sourceTemplateId Nothing
                                        |> set #baseVersionNumber Nothing
                                        |> set #updatedAt now
                                        |> updateRecord
                                persistRosterTemplateDraftContent replacement content
                                Right <$> loadDraft replacement
  where
    normalizedName = Text.strip requestedName

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
                |> orderByAsc #name
                |> fetch
        privateDraft <- fetchPrivateRosterTemplateDraft actor
        pure (Just (RosterTemplateLibrary templates privateDraft))

discardRosterTemplateDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Either RosterTemplateError ())
discardRosterTemplateDraft actor designId
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = do
        maybeDraft <- fetchOwnedDraft actor designId
        case maybeDraft of
            Nothing    -> pure (Left RosterTemplateForbidden)
            Just draft -> deleteRecord draft >> pure (Right ())

reloadLatestRosterTemplateDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Either RosterTemplateError RosterTemplateDraft)
reloadLatestRosterTemplateDraft actor designId = do
    maybeDraft <- fetchOwnedDraft actor designId
    case maybeDraft >>= (.sourceTemplateId) of
        Nothing -> pure (Left RosterTemplateNotFound)
        Just sourceTemplateId -> withTransaction do
            case maybeDraft of
                Nothing -> pure (Left RosterTemplateNotFound)
                Just draft -> do
                    deleteRecord draft
                    startRosterTemplateEditDraftInCurrentTransaction actor (Id sourceTemplateId)

softDeleteRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplate actor templateId reason
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = do
        maybeSaved <- fetchSavedRosterTemplate actor templateId
        case maybeSaved of
            Nothing -> pure (Left RosterTemplateNotFound)
            Just saved -> do
                now <- getCurrentTime
                saved.savedTemplate
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId actor.actorUserId))
                    |> set #deleteReason (Just (Text.take 500 (Text.strip reason)))
                    |> updateRecord
                    |> void
                pure (Right ())

startRosterTemplateEditDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startRosterTemplateEditDraft actor templateId =
    withTransaction (startRosterTemplateEditDraftInCurrentTransaction actor templateId)

startRosterTemplateEditDraftInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startRosterTemplateEditDraftInCurrentTransaction actor templateId
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = do
        lockRosterTemplateDraftSlot actor.actorUserId
        existingDesign <- fetchDraftDesignForOwner actor.actorUserId
        case existingDesign of
            Just _ -> pure (Left RosterTemplateDraftSlotOccupied)
            Nothing -> do
                maybeSaved <- fetchSavedRosterTemplate actor templateId
                case maybeSaved of
                    Nothing -> pure (Left RosterTemplateNotFound)
                    Just saved -> do
                        let template = saved.savedTemplate
                        let content = savedContentInput saved
                        references <- validateContentInputReferences actor template.rosterGroupId content
                        case references of
                            Left problem -> pure (Left problem)
                            Right () -> do
                                design <-
                                    newRecord @RosterTemplateDesign
                                        |> set #rosterGroupId template.rosterGroupId
                                        |> set #scale template.scale
                                        |> set #draftOwnerUserId (Just (unpackId actor.actorUserId))
                                        |> set #draftName (Just template.name)
                                        |> set #sourceTemplateId (Just (unpackId template.id))
                                        |> set #baseVersionNumber (Just template.currentVersion)
                                        |> set #createdByUserId (unpackId actor.actorUserId)
                                        |> createRecord
                                unless (null content.contentDays && null content.contentColumns && null content.contentShifts) do
                                    persistRosterTemplateDraftContent design content
                                Right <$> loadDraft design

saveRosterTemplateDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraft actor designId = saveDraft actor designId Nothing

saveRosterTemplateDraftAsNew ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraftAsNew actor designId name = saveDraft actor designId (Just (Text.strip name))

saveDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    Maybe Text ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveDraft actor designId saveAsName
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | maybe False invalidName saveAsName = pure (Left RosterTemplateInvalidName)
    | otherwise = do
        maybeDraft <- fetchOwnedDraft actor designId
        case maybeDraft of
            Nothing -> pure (Left RosterTemplateForbidden)
            Just draft -> withTransaction do
                referenceValidation <- validateDraftReferences actor draft
                case referenceValidation of
                    Left problem -> pure (Left problem)
                    Right warnings -> commitDraft actor draft saveAsName warnings
  where
    invalidName name = Text.null name || Text.length name > 120

commitDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    Maybe Text ->
    [RosterTemplateSaveWarning] ->
    IO (Either RosterTemplateError RosterTemplateSave)
commitDraft actor draft saveAsName warnings =
    case (saveAsName, draft.sourceTemplateId, draft.baseVersionNumber) of
        (Just newName, _, _) -> saveDraftAsNewTemplate actor draft newName warnings
        (Nothing, Nothing, Nothing) -> saveDraftAsNewTemplate actor draft (fromMaybe "" draft.draftName) warnings
        (Nothing, Just sourceTemplateUuid, Just baseVersion) -> do
            maybeTemplate <- query @RosterTemplate |> filterWhere (#id, Id sourceTemplateUuid) |> filterWhere (#deletedAt, Nothing) |> fetchOneOrNothing
            case maybeTemplate of
                Nothing -> pure (Left RosterTemplateNotFound)
                Just template -> do
                    currentVersion <- lockRosterTemplateVersion template.id
                    if currentVersion /= baseVersion
                        then pure (Left (RosterTemplateConflict currentVersion))
                        else do
                            let nextVersion = currentVersion + 1
                            let savedName = fromMaybe template.name draft.draftName
                            nameAvailable <- rosterTemplateNameAvailable draft.rosterGroupId savedName (Just template.id)
                            if not nameAvailable
                                then pure (Left RosterTemplateDuplicateName)
                                else do
                                    applySaveWarnings warnings
                                    persistSavedDesign draft template nextVersion
                                    updatedTemplate <-
                                        template
                                            |> set #name savedName
                                            |> set #currentVersion nextVersion
                                            |> updateRecord
                                    pure (Right (RosterTemplateSave updatedTemplate nextVersion warnings))
        _ -> pure (Left (RosterTemplateInvalidContent "Draft source version is incomplete."))

saveDraftAsNewTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    Text ->
    [RosterTemplateSaveWarning] ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveDraftAsNewTemplate _actor draft name warnings = do
    nameAvailable <- rosterTemplateNameAvailable draft.rosterGroupId name Nothing
    if not nameAvailable
        then pure (Left RosterTemplateDuplicateName)
        else do
            template <-
                newRecord @RosterTemplate
                    |> set #rosterGroupId draft.rosterGroupId
                    |> set #name name
                    |> set #scale draft.scale
                    |> createRecord
            applySaveWarnings warnings
            persistSavedDesign draft template 1
            updatedTemplate <- template |> set #currentVersion 1 |> updateRecord
            pure (Right (RosterTemplateSave updatedTemplate 1 warnings))

rosterTemplateNameAvailable ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    Maybe (Id RosterTemplate) ->
    IO Bool
rosterTemplateNameAvailable rosterGroupId name excludedTemplateId = do
    lockRosterTemplateName (Id rosterGroupId) name
    let matchingNames =
            query @RosterTemplate
                |> filterWhere (#rosterGroupId, rosterGroupId)
                |> filterWhereCaseInsensitive (#name, name)
    duplicateExists <- case excludedTemplateId of
        Nothing -> matchingNames |> fetchExists
        Just templateId -> matchingNames |> filterWhereNot (#id, templateId) |> fetchExists
    pure (not duplicateExists)

validateDraftReferences ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    IO (Either RosterTemplateError [RosterTemplateSaveWarning])
validateDraftReferences actor draft = do
    shifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateDesignId, unpackId draft.id) |> fetch
    let shiftTypeIds = nub (map (.shiftTypeId) shifts)
    shiftTypes <-
        if null shiftTypeIds
            then pure []
            else query @ShiftType |> filterWhereIn (#id, map Id shiftTypeIds) |> fetch
    let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
    let invalidShiftTypeIds =
            [ Id shiftTypeId
            | shiftTypeId <- shiftTypeIds
            , case Map.lookup shiftTypeId shiftTypeById of
                Nothing -> True
                Just shiftType -> shiftType.venueId /= unpackId actor.actorVenueId || not shiftType.isActive || isJust shiftType.archivedAt
            ]
    if not (null invalidShiftTypeIds)
        then pure (Left (RosterTemplateInvalidShiftTypes invalidShiftTypeIds))
        else do
            invalidStaffShiftIds <- invalidStaffAssignments actor draft shifts shiftTypeById
            pure (Right (map RosterTemplateAssignmentConvertedToOpen invalidStaffShiftIds))

invalidStaffAssignments ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    [RosterTemplateShift] ->
    Map.Map UUID ShiftType ->
    IO [Id RosterTemplateShift]
invalidStaffAssignments actor draft shifts shiftTypeById = do
    let staffIds = nub (mapMaybe (.staffId) shifts)
    staffMembers <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, map Id staffIds) |> fetch
    assignments <-
        if null staffIds
            then pure []
            else query @StaffRosterGroup
                |> filterWhereIn (#staffId, staffIds)
                |> filterWhere (#rosterGroupId, draft.rosterGroupId)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
    activeImportedPayItems <-
        query @XeroImportedPayItem
            |> filterWhere (#venueId, unpackId actor.actorVenueId)
            |> filterWhere (#archivedAt, Nothing)
            |> filterWhere (#providerAvailable, True)
            |> fetch
    let staffById = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
    let eligibleStaffIds = Set.fromList (map (.staffId) assignments)
    let activeAwardIds = map (.id) activeAwardLevels
    let activeImportedPayItemIds = map (.id) activeImportedPayItems
    pure
        [ shift.id
        | shift <- shifts
        , Just staffId <- [shift.staffId]
        , let maybeStaff = Map.lookup staffId staffById
        , let maybeShiftType = Map.lookup shift.shiftTypeId shiftTypeById
        , not (validStaffAssignment activeAwardIds activeImportedPayItemIds eligibleStaffIds actor.actorVenueId staffId maybeStaff maybeShiftType)
        ]

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

applySaveWarnings :: (?modelContext :: ModelContext) => [RosterTemplateSaveWarning] -> IO ()
applySaveWarnings warnings =
    forM_ warnings \case
        RosterTemplateAssignmentConvertedToOpen shiftId -> do
            shift <- fetch shiftId
            shift
                |> set #assignmentState "open"
                |> set #staffId Nothing
                |> updateRecord
                |> void

persistSavedDesign ::
    (?modelContext :: ModelContext) =>
    RosterTemplateDesign ->
    RosterTemplate ->
    Int ->
    IO ()
persistSavedDesign draft template versionNumber =
    draft
        |> set #draftOwnerUserId Nothing
        |> set #draftName Nothing
        |> set #templateId (Just (unpackId template.id))
        |> set #versionNumber (Just versionNumber)
        |> set #sourceTemplateId Nothing
        |> set #baseVersionNumber Nothing
        |> updateRecord
        |> void

fetchOwnedDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Maybe RosterTemplateDesign)
fetchOwnedDraft actor designId = do
    maybeDesign <-
        query @RosterTemplateDesign
            |> filterWhere (#id, designId)
            |> filterWhere (#draftOwnerUserId, Just (unpackId actor.actorUserId))
            |> fetchOneOrNothing
    case maybeDesign of
        Nothing -> pure Nothing
        Just design -> do
            allowed <- designMatchesActorVenue actor design
            pure (if allowed then Just design else Nothing)

fetchSavedRosterTemplate ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    IO (Maybe RosterTemplateSaved)
fetchSavedRosterTemplate actor templateId
    | not actor.actorCanEditRosters = pure Nothing
    | otherwise = do
        maybeTemplate <- query @RosterTemplate |> filterWhere (#id, templateId) |> filterWhere (#deletedAt, Nothing) |> fetchOneOrNothing
        case maybeTemplate of
            Nothing -> pure Nothing
            Just template -> do
                maybeGroup <- query @RosterGroup |> filterWhere (#id, Id template.rosterGroupId) |> filterWhere (#venueId, unpackId actor.actorVenueId) |> fetchOneOrNothing
                case maybeGroup of
                    Nothing -> pure Nothing
                    Just _ -> do
                        maybeDesign <-
                            query @RosterTemplateDesign
                                |> filterWhere (#templateId, Just (unpackId template.id))
                                |> filterWhere (#versionNumber, Just template.currentVersion)
                                |> fetchOneOrNothing
                        forM maybeDesign (loadSaved template)

loadSaved :: (?modelContext :: ModelContext) => RosterTemplate -> RosterTemplateDesign -> IO RosterTemplateSaved
loadSaved template design = do
    days <- query @RosterTemplateDay |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #dayIndex |> fetch
    columns <- query @RosterTemplateColumn |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #sortOrder |> fetch
    shifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #rowIndex |> fetch
    pure (RosterTemplateSaved template design days columns shifts)

savedContentInput :: RosterTemplateSaved -> RosterTemplateContent
savedContentInput saved =
    let dayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- saved.savedDays]
        columnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- saved.savedColumns]
     in RosterTemplateContent
            { contentDays = [RosterTemplateDayInput day.dayIndex day.isClosed day.rowCount | day <- saved.savedDays]
            , contentColumns = [RosterTemplateColumnInput column.name column.sortOrder | column <- saved.savedColumns]
            , contentShifts = mapMaybe (savedShiftInput dayIndexById columnSortById) saved.savedShifts
            }

draftContentInput :: RosterTemplateDraft -> RosterTemplateContent
draftContentInput draft =
    let dayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- draft.draftDays]
        columnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- draft.draftColumns]
     in RosterTemplateContent
            { contentDays = [RosterTemplateDayInput day.dayIndex day.isClosed day.rowCount | day <- draft.draftDays]
            , contentColumns = [RosterTemplateColumnInput column.name column.sortOrder | column <- draft.draftColumns]
            , contentShifts = mapMaybe (savedShiftInput dayIndexById columnSortById) draft.draftShifts
            }

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

rosterTemplateDraftRevision :: RosterTemplateDraft -> Text
rosterTemplateDraftRevision draft =
    tshow (Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256)
  where
    design = draft.draftDesign
    payload = tshow
        ( design.id
        , design.rosterGroupId
        , design.scale
        , design.draftName
        , design.sourceTemplateId
        , design.baseVersionNumber
        , rosterTemplateContentRevision (draftContentInput draft)
        )

savedShiftInput :: Map.Map UUID Int -> Map.Map UUID Int -> RosterTemplateShift -> Maybe RosterTemplateShiftInput
savedShiftInput dayIndexById columnSortById shift = do
    dayIndex <- Map.lookup shift.rosterTemplateDayId dayIndexById
    columnSort <- Map.lookup shift.rosterTemplateColumnId columnSortById
    assignment <- case (shift.assignmentState, shift.staffId) of
        ("staff", Just staffId) -> Just (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Just OpenAssignment
        _                       -> Nothing
    pure (RosterTemplateShiftInput dayIndex columnSort shift.rowIndex shift.startMinute shift.endMinute (Id shift.shiftTypeId) assignment)

replaceRosterTemplateDraftContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError ())
replaceRosterTemplateDraftContent actor designId content =
    updateRosterTemplateDraftContent actor designId (const (Right content))

updateRosterTemplateDraftContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    (RosterTemplateContent -> Either RosterTemplateError RosterTemplateContent) ->
    IO (Either RosterTemplateError ())
updateRosterTemplateDraftContent actor designId transform
    | not actor.actorCanEditRosters = pure (Left RosterTemplateForbidden)
    | otherwise = withTransaction do
        designExists <- lockRosterTemplateDraftDesign designId
        maybeDesign <- if designExists then fetchOwnedDraft actor designId else pure Nothing
        case maybeDesign of
            Nothing -> pure (Left RosterTemplateForbidden)
            Just design -> do
                currentDraft <- loadDraft design
                case transform (draftContentInput currentDraft) of
                    Left templateError -> pure (Left templateError)
                    Right content
                        | not (validTemplateContent design content) -> pure (Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid."))
                        | otherwise -> do
                            references <- validateContentInputReferences actor design.rosterGroupId content
                            case references of
                                Left templateError -> pure (Left templateError)
                                Right () -> persistRosterTemplateDraftContent design content >> pure (Right ())

validateContentInputReferences ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    UUID ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError ())
validateContentInputReferences actor rosterGroupId content = do
    let shiftTypeIds = nub (map (.inputShiftTypeId) content.contentShifts)
    let staffIds = nub [staffId | shift <- content.contentShifts, StaffAssignment staffId <- [shift.inputShiftAssignment]]
    lockRosterTemplateContentReferenceRows (Id rosterGroupId) shiftTypeIds staffIds
    shiftTypes <- if null shiftTypeIds
        then pure []
        else query @ShiftType |> filterWhereIn (#id, shiftTypeIds) |> fetch
    let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
    let invalidShiftTypeIds =
            [ shiftTypeId
            | shiftTypeId <- shiftTypeIds
            , case Map.lookup (unpackId shiftTypeId) shiftTypeById of
                Nothing -> True
                Just shiftType -> shiftType.venueId /= unpackId actor.actorVenueId || not shiftType.isActive || isJust shiftType.archivedAt
            ]
    if not (null invalidShiftTypeIds)
        then pure (Left (RosterTemplateInvalidShiftTypes invalidShiftTypeIds))
        else do
            staffMembers <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, staffIds) |> fetch
            assignments <- if null staffIds
                then pure []
                else query @StaffRosterGroup
                    |> filterWhereIn (#staffId, map unpackId staffIds)
                    |> filterWhere (#rosterGroupId, rosterGroupId)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
            activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
            activeImportedPayItems <- query @XeroImportedPayItem
                |> filterWhere (#venueId, unpackId actor.actorVenueId)
                |> filterWhere (#archivedAt, Nothing)
                |> filterWhere (#providerAvailable, True)
                |> fetch
            let staffById = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
            let eligibleStaffIds = Set.fromList (map (.staffId) assignments)
            let activeAwardIds = map (.id) activeAwardLevels
            let activeImportedPayItemIds = map (.id) activeImportedPayItems
            let invalidStaffExists = any (not . validInputAssignment activeAwardIds activeImportedPayItemIds eligibleStaffIds staffById shiftTypeById) content.contentShifts
            pure if invalidStaffExists
                then Left (RosterTemplateInvalidContent "Choose an available roster-group staff member with valid pay configuration.")
                else Right ()
  where
    validInputAssignment _ _ _ _ _ RosterTemplateShiftInput { inputShiftAssignment = OpenAssignment } = True
    validInputAssignment activeAwardIds activeImportedPayItemIds eligibleStaffIds staffById shiftTypeById shift =
        case shift.inputShiftAssignment of
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

persistRosterTemplateDraftContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateDesign ->
    RosterTemplateContent ->
    IO ()
persistRosterTemplateDraftContent design content = do
    oldShifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> fetch
    oldDays <- query @RosterTemplateDay |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> fetch
    oldColumns <- query @RosterTemplateColumn |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> fetch
    deleteRecords oldShifts
    deleteRecords oldDays
    deleteRecords oldColumns
    days <- forM content.contentDays (createTemplateDay design)
    columns <- forM content.contentColumns (createTemplateColumn design)
    let daysByIndex = Map.fromList [(day.dayIndex, day) | day <- days]
    let columnsBySortOrder = Map.fromList [(column.sortOrder, column) | column <- columns]
    forM_ content.contentShifts (createTemplateShift design daysByIndex columnsBySortOrder)

rosterTemplateContentIsValid :: RosterTemplateScaleEnum -> RosterTemplateContent -> Bool
rosterTemplateContentIsValid = validTemplateContentForScale

validTemplateContent :: RosterTemplateDesign -> RosterTemplateContent -> Bool
validTemplateContent design = validTemplateContentForScale design.scale

validTemplateContentForScale :: RosterTemplateScaleEnum -> RosterTemplateContent -> Bool
validTemplateContentForScale scale content =
    not (null content.contentDays)
        && not (null content.contentColumns)
        && all validDay content.contentDays
        && all validColumn content.contentColumns
        && unique (map (.inputDayIndex) content.contentDays)
        && unique (map (.inputColumnSortOrder) content.contentColumns)
        && unique [(shift.inputShiftDayIndex, shift.inputShiftColumnSortOrder, shift.inputShiftRowIndex) | shift <- content.contentShifts]
        && all validShift content.contentShifts
  where
    dayIndexes = map (.inputDayIndex) content.contentDays
    daysByIndex = Map.fromList [(day.inputDayIndex, day) | day <- content.contentDays]
    columnSortOrders = map (.inputColumnSortOrder) content.contentColumns
    validDay day = day.inputDayIndex >= 0 && day.inputDayIndex <= 6 && day.inputDayRowCount >= 0 && (scale == Week || day.inputDayIndex == 0)
    validColumn column =
        let name = Text.strip column.inputColumnName
         in not (Text.null name) && Text.length name <= 120 && column.inputColumnSortOrder >= 0
    validShift shift =
        case Map.lookup shift.inputShiftDayIndex daysByIndex of
            Nothing -> False
            Just day ->
                shift.inputShiftColumnSortOrder `elem` columnSortOrders
                    && shift.inputShiftRowIndex >= 0
                    && shift.inputShiftRowIndex < day.inputDayRowCount
                    && shift.inputShiftStartMinute >= 0
                    && shift.inputShiftEndMinute > shift.inputShiftStartMinute
                    && shift.inputShiftEndMinute <= 2880

unique :: Ord value => [value] -> Bool
unique values = Map.size (Map.fromList [(value, ()) | value <- values]) == length values

createTemplateDay :: (?modelContext :: ModelContext) => RosterTemplateDesign -> RosterTemplateDayInput -> IO RosterTemplateDay
createTemplateDay design input =
    newRecord @RosterTemplateDay
        |> set #rosterTemplateDesignId (unpackId design.id)
        |> set #dayIndex input.inputDayIndex
        |> set #isClosed input.inputDayIsClosed
        |> set #rowCount input.inputDayRowCount
        |> createRecord

createTemplateColumn :: (?modelContext :: ModelContext) => RosterTemplateDesign -> RosterTemplateColumnInput -> IO RosterTemplateColumn
createTemplateColumn design input =
    newRecord @RosterTemplateColumn
        |> set #rosterTemplateDesignId (unpackId design.id)
        |> set #name (Text.strip input.inputColumnName)
        |> set #sortOrder input.inputColumnSortOrder
        |> createRecord

createTemplateShift ::
    (?modelContext :: ModelContext) =>
    RosterTemplateDesign ->
    Map.Map Int RosterTemplateDay ->
    Map.Map Int RosterTemplateColumn ->
    RosterTemplateShiftInput ->
    IO RosterTemplateShift
createTemplateShift design daysByIndex columnsBySortOrder input = do
    let day = fromMaybe (error "validated template day missing") (Map.lookup input.inputShiftDayIndex daysByIndex)
    let column = fromMaybe (error "validated template column missing") (Map.lookup input.inputShiftColumnSortOrder columnsBySortOrder)
    let (assignmentState, staffId) = case input.inputShiftAssignment of
            StaffAssignment assignedStaffId -> ("staff", Just (unpackId assignedStaffId))
            OpenAssignment -> ("open", Nothing)
    newRecord @RosterTemplateShift
        |> set #rosterTemplateDesignId (unpackId design.id)
        |> set #rosterTemplateDayId (unpackId day.id)
        |> set #rosterTemplateColumnId (unpackId column.id)
        |> set #assignmentState assignmentState
        |> set #staffId staffId
        |> set #rowIndex input.inputShiftRowIndex
        |> set #startMinute input.inputShiftStartMinute
        |> set #endMinute input.inputShiftEndMinute
        |> set #shiftTypeId (unpackId input.inputShiftTypeId)
        |> createRecord

fetchPrivateRosterTemplateDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    IO (Maybe RosterTemplateDraft)
fetchPrivateRosterTemplateDraft actor
    | not actor.actorCanEditRosters = pure Nothing
    | otherwise = do
        maybeDesign <- fetchDraftDesignForOwner actor.actorUserId
        scopedDesign <- case maybeDesign of
            Nothing -> pure Nothing
            Just design -> do
                allowed <- designMatchesActorVenue actor design
                pure (if allowed then Just design else Nothing)
        forM scopedDesign loadDraft

fetchDraftDesignForOwner ::
    (?modelContext :: ModelContext) =>
    Id User ->
    IO (Maybe RosterTemplateDesign)
fetchDraftDesignForOwner userId =
    query @RosterTemplateDesign
        |> filterWhere (#draftOwnerUserId, Just (unpackId userId))
        |> fetchOneOrNothing

designMatchesActorVenue ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    IO Bool
designMatchesActorVenue actor design =
    query @RosterGroup
        |> filterWhere (#id, Id design.rosterGroupId)
        |> filterWhere (#venueId, unpackId actor.actorVenueId)
        |> fetchExists

loadDraft :: (?modelContext :: ModelContext) => RosterTemplateDesign -> IO RosterTemplateDraft
loadDraft design = do
    days <- query @RosterTemplateDay |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #dayIndex |> fetch
    columns <- query @RosterTemplateColumn |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #sortOrder |> fetch
    shifts <- query @RosterTemplateShift |> filterWhere (#rosterTemplateDesignId, unpackId design.id) |> orderByAsc #rowIndex |> fetch
    pure
        RosterTemplateDraft
            { draftDesign = design
            , draftName = fromMaybe "" design.draftName
            , draftDays = days
            , draftColumns = columns
            , draftShifts = shifts
            }

emptyDraft :: RosterTemplateDesign -> Text -> RosterTemplateDraft
emptyDraft design name =
    RosterTemplateDraft
        { draftDesign = design
        , draftName = name
        , draftDays = []
        , draftColumns = []
        , draftShifts = []
        }
