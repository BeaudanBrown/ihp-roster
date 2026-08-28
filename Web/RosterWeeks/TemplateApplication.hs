{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication
    ( RosterTemplateApplicationAssignmentIssue (..)
    , RosterTemplateApplicationBoundary (..)
    , RosterTemplateApplicationError (..)
    , RosterTemplateApplicationPreview (..)
    , RosterTemplateApplicationRequest (..)
    , RosterTemplateApplicationResolvedShift (..)
    , RosterTemplateApplicationResult (..)
    , RosterTemplateApplicationShiftTypeRequirement (..)
    , RosterTemplateApplicationWarning (..)
    , applyRosterTemplateApplication
    , applyRosterTemplateApplicationMutation
    , previewRosterTemplateApplication
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterPublication.Mutations (withRosterWindowDateLockInCurrentTransaction)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateApplicationRows)
import Application.VenueTime (RepeatedTimeOccurrence (FirstOccurrence),
                              melbourneTimeZoneName)
import Application.VenueTime.Model
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import Web.RosterWeeks.Service (validateRosterSlotForPersistence)
import Web.RosterWeeks.TemplateApplication.Persistence (applyPreparedApplication)
import Web.RosterWeeks.TemplateApplication.Types
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

previewRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationPreview)
previewRosterTemplateApplication actor request = fmap toPreview <$> prepareRosterTemplateApplication actor request

applyRosterTemplateApplicationMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError (LiveMutationResult RosterTemplateApplicationResult))
applyRosterTemplateApplicationMutation actor request expectedTargetRevision expectedCalendarRevision =
    withDurableLiveMutationOutcome publicationFor do
        fmap (fmap (\result -> liveMutationResult result result.appliedTouchedResources)) $
            applyRosterTemplateApplicationInCurrentTransaction actor request expectedTargetRevision expectedCalendarRevision
  where
    publicationFor = either (const Nothing) (\result -> Just ("roster.template.apply", result.liveMutationTouchedResources))

applyRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplication actor request expectedTargetRevision expectedCalendarRevision =
    withTransaction $
        applyRosterTemplateApplicationInCurrentTransaction actor request expectedTargetRevision expectedCalendarRevision

applyRosterTemplateApplicationInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplicationInCurrentTransaction actor request expectedTargetRevision expectedCalendarRevision =
    withRosterWindowDateLockInCurrentTransaction
        (rosterTemplateActorVenueId actor)
        request.applicationTargetRosterGroupId
        request.applicationTargetWindowStart
        request.applicationTargetWindowEnd do
            lockRosterTemplateApplicationRows
                request.applicationTemplateId
                (rosterTemplateActorVenueId actor)
                request.applicationTargetRosterGroupId
                request.applicationTargetWindowStart
                request.applicationTargetWindowEnd
                (Map.elems request.applicationShiftTypeMappings)
            preparedResult <- prepareRosterTemplateApplication actor request
            case preparedResult of
                Left failure -> pure (Left failure)
                Right prepared
                    | prepared.preparedCalendarRevision /= expectedCalendarRevision -> pure (Left RosterTemplateApplicationCalendarConflict)
                    | targetRevision prepared /= expectedTargetRevision -> pure (Left RosterTemplateApplicationTargetConflict)
                    | not (null missingMappingIds) -> pure (Left (RosterTemplateApplicationShiftTypeMappingsRequired missingMappingIds))
                    | otherwise -> do
                        templateChanged <- applyPreparedApplication actor prepared
                        let preview = toPreview prepared
                        pure (Right RosterTemplateApplicationResult
                            { appliedTargetWindowStart = prepared.preparedTargetWindowStart
                            , appliedTargetWindowEnd = prepared.preparedTargetWindowEnd
                            , appliedTemplateChanged = templateChanged
                            , appliedWarnings = preview.applicationWarnings
                            , appliedTouchedResources = preview.applicationTouchedResources
                            })
                  where
                    missingMappingIds =
                        [ requirement.applicationStaleShiftTypeId
                        | requirement <- prepared.preparedShiftTypeRequirements
                        , isNothing requirement.applicationMappedShiftTypeId
                        ]

prepareRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareRosterTemplateApplication actor request
    | not (rosterTemplateActorCanEditRosters actor) = pure (Left RosterTemplateApplicationForbidden)
    | request.applicationTargetWindowEnd /= addDays 7 request.applicationTargetWindowStart = pure (Left RosterTemplateApplicationInvalidTargetDay)
    | otherwise = do
        maybeSaved <- fetchSavedRosterTemplate actor request.applicationTemplateId
        maybeTargetGroup <- query @RosterGroup
            |> filterWhere (#id, request.applicationTargetRosterGroupId)
            |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
        case (maybeSaved, maybeTargetGroup) of
            (Nothing, _) -> pure (Left RosterTemplateApplicationNotFound)
            (_, Nothing) -> pure (Left RosterTemplateApplicationNotFound)
            (Just saved, Just targetGroup)
                | targetGroup.id /= Id saved.snapshotTemplate.rosterGroupId -> pure (Left RosterTemplateApplicationScopeMismatch)
                | saved.snapshotTemplate.scale /= Week -> pure (Left RosterTemplateApplicationScaleMismatch)
                | otherwise -> prepareContent request saved targetGroup

templateStructureError :: [RosterTemplateDay] -> Maybe Text
templateStructureError days
    | sort (mapMaybe (.weekdayIndex) days) /= [0 .. 6] = Just "Week templates must contain all seven weekdays."
    | otherwise = Nothing

prepareContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSnapshot ->
    RosterGroup ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareContent request saved targetGroup = case templateStructureError saved.snapshotDays of
    Just message -> pure (Left (RosterTemplateApplicationInvalidStructure message))
    Nothing -> prepareStructurallyValidContent request saved targetGroup

prepareStructurallyValidContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSnapshot ->
    RosterGroup ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareStructurallyValidContent request saved targetGroup = do
    targetDays <- query @RosterDay
        |> filterWhere (#venueId, targetGroup.venueId)
        |> filterWhere (#rosterGroupId, unpackId targetGroup.id)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, request.applicationTargetWindowStart)
        |> filterWhereLessThan (#operationalDate, request.applicationTargetWindowEnd)
        |> orderByAsc #operationalDate
        |> fetch
    if any ((== Published) . (.publicationState)) targetDays
        then pure (Left RosterTemplateApplicationTargetLive)
        else if map (.operationalDate) targetDays /= map (`addDays` request.applicationTargetWindowStart) [0 .. 6]
            then pure (Left RosterTemplateApplicationInvalidTargetDay)
            else do
                shiftTypeResolution <- resolveApplicationShiftTypes request saved targetGroup
                case shiftTypeResolution of
                    Left failure -> pure (Left failure)
                    Right (requirements, availableShiftTypes, effectiveShiftTypeIds, shiftTypeRevision) -> do
                        let targetDayByWeekday = Map.fromList [(weekdayIndexForDay day.operationalDate, day) | day <- targetDays]
                            templateDayIndexById = Map.fromList
                                [ (unpackId day.id, fromMaybe day.dayIndex day.weekdayIndex)
                                | day <- saved.snapshotDays
                                ]
                            templateColumnById = Map.fromList [(unpackId column.id, column) | column <- saved.snapshotColumns]
                        venueConfig <- query @VenueConfig |> filterWhere (#venueId, targetGroup.venueId) |> fetchOne
                        let shiftPlans = traverse (prepareShift venueConfig targetDayByWeekday templateDayIndexById templateColumnById effectiveShiftTypeIds) saved.snapshotShifts
                        case shiftPlans of
                            Left failure -> pure (Left failure)
                            Right boundaryPlans -> do
                                (plans, staffNames, assignmentReferenceRevision) <- validateAssignments targetGroup availableShiftTypes boundaryPlans
                                existingSlots <- query @RosterSlot
                                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                                    |> filterWhere (#deletedAt, Nothing)
                                    |> orderByAsc #id
                                    |> fetch
                                targetLanes <- query @RosterLane
                                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                                    |> filterWhere (#deletedAt, Nothing)
                                    |> orderByAsc #id
                                    |> fetch
                                timesheetEntries <- if null existingSlots then pure [] else query @TimesheetEntry
                                    |> filterWhereIn (#sourceRosterSlotId, map (Just . unpackId . (.id)) existingSlots)
                                    |> filterWhere (#deletedAt, Nothing)
                                    |> orderByAsc #id
                                    |> fetch
                                let mappingsComplete = all (isJust . (.applicationMappedShiftTypeId)) requirements
                                    hasDurableCleanup = any (maybe False issueIsDurable . (.preparedAssignmentIssue)) plans
                                    cleanedContent
                                        | mappingsComplete && (not (null requirements) || hasDurableCleanup) = Just (cleanedTemplateContent saved plans)
                                        | otherwise = Nothing
                                pure (Right PreparedApplication
                                    { preparedSaved = saved
                                    , preparedTargetGroup = targetGroup
                                    , preparedTargetWindowStart = request.applicationTargetWindowStart
                                    , preparedTargetWindowEnd = request.applicationTargetWindowEnd
                                    , preparedTargetDays = targetDays
                                    , preparedShiftPlans = plans
                                    , preparedExistingSlots = existingSlots
                                    , preparedTargetLanes = targetLanes
                                    , preparedTimesheetEntries = timesheetEntries
                                    , preparedCalendarRevision = venueConfig.rosterCalendarRevision
                                    , preparedShiftTypeRequirements = requirements
                                    , preparedAvailableShiftTypes = availableShiftTypes
                                    , preparedStaffNames = staffNames
                                    , preparedCleanedTemplateContent = cleanedContent
                                    , preparedReferenceRevision = shiftTypeRevision <> ":" <> assignmentReferenceRevision
                                    })

resolveApplicationShiftTypes ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSnapshot ->
    RosterGroup ->
    IO (Either RosterTemplateApplicationError ([RosterTemplateApplicationShiftTypeRequirement], [ShiftType], Map.Map (Id ShiftType) (Id ShiftType), Text))
resolveApplicationShiftTypes request saved targetGroup = do
    let sourceIds = nub [Id shift.shiftTypeId :: Id ShiftType | shift <- saved.snapshotShifts]
    sourceTypes <- if null sourceIds then pure [] else query @ShiftType |> filterWhereIn (#id, sourceIds) |> fetch
    available <- query @ShiftType
        |> filterWhere (#venueId, targetGroup.venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    let sourceById = Map.fromList [(shiftType.id, shiftType) | shiftType <- sourceTypes]
        availableIds = Set.fromList (map (.id) available)
        staleIds =
            [ sourceId
            | sourceId <- sourceIds
            , case Map.lookup sourceId sourceById of
                Nothing -> True
                Just source -> source.venueId /= targetGroup.venueId || source.id `Set.notMember` availableIds
            ]
        mappingKeys = Map.keysSet request.applicationShiftTypeMappings
        mappingsValid = mappingKeys `Set.isSubsetOf` Set.fromList staleIds
        currentMappings = Map.filter (`Set.member` availableIds) request.applicationShiftTypeMappings
        requirements =
            [ RosterTemplateApplicationShiftTypeRequirement
                { applicationStaleShiftTypeId = sourceId
                , applicationStaleShiftTypeName = maybe "Unavailable Shift type" (.name) (Map.lookup sourceId sourceById)
                , applicationMappedShiftTypeId = Map.lookup sourceId currentMappings
                }
            | sourceId <- staleIds
            ]
        effectiveIds = Map.fromList
            [ (sourceId, fromMaybe sourceId (Map.lookup sourceId currentMappings))
            | sourceId <- sourceIds
            ]
    pure if mappingsValid
        then Right (requirements, available, effectiveIds, digestText (tshow (sourceTypes, available)))
        else Left RosterTemplateApplicationInvalidShiftTypeMappings

prepareShift ::
    VenueConfig ->
    Map.Map Int RosterDay ->
    Map.Map UUID Int ->
    Map.Map UUID RosterTemplateColumn ->
    Map.Map (Id ShiftType) (Id ShiftType) ->
    RosterTemplateShift ->
    Either RosterTemplateApplicationError PreparedShift
prepareShift venueConfig targetDayByWeekday templateDayIndexById templateColumnById effectiveShiftTypeIds shift = do
    templateWeekday <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateDayId templateDayIndexById)
    targetDay <- maybe invalidStructure Right (Map.lookup templateWeekday targetDayByWeekday)
    templateColumn <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateColumnId templateColumnById)
    assignment <- case (shift.assignmentState, shift.staffId) of
        ("staff", Just staffId) -> Right (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Right OpenAssignment
        _                       -> invalidStructure
    let rosterDate = targetDay.operationalDate
        sourceShiftTypeId = Id shift.shiftTypeId
        effectiveShiftTypeId = Map.findWithDefault sourceShiftTypeId sourceShiftTypeId effectiveShiftTypeIds
    startsAt <- resolveTemplateMinute shift.id RosterTemplateApplicationStartBoundary venueConfig.timezone rosterDate shift.startMinute
    endsAt <- resolveTemplateMinute shift.id RosterTemplateApplicationEndBoundary venueConfig.timezone rosterDate shift.endMinute
    _ <- either (Left . RosterTemplateApplicationBoundaryError shift.id RosterTemplateApplicationEndBoundary) Right (authoritativeBoundariesFromInstants venueConfig.timezone startsAt endsAt Nothing Nothing)
    pure PreparedShift
        { preparedTemplateShift = shift
        , preparedTemplateColumn = templateColumn
        , preparedTargetDay = targetDay
        , preparedStartsAt = startsAt
        , preparedEndsAt = endsAt
        , preparedAssignment = assignment
        , preparedShiftTypeId = effectiveShiftTypeId
        , preparedAssignmentIssue = Nothing
        }
  where
    invalidStructure = Left (RosterTemplateApplicationInvalidStructure "Template shift references are incomplete.")

validateAssignments ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    [ShiftType] ->
    [PreparedShift] ->
    IO ([PreparedShift], Map.Map (Id Staff) Text, Text)
validateAssignments targetGroup availableShiftTypes plans = do
    let targetStart = case plans of
            [] -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated template application has no shift plans"
            firstPlan : remainingPlans -> foldl' min firstPlan.preparedTargetDay.operationalDate (map (.preparedTargetDay.operationalDate) remainingPlans)
    let staffIds = nub [staffId | plan <- plans, StaffAssignment staffId <- [plan.preparedAssignment]]
    staff <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, staffIds) |> fetch
    memberships <- if null staffIds then pure [] else query @StaffRosterGroup
        |> filterWhereIn (#staffId, map unpackId staffIds)
        |> filterWhere (#rosterGroupId, unpackId targetGroup.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    leaveRequests <- if null staffIds then pure [] else query @LeaveRequest
        |> filterWhereIn (#staffId, map unpackId staffIds)
        |> filterWhere (#venueId, targetGroup.venueId)
        |> filterWhere (#status, LeaveRequestStatusEnumApproved)
        |> filterWhereLessThan (#startDate, addDays 7 targetStart)
        |> filterWhereGreaterThan (#endDate, targetStart)
        |> fetch
    let effectiveShiftTypeIds = Set.fromList (map (.preparedShiftTypeId) plans)
        effectiveShiftTypes = filter (\shiftType -> shiftType.id `Set.member` effectiveShiftTypeIds) availableShiftTypes
        awardIds = nub (catMaybes (map (.defaultAwardLevelId) staff <> map (.overrideAwardLevelId) effectiveShiftTypes))
        importedPayItemIds = nub (catMaybes (map (.importedXeroPayItemId) staff <> map (.importedXeroPayItemId) effectiveShiftTypes))
    awardLevels <- if null awardIds then pure [] else query @AwardLevel |> filterWhereIn (#id, awardIds) |> fetch
    importedPayItems <- if null importedPayItemIds then pure [] else query @XeroImportedPayItem |> filterWhereIn (#id, importedPayItemIds) |> fetch
    let staffById = Map.fromList [(person.id, person) | person <- staff]
        staffNames = Map.map (\person -> Text.strip (person.firstName <> " " <> person.lastName)) staffById
        membershipIds = Set.fromList [Id membership.staffId :: Id Staff | membership <- memberships]
        availableShiftTypeIds = Set.fromList (map (.id) availableShiftTypes)
        onApprovedLeave staffId operationalDate = any (\leave -> Id leave.staffId == staffId && operationalDate >= leave.startDate && operationalDate < leave.endDate) leaveRequests
    validated <- forM plans \plan -> case plan.preparedAssignment of
        OpenAssignment -> pure plan
        StaffAssignment staffId -> case Map.lookup staffId staffById of
            Nothing -> pure (convertToOpen RosterTemplateStaffUnavailable plan)
            Just person
                | person.venueId /= targetGroup.venueId || not person.isActive || isJust person.archivedAt ->
                    pure (convertToOpen RosterTemplateStaffUnavailable plan)
                | staffId `Set.notMember` membershipIds -> pure (convertToOpen RosterTemplateStaffOutsideGroup plan)
                | plan.preparedShiftTypeId `Set.notMember` availableShiftTypeIds -> pure plan
                | otherwise -> do
                    let candidate =
                            newRecord @RosterSlot
                                |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
                                |> set #slotSortOrder plan.preparedTemplateColumn.sortOrder
                                |> set #rowIndex plan.preparedTemplateShift.rowIndex
                                |> set #startsAt (Just plan.preparedStartsAt)
                                |> set #endsAt (Just plan.preparedEndsAt)
                                |> set #timezone melbourneTimeZoneName
                                |> set #shiftTypeId (Just (unpackId plan.preparedShiftTypeId))
                                |> applyRosterShiftAssignment (StaffAssignment staffId)
                    payError <- validateRosterSlotForPersistence (Id targetGroup.venueId) candidate
                    pure case payError of
                        Just _ -> convertToOpen RosterTemplateStaffPayInvalid plan
                        Nothing
                            | onApprovedLeave staffId plan.preparedTargetDay.operationalDate -> convertToOpen RosterTemplateStaffOnApprovedLeave plan
                            | otherwise -> plan
    pure (validated, staffNames, digestText (tshow (staff, memberships, leaveRequests, awardLevels, importedPayItems)))
  where
    convertToOpen issue plan = plan
        { preparedAssignment = OpenAssignment
        , preparedAssignmentIssue = Just issue
        }

issueIsDurable :: RosterTemplateApplicationAssignmentIssue -> Bool
issueIsDurable RosterTemplateStaffUnavailable     = True
issueIsDurable RosterTemplateStaffOutsideGroup    = True
issueIsDurable RosterTemplateStaffPayInvalid      = True
issueIsDurable RosterTemplateStaffOnApprovedLeave = False

cleanedTemplateContent :: RosterTemplateSnapshot -> [PreparedShift] -> RosterTemplateContent
cleanedTemplateContent saved plans =
    RosterTemplateContent
        { contentDays =
            [ RosterTemplateDayInput day.dayIndex day.weekdayIndex day.isClosed day.rowCount
            | day <- saved.snapshotDays
            ]
        , contentColumns =
            [ RosterTemplateColumnInput column.name column.sortOrder
            | column <- saved.snapshotColumns
            ]
        , contentShifts = map cleanedShift plans
        }
  where
    dayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- saved.snapshotDays]
    cleanedShift plan =
        RosterTemplateShiftInput
            { inputShiftDayIndex = Map.findWithDefault (externalRuntimeInvariantFailure PersistedRuntimeInvariant "prepared template day missing") plan.preparedTemplateShift.rosterTemplateDayId dayIndexById
            , inputShiftColumnSortOrder = plan.preparedTemplateColumn.sortOrder
            , inputShiftRowIndex = plan.preparedTemplateShift.rowIndex
            , inputShiftStartMinute = plan.preparedTemplateShift.startMinute
            , inputShiftEndMinute = plan.preparedTemplateShift.endMinute
            , inputShiftTypeId = plan.preparedShiftTypeId
            , inputShiftAssignment = case (plan.preparedTemplateShift.assignmentState, plan.preparedTemplateShift.staffId, plan.preparedAssignmentIssue) of
                (_, _, Just issue) | issueIsDurable issue -> OpenAssignment
                ("staff", Just staffId, _) -> StaffAssignment (Id staffId)
                ("open", Nothing, _) -> OpenAssignment
                _ -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated template assignment shape changed"
            }

resolveTemplateMinute ::
    Id RosterTemplateShift ->
    RosterTemplateApplicationBoundary ->
    Text ->
    Day ->
    Int ->
    Either RosterTemplateApplicationError UTCTime
resolveTemplateMinute shiftId boundary timezone rosterDate minute =
    either (Left . RosterTemplateApplicationBoundaryError shiftId boundary) Right
        (resolveBoundaryInstant timezone targetDate timeOfDay occurrence)
  where
    (dayDelta, minuteOfDay) = minute `divMod` 1440
    (hour, minuteWithinHour) = minuteOfDay `divMod` 60
    targetDate = addDays (toInteger dayDelta) rosterDate
    timeOfDay = TimeOfDay hour minuteWithinHour 0
    occurrence
        | civilBoundaryIsRepeated targetDate timeOfDay = Just FirstOccurrence
        | otherwise = Nothing

toPreview :: PreparedApplication -> RosterTemplateApplicationPreview
toPreview prepared =
    RosterTemplateApplicationPreview
        { applicationPreviewTemplateName = prepared.preparedSaved.snapshotTemplate.name
        , applicationPreviewTargetWindowStart = prepared.preparedTargetWindowStart
        , applicationPreviewTargetWindowEnd = prepared.preparedTargetWindowEnd
        , applicationExpectedTargetRevision = targetRevision prepared
        , applicationExpectedTemplateRevision = rosterTemplateSnapshotRevision prepared.preparedSaved
        , applicationRosterCalendarRevision = prepared.preparedCalendarRevision
        , applicationReplacementShiftCount = length prepared.preparedShiftPlans
        , applicationExistingShiftCount = length prepared.preparedExistingSlots
        , applicationResolvedShifts = map resolvedShift prepared.preparedShiftPlans
        , applicationShiftTypeRequirements = prepared.preparedShiftTypeRequirements
        , applicationAvailableShiftTypes = prepared.preparedAvailableShiftTypes
        , applicationWarnings = RosterTemplateApplicationClearsWeek : assignmentWarnings <> timesheetWarnings
        , applicationTouchedResources = touchedResources prepared
        }
  where
    resolvedShift plan = RosterTemplateApplicationResolvedShift
        { resolvedTemplateShiftId = plan.preparedTemplateShift.id
        , resolvedTargetDayOffset = fromInteger (diffDays plan.preparedTargetDay.operationalDate prepared.preparedTargetWindowStart)
        , resolvedStartsAt = plan.preparedStartsAt
        , resolvedEndsAt = plan.preparedEndsAt
        , resolvedAssignment = plan.preparedAssignment
        }
    groupedIssues = Map.fromListWith (+)
        [ ((staffId, issue), 1 :: Int)
        | plan <- prepared.preparedShiftPlans
        , StaffAssignment staffId <- [templateShiftAssignment plan.preparedTemplateShift]
        , Just issue <- [plan.preparedAssignmentIssue]
        ]
    assignmentWarnings =
        [ RosterTemplateApplicationAssignmentConvertedToOpen staffId (Map.findWithDefault "Unavailable Staff member" staffId prepared.preparedStaffNames) issue count
        | ((staffId, issue), count) <- Map.toList groupedIssues
        ]
    timesheetWarnings =
        [RosterTemplateApplicationExistingTimesheetsRemain (length prepared.preparedTimesheetEntries) | not (null prepared.preparedTimesheetEntries)]

templateShiftAssignment :: RosterTemplateShift -> RosterShiftAssignment
templateShiftAssignment shift = case (shift.assignmentState, shift.staffId) of
    ("staff", Just staffId) -> StaffAssignment (Id staffId)
    ("open", Nothing)       -> OpenAssignment
    _                       -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated template assignment shape changed"

digestText :: Text -> Text
digestText value = tshow (Hash.hash (TextEncoding.encodeUtf8 value) :: Hash.Digest Hash.SHA256)

targetRevision :: PreparedApplication -> Text
targetRevision prepared = digestText payload
  where
    payload = Text.intercalate "|"
        [ rosterTemplateSnapshotRevision prepared.preparedSaved
        , tshow (prepared.preparedTargetGroup.id, prepared.preparedTargetWindowStart, prepared.preparedTargetWindowEnd)
        , tshow [(day.id, day.operationalDate, day.publicationState, day.isClosed, day.rowCount, day.updatedAt) | day <- prepared.preparedTargetDays]
        , tshow [(lane.id, lane.rosterDayId, lane.name, lane.sortOrder, lane.updatedAt) | lane <- prepared.preparedTargetLanes]
        , tshow
            [ (slot.id, slot.rosterDayId, slot.assignmentState, slot.staffId, slot.slotSortOrder, slot.rowIndex, slot.startsAt, slot.endsAt, slot.shiftTypeId, slot.updatedAt)
            | slot <- prepared.preparedExistingSlots
            ]
        , tshow [(entry.id, entry.sourceRosterSlotId, entry.updatedAt) | entry <- prepared.preparedTimesheetEntries]
        , prepared.preparedReferenceRevision
        , tshow prepared.preparedShiftTypeRequirements
        , tshow [(plan.preparedTemplateShift.id, plan.preparedAssignmentIssue, plan.preparedShiftTypeId) | plan <- prepared.preparedShiftPlans]
        ]

touchedResources :: PreparedApplication -> [SurfaceResourceValue]
touchedResources prepared =
    [ rosterWeekResource groupId windowStart windowEnd
    , rosterWeekStructureResource groupId windowStart windowEnd
    , rosterSlotsStructureResource groupId windowStart windowEnd
    , rosterSlotsContentResource groupId windowStart windowEnd
    , timesheetWeekResource prepared.preparedTargetGroup.venueId windowStart windowEnd
    , rosterTemplateLibraryResource groupId
    ]
  where
    groupId = unpackId prepared.preparedTargetGroup.id
    windowStart = prepared.preparedTargetWindowStart
    windowEnd = prepared.preparedTargetWindowEnd
