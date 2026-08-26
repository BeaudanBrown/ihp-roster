{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateCapture
    ( RosterTemplateCaptureAssignmentMode (..)
    , RosterTemplateCaptureError (..)
    , RosterTemplateCapturePreview (..)
    , RosterTemplateCaptureRequest (..)
    , RosterTemplateCaptureShiftTypeRequirement (..)
    , RosterTemplateCaptureStaffIssue (..)
    , RosterTemplateCaptureWarning (..)
    , confirmRosterTemplateCapture
    , confirmRosterTemplateCaptureMutation
    , previewRosterTemplateCapture
    ) where

import Application.Helper.FrontendContract.Surface.Roster (RosterTemplateCaptureAssignmentMode (..))
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterTemplateLibraryResource)
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.PayAssignment (EffectivePayAssignment (..),
                                  ShiftPayAssignment (..),
                                  StaffPayAssignment (..), resolvePayAssignment,
                                  shiftPayAssignmentRequiresRemediation,
                                  staffPayAssignmentRequiresRemediation)
import Application.RosterPublication.Mutations (withRosterWindowDateLockInCurrentTransaction)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          rosterShiftAssignment)
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateCaptureGroup,
                                              lockRosterTemplateCaptureRows,
                                              lockRosterTemplateContentReferenceRows)
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Control.Monad (guard)
import qualified "crypton" Crypto.Hash as Hash
import Data.List (nubBy, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Data.UUID (UUID)
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude
import Web.RosterWeeks.DateRange
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

data RosterTemplateCaptureStaffIssue
    = CaptureStaffUnavailable
    | CaptureStaffOutsideGroup
    | CaptureStaffPayInvalid
    deriving (Eq, Ord, Show)

data RosterTemplateCaptureWarning = RosterTemplateCaptureWarning
    { captureWarningStaffId   :: !(Id Staff)
    , captureWarningStaffName :: !Text
    , captureWarningIssue     :: !RosterTemplateCaptureStaffIssue
    , captureWarningCount     :: !Int
    }
    deriving (Eq, Show)

data RosterTemplateCaptureShiftTypeRequirement = RosterTemplateCaptureShiftTypeRequirement
    { captureStaleShiftTypeId   :: !(Id ShiftType)
    , captureStaleShiftTypeName :: !Text
    , captureStaleShiftCount    :: !Int
    , captureMappedShiftTypeId  :: !(Maybe (Id ShiftType))
    }
    deriving (Eq, Show)

data RosterTemplateCaptureRequest = RosterTemplateCaptureRequest
    { captureSourceScope       :: !RosterWindowScope
    , captureRequestedName     :: !Text
    , captureAssignmentMode    :: !RosterTemplateCaptureAssignmentMode
    , captureShiftTypeMappings :: !(Map.Map (Id ShiftType) (Id ShiftType))
    }
    deriving (Eq, Show)

data RosterTemplateCapturePreview = RosterTemplateCapturePreview
    { capturePreviewName                 :: !Text
    , capturePreviewAssignmentMode       :: !RosterTemplateCaptureAssignmentMode
    , capturePreviewSourceRevision       :: !Text
    , capturePreviewCalendarRevision     :: !Int
    , capturePreviewWarnings             :: ![RosterTemplateCaptureWarning]
    , capturePreviewShiftTypeRequirements :: ![RosterTemplateCaptureShiftTypeRequirement]
    , capturePreviewAvailableShiftTypes  :: ![ShiftType]
    , capturePreviewContent              :: !(Maybe RosterTemplateContent)
    , capturePreviewReferencedShiftTypes :: ![Id ShiftType]
    , capturePreviewReferencedStaff      :: ![Id Staff]
    }
    deriving (Eq, Show)

data RosterTemplateCaptureError
    = RosterTemplateCaptureForbidden
    | RosterTemplateCaptureSourceNotFound
    | RosterTemplateCaptureScopeMismatch
    | RosterTemplateCaptureCalendarConflict
    | RosterTemplateCaptureInvalidName
    | RosterTemplateCaptureDuplicateName
    | RosterTemplateCaptureInvalidStructure !Text
    | RosterTemplateCaptureInvalidShiftTypeMappings ![Id ShiftType]
    | RosterTemplateCaptureShiftTypeMappingsRequired ![Id ShiftType]
    | RosterTemplateCaptureConfirmationRequired
    | RosterTemplateCaptureSourceConflict
    | RosterTemplateCapturePersistenceError !RosterTemplateError
    deriving (Eq, Show)

previewRosterTemplateCapture ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateCaptureRequest ->
    IO (Either RosterTemplateCaptureError RosterTemplateCapturePreview)
previewRosterTemplateCapture actor request
    | not (rosterTemplateActorCanEditRosters actor) = pure (Left RosterTemplateCaptureForbidden)
    | Text.null normalizedName || Text.length normalizedName > 120 = pure (Left RosterTemplateCaptureInvalidName)
    | scope.rosterWindowVenueId /= rosterTemplateActorVenueId actor = pure (Left RosterTemplateCaptureScopeMismatch)
    | scope.rosterWindowEnd /= addDays 7 scope.rosterWindowStart = pure (Left (RosterTemplateCaptureInvalidStructure "Choose a complete seven-day roster window."))
    | otherwise = do
        maybeGroup <- query @RosterGroup
            |> filterWhere (#id, scope.rosterWindowRosterGroupId)
            |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
        venueConfig <- query @VenueConfig
            |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
            |> fetchOne
        case maybeGroup of
            Nothing -> pure (Left RosterTemplateCaptureSourceNotFound)
            Just rosterGroup
                | not (rosterWindowScopeMatchesConfig venueConfig scope) -> pure (Left RosterTemplateCaptureCalendarConflict)
                | otherwise -> prepareCapture actor rosterGroup venueConfig request normalizedName
  where
    scope = request.captureSourceScope
    normalizedName = Text.strip request.captureRequestedName

confirmRosterTemplateCapture ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateCaptureRequest ->
    Text ->
    Int ->
    Bool ->
    IO (Either RosterTemplateCaptureError RosterTemplateSnapshot)
confirmRosterTemplateCapture actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed =
    withTransaction (confirmRosterTemplateCaptureInCurrentTransaction actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed)

confirmRosterTemplateCaptureMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    RosterTemplateCaptureRequest ->
    Text ->
    Int ->
    Bool ->
    IO (Either RosterTemplateCaptureError (LiveMutationResult RosterTemplateSnapshot))
confirmRosterTemplateCaptureMutation actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed =
    withDurableLiveMutationOutcome publicationFor do
        result <- confirmRosterTemplateCaptureInCurrentTransaction actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed
        pure (fmap withResources result)
  where
    withResources snapshot =
        liveMutationResult snapshot
            [rosterTemplateLibraryResource snapshot.snapshotTemplate.rosterGroupId]
    publicationFor = either (const Nothing) (\result -> Just ("roster.template.capture", result.liveMutationTouchedResources))

confirmRosterTemplateCaptureInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateCaptureRequest ->
    Text ->
    Int ->
    Bool ->
    IO (Either RosterTemplateCaptureError RosterTemplateSnapshot)
confirmRosterTemplateCaptureInCurrentTransaction actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed =
    withRosterWindowDateLockInCurrentTransaction
        scope.rosterWindowVenueId
        scope.rosterWindowRosterGroupId
        scope.rosterWindowStart
        scope.rosterWindowEnd do
            groupExists <- lockRosterTemplateCaptureGroup scope.rosterWindowRosterGroupId
            if not groupExists
                then pure (Left RosterTemplateCaptureSourceNotFound)
                else confirmLockedRosterTemplateCapture actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed
  where
    scope = request.captureSourceScope

confirmLockedRosterTemplateCapture ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateCaptureRequest ->
    Text ->
    Int ->
    Bool ->
    IO (Either RosterTemplateCaptureError RosterTemplateSnapshot)
confirmLockedRosterTemplateCapture actor request expectedSourceRevision expectedCalendarRevision warningsConfirmed = do
    lockRosterTemplateCaptureRows
        scope.rosterWindowVenueId
        scope.rosterWindowRosterGroupId
        scope.rosterWindowStart
        scope.rosterWindowEnd
    initial <- previewRosterTemplateCapture actor request
    case initial of
        Left failure -> pure (Left failure)
        Right initialPreview -> do
            lockRosterTemplateContentReferenceRows
                scope.rosterWindowRosterGroupId
                initialPreview.capturePreviewReferencedShiftTypes
                initialPreview.capturePreviewReferencedStaff
            prepared <- previewRosterTemplateCapture actor request
            case prepared of
                Left failure -> pure (Left failure)
                Right preview
                    | preview.capturePreviewCalendarRevision /= expectedCalendarRevision -> pure (Left RosterTemplateCaptureCalendarConflict)
                    | preview.capturePreviewSourceRevision /= expectedSourceRevision -> pure (Left RosterTemplateCaptureSourceConflict)
                    | not (null missingMappingIds) -> pure (Left (RosterTemplateCaptureShiftTypeMappingsRequired missingMappingIds))
                    | not (null preview.capturePreviewWarnings) && not warningsConfirmed -> pure (Left RosterTemplateCaptureConfirmationRequired)
                    | otherwise -> case preview.capturePreviewContent of
                        Nothing -> pure (Left (RosterTemplateCaptureShiftTypeMappingsRequired missingMappingIds))
                        Just content -> do
                            rosterGroup <- query @RosterGroup
                                |> filterWhere (#id, scope.rosterWindowRosterGroupId)
                                |> filterWhere (#venueId, unpackId scope.rosterWindowVenueId)
                                |> filterWhere (#isActive, True)
                                |> filterWhere (#archivedAt, Nothing)
                                |> fetchOne
                            created <- createRosterTemplateInCurrentTransaction actor rosterGroup Week preview.capturePreviewName content
                            pure (either (Left . RosterTemplateCapturePersistenceError) Right created)
                  where
                    missingMappingIds =
                        [ requirement.captureStaleShiftTypeId
                        | requirement <- preview.capturePreviewShiftTypeRequirements
                        , isNothing requirement.captureMappedShiftTypeId
                        ]
  where
    scope = request.captureSourceScope

prepareCapture ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    VenueConfig ->
    RosterTemplateCaptureRequest ->
    Text ->
    IO (Either RosterTemplateCaptureError RosterTemplateCapturePreview)
prepareCapture actor rosterGroup venueConfig request normalizedName = do
    duplicate <- query @RosterTemplate
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereCaseInsensitive (#name, normalizedName)
        |> fetchExists
    if duplicate
        then pure (Left RosterTemplateCaptureDuplicateName)
        else do
            let scope = request.captureSourceScope
            days <- query @RosterDay
                |> filterWhere (#venueId, unpackId scope.rosterWindowVenueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, scope.rosterWindowStart)
                |> filterWhereLessThan (#operationalDate, scope.rosterWindowEnd)
                |> orderByAsc #operationalDate
                |> fetch
            if map (.operationalDate) days /= map (`addDays` scope.rosterWindowStart) [0 .. 6]
                then pure (Left (RosterTemplateCaptureInvalidStructure "The viewed roster window must contain all seven operational days."))
                else do
                    window <- fetchRosterWindow scope.rosterWindowVenueId rosterGroup.id scope.rosterWindowStart
                    activeLanes <- query @RosterLane
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                    slots <- query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #id
                        |> fetch
                    prepareCaptureFacts actor rosterGroup venueConfig request normalizedName days window activeLanes slots

prepareCaptureFacts ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    VenueConfig ->
    RosterTemplateCaptureRequest ->
    Text ->
    [RosterDay] ->
    RosterWindow ->
    [RosterLane] ->
    [RosterSlot] ->
    IO (Either RosterTemplateCaptureError RosterTemplateCapturePreview)
prepareCaptureFacts actor rosterGroup venueConfig request normalizedName days window activeLanes slots = do
    let columns = zipWith (\sortOrder lane -> RosterTemplateColumnInput lane.rosterWindowLaneName sortOrder) [0 ..] window.rosterWindowLanes
        activeLaneKeys = [(lane.rosterDayId, normalizeLaneName lane.name) | lane <- activeLanes]
        hasDuplicateDayLaneNames = Set.size (Set.fromList activeLaneKeys) /= length activeLaneKeys
        structuralError
            | hasDuplicateDayLaneNames = Just "The viewed roster contains duplicate column names on one day."
            | null columns = Just "The viewed roster window must contain at least one column."
            | otherwise = Nothing
    case (structuralError, mapM (rawShiftInput days window activeLanes) slots) of
        (Just message, _) -> pure (Left (RosterTemplateCaptureInvalidStructure message))
        (Nothing, Nothing) -> pure (Left (RosterTemplateCaptureInvalidStructure "The viewed roster contains an incomplete shift or invalid placement."))
        (Nothing, Just rawShifts) -> do
                let sourceShiftTypeIds = nub (map (.inputShiftTypeId) rawShifts)
                    sourceStaffIds = nub [staffId | shift <- rawShifts, StaffAssignment staffId <- [shift.inputShiftAssignment]]
                sourceShiftTypes <- if null sourceShiftTypeIds then pure [] else query @ShiftType |> filterWhereIn (#id, sourceShiftTypeIds) |> fetch
                availableShiftTypes <- query @ShiftType
                    |> filterWhere (#venueId, rosterGroup.venueId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> orderByAsc #createdAt
                    |> fetch
                let sourceShiftTypeById = Map.fromList [(shiftType.id, shiftType) | shiftType <- sourceShiftTypes]
                    availableShiftTypeIds = Set.fromList (map (.id) availableShiftTypes)
                    staleIds = filter (shiftTypeIsStale actor sourceShiftTypeById) sourceShiftTypeIds
                    suppliedMappings = request.captureShiftTypeMappings
                    invalidMappingSources = filter (`notElem` staleIds) (Map.keys suppliedMappings)
                    invalidMappingTargets =
                        [ sourceId
                        | (sourceId, targetId) <- Map.toList suppliedMappings
                        , sourceId `elem` staleIds
                        , targetId `Set.notMember` availableShiftTypeIds
                        ]
                    invalidMappings = nub (invalidMappingSources <> invalidMappingTargets)
                if not (null invalidMappings)
                    then pure (Left (RosterTemplateCaptureInvalidShiftTypeMappings invalidMappings))
                    else do
                        let requirements = map (shiftTypeRequirement sourceShiftTypeById rawShifts suppliedMappings) staleIds
                            mappedShifts = map (applyShiftTypeMapping suppliedMappings) rawShifts
                            allMappingsPresent = all (isJust . (.captureMappedShiftTypeId)) requirements
                        (warnings, finalShifts, staffFacts) <- case request.captureAssignmentMode of
                            MakeEveryShiftOpen -> pure ([], map makeShiftOpen mappedShifts, [])
                            KeepValidStaffAssignments -> validateCapturedAssignments rosterGroup availableShiftTypes mappedShifts
                        let daysInput =
                                [ RosterTemplateDayInput
                                    { inputDayIndex = dayIndex
                                    , inputDayWeekdayIndex = Just (weekdayIndexForDay day.operationalDate)
                                    , inputDayIsClosed = day.isClosed
                                    , inputDayRowCount = day.rowCount
                                    }
                                | (dayIndex, day) <- zip [0 ..] days
                                ]
                            content = RosterTemplateContent daysInput columns finalShifts
                            revisionFacts = tshow (daysInput, columns, rawShifts, warnings, finalShifts)
                            revisionShiftTypes = nubBy (\left right -> left.id == right.id) (sourceShiftTypes <> availableShiftTypes)
                            revision = captureRevision request normalizedName revisionFacts venueConfig days activeLanes slots revisionShiftTypes staffFacts
                        pure (Right RosterTemplateCapturePreview
                            { capturePreviewName = normalizedName
                            , capturePreviewAssignmentMode = request.captureAssignmentMode
                            , capturePreviewSourceRevision = revision
                            , capturePreviewCalendarRevision = venueConfig.rosterCalendarRevision
                            , capturePreviewWarnings = warnings
                            , capturePreviewShiftTypeRequirements = requirements
                            , capturePreviewAvailableShiftTypes = availableShiftTypes
                            , capturePreviewContent = content <$ guard allMappingsPresent
                            , capturePreviewReferencedShiftTypes = nub (sourceShiftTypeIds <> Map.elems suppliedMappings)
                            , capturePreviewReferencedStaff = sourceStaffIds
                            })

rawShiftInput :: [RosterDay] -> RosterWindow -> [RosterLane] -> RosterSlot -> Maybe RosterTemplateShiftInput
rawShiftInput days window activeLanes slot = do
    day <- find ((== slot.rosterDayId) . unpackId . (.id)) days
    lane <- find ((== slot.rosterLaneId) . unpackId . (.id)) activeLanes
    guard (lane.rosterDayId == slot.rosterDayId)
    columnSortOrder <- findIndex ((== normalizeLaneName lane.name) . (.rosterWindowLaneNormalizedName)) window.rosterWindowLanes
    startsAt <- slot.startsAt
    endsAt <- slot.endsAt
    shiftTypeId <- Id <$> slot.shiftTypeId
    assignment <- either (const Nothing) Just (rosterShiftAssignment slot)
    startMinute <- minuteRelativeToOperationalDate day.operationalDate startsAt
    endMinute <- minuteRelativeToOperationalDate day.operationalDate endsAt
    sourceDay <- listToMaybe days
    guard (slot.rowIndex >= 0 && slot.rowIndex < day.rowCount)
    guard (startMinute >= 0 && endMinute > startMinute && endMinute <= 2880)
    let sourceWindowStart = sourceDay.operationalDate
    pure RosterTemplateShiftInput
        { inputShiftDayIndex = fromInteger (diffDays day.operationalDate sourceWindowStart)
        , inputShiftColumnSortOrder = columnSortOrder
        , inputShiftRowIndex = slot.rowIndex
        , inputShiftStartMinute = startMinute
        , inputShiftEndMinute = endMinute
        , inputShiftTypeId = shiftTypeId
        , inputShiftAssignment = assignment
        }

minuteRelativeToOperationalDate :: Day -> UTCTime -> Maybe Int
minuteRelativeToOperationalDate operationalDate instant = do
    let LocalTime localDate (TimeOfDay hour minute seconds) = resolvedInstantLocalTime (resolvedInstantFromUTC instant)
    guard (seconds == 0)
    pure (fromInteger (diffDays localDate operationalDate) * 1440 + hour * 60 + minute)

normalizeLaneName :: Text -> Text
normalizeLaneName = Text.toCaseFold . Text.strip

shiftTypeIsStale :: RosterTemplateActor -> Map.Map (Id ShiftType) ShiftType -> Id ShiftType -> Bool
shiftTypeIsStale actor shiftTypes shiftTypeId = case Map.lookup shiftTypeId shiftTypes of
    Nothing -> True
    Just shiftType ->
        shiftType.venueId /= unpackId (rosterTemplateActorVenueId actor)
            || not shiftType.isActive
            || isJust shiftType.archivedAt

shiftTypeRequirement :: Map.Map (Id ShiftType) ShiftType -> [RosterTemplateShiftInput] -> Map.Map (Id ShiftType) (Id ShiftType) -> Id ShiftType -> RosterTemplateCaptureShiftTypeRequirement
shiftTypeRequirement shiftTypes shifts mappings staleId =
    RosterTemplateCaptureShiftTypeRequirement
        { captureStaleShiftTypeId = staleId
        , captureStaleShiftTypeName = maybe "Unavailable Shift type" (.name) (Map.lookup staleId shiftTypes)
        , captureStaleShiftCount = length (filter ((== staleId) . (.inputShiftTypeId)) shifts)
        , captureMappedShiftTypeId = Map.lookup staleId mappings
        }

applyShiftTypeMapping :: Map.Map (Id ShiftType) (Id ShiftType) -> RosterTemplateShiftInput -> RosterTemplateShiftInput
applyShiftTypeMapping mappings shift =
    shift { inputShiftTypeId = Map.findWithDefault shift.inputShiftTypeId shift.inputShiftTypeId mappings }

makeShiftOpen :: RosterTemplateShiftInput -> RosterTemplateShiftInput
makeShiftOpen shift = shift { inputShiftAssignment = OpenAssignment }

validateCapturedAssignments ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    [ShiftType] ->
    [RosterTemplateShiftInput] ->
    IO ([RosterTemplateCaptureWarning], [RosterTemplateShiftInput], [Text])
validateCapturedAssignments rosterGroup shiftTypes shifts = do
    let staffIds = nub [staffId | shift <- shifts, StaffAssignment staffId <- [shift.inputShiftAssignment]]
    staff <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, staffIds) |> fetch
    memberships <- if null staffIds then pure [] else query @StaffRosterGroup
        |> filterWhereIn (#staffId, map unpackId staffIds)
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
    activeImportedPayItems <- query @XeroImportedPayItem
        |> filterWhere (#venueId, rosterGroup.venueId)
        |> filterWhere (#archivedAt, Nothing)
        |> filterWhere (#providerAvailable, True)
        |> fetch
    let staffById = Map.fromList [(person.id, person) | person <- staff]
        shiftTypeById = Map.fromList [(shiftType.id, shiftType) | shiftType <- shiftTypes]
        eligibleStaffIds = Set.fromList (map (.staffId) memberships)
        activeAwardIds = map (.id) activeAwardLevels
        activeImportedPayItemIds = map (.id) activeImportedPayItems
        classify shift = case shift.inputShiftAssignment of
            OpenAssignment -> Nothing
            StaffAssignment staffId -> Just (staffId, capturedStaffIssue activeAwardIds activeImportedPayItemIds eligibleStaffIds rosterGroup (Map.lookup staffId staffById) (Map.lookup shift.inputShiftTypeId shiftTypeById))
        classifiedShifts = [(shift, classify shift) | shift <- shifts]
        issues = [(staffId, issue) | (_, Just (staffId, Just issue)) <- classifiedShifts]
        issueCounts = Map.fromListWith (+) [((staffId, issue), 1 :: Int) | (staffId, issue) <- issues]
        warningFor ((staffId, issue), count) =
            RosterTemplateCaptureWarning staffId (staffDisplayName staffId (Map.lookup staffId staffById)) issue count
        warnings = map warningFor (sortOn (\((staffId, issue), _) -> (staffDisplayName staffId (Map.lookup staffId staffById), issue)) (Map.toList issueCounts))
        invalidKeys = Set.fromList issues
        finalShifts =
            [ case classification of
                Just (_, Just _) -> makeShiftOpen shift
                _                -> shift
            | (shift, classification) <- classifiedShifts
            ]
        staffFacts =
            [ tshow (person.id, person.venueId, person.isActive, person.archivedAt, person.payAssignmentMode, person.defaultAwardLevelId, person.importedXeroPayItemId, Set.member (unpackId person.id) eligibleStaffIds, person.updatedAt)
            | person <- staff
            ] <> [tshow invalidKeys]
    pure (warnings, finalShifts, staffFacts)

capturedStaffIssue ::
    [Id AwardLevel] ->
    [Id XeroImportedPayItem] ->
    Set.Set UUID ->
    RosterGroup ->
    Maybe Staff ->
    Maybe ShiftType ->
    Maybe RosterTemplateCaptureStaffIssue
capturedStaffIssue activeAwardIds activeImportedPayItemIds eligibleStaffIds rosterGroup maybeStaff maybeShiftType =
    case (maybeStaff, maybeShiftType) of
        (Nothing, _) -> Just CaptureStaffUnavailable
        (Just staff, _)
            | staff.venueId /= rosterGroup.venueId || not staff.isActive || isJust staff.archivedAt -> Just CaptureStaffUnavailable
            | unpackId staff.id `Set.notMember` eligibleStaffIds -> Just CaptureStaffOutsideGroup
        (Just staff, Just shiftType) ->
            let staffAssignment = StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId
                shiftAssignment = ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId
                referencesCurrent =
                    not (staffPayAssignmentRequiresRemediation activeAwardIds activeImportedPayItemIds staffAssignment)
                        && not (shiftPayAssignmentRequiresRemediation activeAwardIds activeImportedPayItemIds shiftAssignment)
                payValid = case resolvePayAssignment staffAssignment shiftAssignment of
                    InvalidPayAssignment {} -> False
                    _                       -> True
             in CaptureStaffPayInvalid <$ guard (not referencesCurrent || not payValid)
        (Just _, Nothing) -> Just CaptureStaffPayInvalid

staffDisplayName :: Id Staff -> Maybe Staff -> Text
staffDisplayName staffId = maybe ("Unavailable Staff " <> tshow staffId) (Text.strip . (\staff -> staff.firstName <> " " <> staff.lastName))

captureRevision ::
    RosterTemplateCaptureRequest ->
    Text ->
    Text ->
    VenueConfig ->
    [RosterDay] ->
    [RosterLane] ->
    [RosterSlot] ->
    [ShiftType] ->
    [Text] ->
    Text
captureRevision request normalizedName revisionFacts venueConfig days lanes slots shiftTypes staffFacts =
    tshow (Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256)
  where
    payload = Text.intercalate "|"
        [ tshow (normalizedName, request.captureAssignmentMode, Map.toAscList request.captureShiftTypeMappings)
        , revisionFacts
        , tshow (venueConfig.venueId, venueConfig.rosterCalendarRevision, venueConfig.rosterWeekStartsOn)
        , tshow [(day.id, day.operationalDate, day.isClosed, day.rowCount, day.updatedAt) | day <- days]
        , tshow [(lane.id, lane.rosterDayId, lane.name, lane.sortOrder, lane.deletedAt, lane.updatedAt) | lane <- sortOn (.id) lanes]
        , tshow
            [ (slot.id, slot.rosterDayId, slot.rosterLaneId, slot.assignmentState, slot.staffId, slot.rowIndex, slot.startsAt, slot.endsAt, slot.timezone, slot.shiftTypeId, slot.deletedAt, slot.updatedAt)
            | slot <- slots
            ]
        , tshow
            [ (shiftType.id, shiftType.venueId, shiftType.name, shiftType.isActive, shiftType.archivedAt, shiftType.payAssignmentMode, shiftType.overrideAwardLevelId, shiftType.importedXeroPayItemId, shiftType.updatedAt)
            | shiftType <- sortOn (.id) shiftTypes
            ]
        , tshow staffFacts
        ]
