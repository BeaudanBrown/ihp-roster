{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication
    ( RosterTemplateApplicationAssignmentIssue (..)
    , RosterTemplateApplicationBoundary (..)
    , RosterTemplateApplicationError (..)
    , RosterTemplateApplicationPreview (..)
    , RosterTemplateApplicationRequest (..)
    , RosterTemplateApplicationResolvedShift (..)
    , RosterTemplateApplicationResult (..)
    , RosterTemplateApplicationWarning (..)
    , applyRosterTemplateApplication
    , applyRosterTemplateApplicationMutation
    , previewRosterTemplateApplication
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.RosterTemplateScale (rosterTemplateScaleIsWeek)
import Application.Helper.SurfaceResource (LiveMutationResult,
                                           liveMutationResult)
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterPublication (fetchRosterWeekHasPublishedDay)
import Application.RosterPublication.Mutations (withRosterWindowLock)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateApplicationRows)
import Application.VenueTime (RepeatedTimeOccurrence, melbourneTimeZoneName)
import Application.VenueTime.Model
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import Web.RosterWeeks.Service (validateRosterSlotForPersistence)
import Web.RosterWeeks.TemplateApplication.Persistence (applyPreparedApplication)
import Web.RosterWeeks.TemplateApplication.Types
import Web.SurfaceInvalidation (invalidateTouchedResources)

previewRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationPreview)
previewRosterTemplateApplication actor request = do
    prepared <- prepareRosterTemplateApplication actor request
    pure (toPreview <$> prepared)

applyRosterTemplateApplicationMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Int ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError (LiveMutationResult RosterTemplateApplicationResult))
applyRosterTemplateApplicationMutation actor request expectedVersion expectedTargetRevision expectedCalendarRevision = do
    applied <- applyRosterTemplateApplication actor request expectedVersion expectedTargetRevision expectedCalendarRevision
    traverse (invalidateTouchedResources "roster.template.apply" . \result -> liveMutationResult result result.appliedTouchedResources) applied

applyRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Int ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplication actor request expectedVersion expectedTargetRevision expectedCalendarRevision = do
    lockTarget <- query @RosterWeek
        |> filterWhere (#id, request.applicationTargetWeekId)
        |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
        |> filterWhere (#archivedAt, Nothing)
        |> fetchOneOrNothing
    case lockTarget of
        Nothing -> pure (Left RosterTemplateApplicationNotFound)
        Just targetWeek ->
            withRosterWindowLock (rosterTemplateActorVenueId actor) (Id targetWeek.rosterGroupId) targetWeek.weekOffset do
                targetHasPublishedDay <- fetchRosterWeekHasPublishedDay targetWeek
                if targetHasPublishedDay
                    then pure (Left RosterTemplateApplicationTargetLive)
                    else do
                        lockRosterTemplateApplicationRows request.applicationTemplateId request.applicationTargetWeekId request.applicationTargetDayOffset
                        preparedResult <- prepareRosterTemplateApplication actor request
                        case preparedResult of
                            Left failure -> pure (Left failure)
                            Right prepared
                                | prepared.preparedCalendarRevision /= expectedCalendarRevision ->
                                    pure (Left RosterTemplateApplicationCalendarConflict)
                                | prepared.preparedSaved.savedTemplate.currentVersion /= expectedVersion ->
                                    pure (Left (RosterTemplateApplicationVersionConflict prepared.preparedSaved.savedTemplate.currentVersion))
                                | targetRevision prepared /= expectedTargetRevision ->
                                    pure (Left RosterTemplateApplicationTargetConflict)
                                | otherwise -> do
                                    appliedVersion <- applyPreparedApplication actor prepared
                                    refreshedWeek <- fetch prepared.preparedTargetWeek.id
                                    let preview = toPreview prepared
                                    pure (Right RosterTemplateApplicationResult
                                        { appliedRosterWeek = refreshedWeek
                                        , appliedTemplateVersion = appliedVersion
                                        , appliedWarnings = preview.applicationWarnings
                                        , appliedTouchedResources = preview.applicationTouchedResources
                                        })

prepareRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareRosterTemplateApplication actor request
    | not (rosterTemplateActorCanEditRosters actor) = pure (Left RosterTemplateApplicationForbidden)
    | otherwise = do
        maybeSaved <- fetchSavedRosterTemplate actor request.applicationTemplateId
        maybeTarget <- query @RosterWeek
            |> filterWhere (#id, request.applicationTargetWeekId)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
        case (maybeSaved, maybeTarget) of
            (Nothing, _) -> pure (Left RosterTemplateApplicationNotFound)
            (_, Nothing) -> pure (Left RosterTemplateApplicationNotFound)
            (Just saved, Just targetWeek)
                | targetWeek.venueId /= unpackId (rosterTemplateActorVenueId actor)
                    || targetWeek.rosterGroupId /= saved.savedTemplate.rosterGroupId ->
                    pure (Left RosterTemplateApplicationScopeMismatch)
                | not (requestMatchesScale saved.savedTemplate.scale request.applicationTargetDayOffset) ->
                    pure (Left RosterTemplateApplicationScaleMismatch)
                | otherwise -> do
                    targetHasPublishedDay <- fetchRosterWeekHasPublishedDay targetWeek
                    if targetHasPublishedDay
                        then pure (Left RosterTemplateApplicationTargetLive)
                        else prepareContent request saved (targetWeek |> set #isLive False)

requestMatchesScale :: RosterTemplateScaleEnum -> Maybe Int -> Bool
requestMatchesScale Day (Just dayOffset) = dayOffset >= 0 && dayOffset <= 6
requestMatchesScale Day Nothing          = False
requestMatchesScale Week (Just _)        = False
requestMatchesScale Week Nothing         = True

templateStructureError :: RosterTemplateScaleEnum -> [RosterTemplateDay] -> Maybe Text
templateStructureError Day days
    | map (.dayIndex) days /= [0] = Just "Day templates must contain day zero."
    | otherwise = Nothing
templateStructureError Week days
    | map (.dayIndex) days /= [0 .. 6] = Just "Week templates must contain all seven days."
    | otherwise = Nothing

prepareContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSaved ->
    RosterWeek ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareContent request saved targetWeek =
    case templateStructureError saved.savedTemplate.scale saved.savedDays of
        Just message -> pure (Left (RosterTemplateApplicationInvalidStructure message))
        Nothing -> prepareStructurallyValidContent request saved targetWeek

prepareStructurallyValidContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSaved ->
    RosterWeek ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareStructurallyValidContent request saved targetWeek = do
        allTargetDays <-
            query @RosterDay
                |> filterWhere (#rosterWeekId, Just (unpackId targetWeek.id))
                |> orderByAsc #dayOffset
                |> fetch
        let targetDays = case request.applicationTargetDayOffset of
                Just dayOffset -> filter ((== dayOffset) . (.dayOffset)) allTargetDays
                Nothing        -> allTargetDays
        case targetDays of
            [] -> pure (Left RosterTemplateApplicationInvalidTargetDay)
            firstTargetDay : _
                | rosterTemplateScaleIsWeek saved.savedTemplate.scale && map (.dayOffset) targetDays /= [0 .. 6] ->
                    pure (Left RosterTemplateApplicationInvalidTargetDay)
                | otherwise -> do
                    let targetDayByTemplateIndex = case request.applicationTargetDayOffset of
                            Just _  -> Map.fromList [(0, firstTargetDay)]
                            Nothing -> Map.fromList [(day.dayOffset, day) | day <- targetDays]
                    let templateDayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- saved.savedDays]
                    let templateColumnById = Map.fromList [(unpackId column.id, column) | column <- saved.savedColumns]
                    venueConfig <- query @VenueConfig |> filterWhere (#venueId, targetWeek.venueId) |> fetchOne
                    let shiftPlans = traverse (prepareShift venueConfig targetWeek targetDayByTemplateIndex templateDayIndexById templateColumnById request.applicationOccurrenceSelections) saved.savedShifts
                    case shiftPlans of
                        Left failure -> pure (Left failure)
                        Right boundaryPlans -> do
                            invalidShiftTypes <- findInvalidShiftTypes targetWeek boundaryPlans
                            if not (null invalidShiftTypes)
                                then pure (Left (RosterTemplateApplicationInvalidShiftTypes invalidShiftTypes))
                                else do
                                    plans <- validateAssignments targetWeek boundaryPlans
                                    existingSlots <-
                                        query @RosterSlot
                                            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                                            |> filterWhere (#deletedAt, Nothing)
                                            |> orderByAsc #id
                                            |> fetch
                                    targetDefinitions <-
                                        query @RosterWeekSlotDefinition
                                            |> filterWhere (#rosterWeekId, unpackId targetWeek.id)
                                            |> filterWhere (#deletedAt, Nothing)
                                            |> orderByAsc #id
                                            |> fetch
                                    timesheetEntries <- if null existingSlots
                                        then pure []
                                        else query @TimesheetEntry
                                            |> filterWhereIn (#sourceRosterSlotId, map (Just . unpackId . (.id)) existingSlots)
                                            |> filterWhere (#deletedAt, Nothing)
                                            |> orderByAsc #id
                                            |> fetch
                                    pure (Right PreparedApplication
                                        { preparedSaved = saved
                                        , preparedTargetWeek = targetWeek
                                        , preparedTargetDays = targetDays
                                        , preparedFirstTargetDay = firstTargetDay
                                        , preparedShiftPlans = plans
                                        , preparedExistingSlots = existingSlots
                                        , preparedTargetDefinitions = targetDefinitions
                                        , preparedTimesheetEntries = timesheetEntries
                                        , preparedCalendarRevision = venueConfig.rosterCalendarRevision
                                        })

prepareShift ::
    VenueConfig ->
    RosterWeek ->
    Map.Map Int RosterDay ->
    Map.Map UUID Int ->
    Map.Map UUID RosterTemplateColumn ->
    ShiftCopyOccurrenceSelections ->
    RosterTemplateShift ->
    Either RosterTemplateApplicationError PreparedShift
prepareShift venueConfig targetWeek targetDayByTemplateIndex templateDayIndexById templateColumnById selections shift = do
    templateDayIndex <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateDayId templateDayIndexById)
    targetDay <- maybe invalidStructure Right (Map.lookup templateDayIndex targetDayByTemplateIndex)
    templateColumn <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateColumnId templateColumnById)
    assignment <- case (shift.assignmentState, shift.staffId) of
        ("staff", Just staffId) -> Right (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Right OpenAssignment
        _                       -> invalidStructure
    let rosterDate = addDays (toInteger targetDay.dayOffset) (venueWeekStartDate venueConfig targetWeek.weekOffset)
    startsAt <- resolveTemplateMinute shift.id RosterTemplateApplicationStartBoundary venueConfig.timezone rosterDate shift.startMinute selections.copyShiftStartOccurrence
    endsAt <- resolveTemplateMinute shift.id RosterTemplateApplicationEndBoundary venueConfig.timezone rosterDate shift.endMinute selections.copyShiftEndOccurrence
    _ <- either (Left . RosterTemplateApplicationBoundaryError shift.id RosterTemplateApplicationEndBoundary) Right (authoritativeBoundariesFromInstants venueConfig.timezone startsAt endsAt Nothing Nothing)
    pure PreparedShift
        { preparedTemplateShift = shift
        , preparedTemplateColumn = templateColumn
        , preparedTargetDay = targetDay
        , preparedStartsAt = startsAt
        , preparedEndsAt = endsAt
        , preparedAssignment = assignment
        , preparedAssignmentIssue = Nothing
        }
  where
    invalidStructure = Left (RosterTemplateApplicationInvalidStructure "Template shift references are incomplete.")

findInvalidShiftTypes ::
    (?modelContext :: ModelContext) =>
    RosterWeek ->
    [PreparedShift] ->
    IO [Id ShiftType]
findInvalidShiftTypes targetWeek plans = do
    let shiftTypeIds = nub [Id plan.preparedTemplateShift.shiftTypeId :: Id ShiftType | plan <- plans]
    available <- if null shiftTypeIds
        then pure []
        else query @ShiftType
            |> filterWhereIn (#id, shiftTypeIds)
            |> filterWhere (#venueId, targetWeek.venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let availableIds = map (.id) available
    pure (filter (`notElem` availableIds) shiftTypeIds)

validateAssignments ::
    (?modelContext :: ModelContext) =>
    RosterWeek ->
    [PreparedShift] ->
    IO [PreparedShift]
validateAssignments targetWeek = traverse validateAssignment
  where
    validateAssignment plan = case plan.preparedAssignment of
        OpenAssignment -> pure plan
        StaffAssignment staffId -> do
            maybeStaff <- query @Staff |> filterWhere (#id, staffId) |> fetchOneOrNothing
            case maybeStaff of
                Nothing -> pure (convertToOpen RosterTemplateStaffUnavailable plan)
                Just staff
                    | staff.venueId /= targetWeek.venueId
                        || not staff.isActive
                        || isJust staff.archivedAt ->
                        pure (convertToOpen RosterTemplateStaffUnavailable plan)
                    | otherwise -> do
                        assignedToGroup <- query @StaffRosterGroup
                            |> filterWhere (#staffId, unpackId staffId)
                            |> filterWhere (#rosterGroupId, targetWeek.rosterGroupId)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetchExists
                        if not assignedToGroup
                            then pure (convertToOpen RosterTemplateStaffOutsideGroup plan)
                            else do
                                let candidate =
                                        newRecord @RosterSlot
                                            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
                                            |> set #rosterWeekSlotDefinitionId Nothing
                                            |> set #slotSortOrder plan.preparedTemplateColumn.sortOrder
                                            |> set #rowIndex plan.preparedTemplateShift.rowIndex
                                            |> set #startsAt (Just plan.preparedStartsAt)
                                            |> set #endsAt (Just plan.preparedEndsAt)
                                            |> set #timezone melbourneTimeZoneName
                                            |> set #shiftTypeId (Just plan.preparedTemplateShift.shiftTypeId)
                                            |> applyRosterShiftAssignment (StaffAssignment staffId)
                                payError <- validateRosterSlotForPersistence (Id targetWeek.venueId) candidate
                                pure (maybe plan (const (convertToOpen RosterTemplateStaffPayInvalid plan)) payError)

    convertToOpen issue plan =
        plan
            { preparedAssignment = OpenAssignment
            , preparedAssignmentIssue = Just issue
            }

resolveTemplateMinute ::
    Id RosterTemplateShift ->
    RosterTemplateApplicationBoundary ->
    Text ->
    Day ->
    Int ->
    Maybe RepeatedTimeOccurrence ->
    Either RosterTemplateApplicationError UTCTime
resolveTemplateMinute shiftId boundary timezone rosterDate minute occurrence =
    either (Left . RosterTemplateApplicationBoundaryError shiftId boundary) Right
        (resolveBoundaryInstant timezone targetDate timeOfDay applicableOccurrence)
  where
    (dayDelta, minuteOfDay) = minute `divMod` 1440
    (hour, minuteWithinHour) = minuteOfDay `divMod` 60
    targetDate = addDays (toInteger dayDelta) rosterDate
    timeOfDay = TimeOfDay hour minuteWithinHour 0
    applicableOccurrence
        | civilBoundaryIsRepeated targetDate timeOfDay = occurrence
        | otherwise = Nothing

toPreview :: PreparedApplication -> RosterTemplateApplicationPreview
toPreview prepared =
    RosterTemplateApplicationPreview
        { applicationPreviewTemplateName = prepared.preparedSaved.savedTemplate.name
        , applicationPreviewScale = prepared.preparedSaved.savedTemplate.scale
        , applicationPreviewTargetWeekOffset = prepared.preparedTargetWeek.weekOffset
        , applicationPreviewTargetAnchorDate = minimum (map (.operationalDate) prepared.preparedTargetDays)
        , applicationPreviewTargetDayOffset = case prepared.preparedSaved.savedTemplate.scale of
            Day  -> Just prepared.preparedFirstTargetDay.dayOffset
            Week -> Nothing
        , applicationExpectedVersion = prepared.preparedSaved.savedTemplate.currentVersion
        , applicationExpectedTargetRevision = targetRevision prepared
        , applicationRosterCalendarRevision = prepared.preparedCalendarRevision
        , applicationReplacementShiftCount = length prepared.preparedShiftPlans
        , applicationExistingShiftCount = length prepared.preparedExistingSlots
        , applicationResolvedShifts = map resolvedShift prepared.preparedShiftPlans
        , applicationWarnings = destructiveWarning : assignmentWarnings <> timesheetWarnings
        , applicationTouchedResources = touchedResources prepared
        }
  where
    resolvedShift plan = RosterTemplateApplicationResolvedShift
        { resolvedTemplateShiftId = plan.preparedTemplateShift.id
        , resolvedTargetDayOffset = plan.preparedTargetDay.dayOffset
        , resolvedStartsAt = plan.preparedStartsAt
        , resolvedEndsAt = plan.preparedEndsAt
        , resolvedAssignment = plan.preparedAssignment
        }
    assignmentWarnings =
        [ RosterTemplateApplicationAssignmentConvertedToOpen plan.preparedTemplateShift.id issue
        | plan <- prepared.preparedShiftPlans
        , Just issue <- [plan.preparedAssignmentIssue]
        ]
    destructiveWarning = case prepared.preparedSaved.savedTemplate.scale of
        Day -> RosterTemplateApplicationClearsDay prepared.preparedFirstTargetDay.dayOffset
        Week -> RosterTemplateApplicationClearsWeek
    timesheetWarnings =
        [RosterTemplateApplicationExistingTimesheetsRemain (length prepared.preparedTimesheetEntries) | not (null prepared.preparedTimesheetEntries)]

targetRevision :: PreparedApplication -> Text
targetRevision prepared =
    tshow (Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256)
  where
    targetWeek = prepared.preparedTargetWeek
    payload = Text.intercalate "|"
        [ tshow (targetWeek.id, targetWeek.updatedAt, targetWeek.isLive, targetWeek.archivedAt)
        , tshow
            [ (day.id, day.dayOffset, day.isClosed, day.rowCount, day.updatedAt)
            | day <- prepared.preparedTargetDays
            ]
        , tshow
            [ (definition.id, definition.name, definition.sortOrder, definition.updatedAt)
            | definition <- prepared.preparedTargetDefinitions
            ]
        , tshow
            [ ( slot.id
              , slot.rosterDayId
              , slot.assignmentState
              , slot.staffId
              , slot.rosterWeekSlotDefinitionId
              , slot.slotSortOrder
              , slot.rowIndex
              , slot.startsAt
              , slot.endsAt
              , slot.shiftTypeId
              , slot.updatedAt
              )
            | slot <- prepared.preparedExistingSlots
            ]
        , tshow
            [ (entry.id, entry.sourceRosterSlotId, entry.updatedAt)
            | entry <- prepared.preparedTimesheetEntries
            ]
        ]

touchedResources :: PreparedApplication -> [SurfaceResourceValue]
touchedResources prepared =
    [ rosterWeekResource groupId windowStart windowEnd
    , rosterWeekStructureResource groupId windowStart windowEnd
    , rosterSlotsStructureResource groupId windowStart windowEnd
    , rosterSlotsContentResource groupId windowStart windowEnd
    , timesheetWeekResource prepared.preparedTargetWeek.venueId windowStart windowEnd
    ] <> templateResources
  where
    templateResources
        | any (isJust . (.preparedAssignmentIssue)) prepared.preparedShiftPlans =
            [ rosterTemplateResource (unpackId prepared.preparedSaved.savedTemplate.id)
            , rosterTemplateLibraryResource groupId
            ]
        | otherwise = []
    groupId = prepared.preparedTargetWeek.rosterGroupId
    windowStart = minimum (map (.operationalDate) prepared.preparedTargetDays)
    windowEnd = addDays 7 windowStart
