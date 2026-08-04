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
    , previewRosterTemplateApplication
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateApplicationRows)
import Application.VenueTime (RepeatedTimeOccurrence, melbourneTimeZoneName)
import Application.VenueTime.Model
import Control.Monad (void)
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

previewRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationPreview)
previewRosterTemplateApplication actor request = do
    prepared <- prepareRosterTemplateApplication actor request
    pure (toPreview <$> prepared)

applyRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Int ->
    Text ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplication actor request expectedVersion expectedTargetRevision =
    withTransaction do
        lockRosterTemplateApplicationRows request.applicationTemplateId request.applicationTargetWeekId request.applicationTargetDayOffset
        preparedResult <- prepareRosterTemplateApplication actor request
        case preparedResult of
            Left failure -> pure (Left failure)
            Right prepared
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
                | targetWeek.isLive -> pure (Left RosterTemplateApplicationTargetLive)
                | not (requestMatchesScale saved.savedTemplate.scale request.applicationTargetDayOffset) ->
                    pure (Left RosterTemplateApplicationScaleMismatch)
                | otherwise -> prepareContent request saved targetWeek

requestMatchesScale :: RosterTemplateScaleEnum -> Maybe Int -> Bool
requestMatchesScale Day (Just dayOffset) = dayOffset >= 0 && dayOffset <= 6
requestMatchesScale Week Nothing         = True
requestMatchesScale _ _                  = False

prepareContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSaved ->
    RosterWeek ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareContent request saved targetWeek
    | saved.savedTemplate.scale == Day && map (.dayIndex) saved.savedDays /= [0] =
        pure (Left (RosterTemplateApplicationInvalidStructure "Day templates must contain day zero."))
    | saved.savedTemplate.scale == Week && map (.dayIndex) saved.savedDays /= [0 .. 6] =
        pure (Left (RosterTemplateApplicationInvalidStructure "Week templates must contain all seven days."))
    | otherwise = do
        allTargetDays <-
            query @RosterDay
                |> filterWhere (#rosterWeekId, unpackId targetWeek.id)
                |> orderByAsc #dayOffset
                |> fetch
        let targetDays = case request.applicationTargetDayOffset of
                Just dayOffset -> filter ((== dayOffset) . (.dayOffset)) allTargetDays
                Nothing        -> allTargetDays
        case targetDays of
            [] -> pure (Left RosterTemplateApplicationInvalidTargetDay)
            firstTargetDay : _
                | saved.savedTemplate.scale == Week && map (.dayOffset) targetDays /= [0 .. 6] ->
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
                                            |> set #rosterWeekSlotDefinitionId UUID.nil
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
        , applicationPreviewTargetDayOffset = case prepared.preparedSaved.savedTemplate.scale of
            Day  -> Just prepared.preparedFirstTargetDay.dayOffset
            Week -> Nothing
        , applicationExpectedVersion = prepared.preparedSaved.savedTemplate.currentVersion
        , applicationExpectedTargetRevision = targetRevision prepared
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
    [ rosterWeekResource groupId weekOffset
    , rosterWeekStructureResource groupId weekOffset
    , rosterSlotsStructureResource groupId weekOffset
    , rosterSlotsContentResource groupId weekOffset
    , timesheetWeekResource prepared.preparedTargetWeek.venueId weekOffset
    ] <> templateResources
  where
    templateResources
        | any (isJust . (.preparedAssignmentIssue)) prepared.preparedShiftPlans =
            [ rosterTemplateResource (unpackId prepared.preparedSaved.savedTemplate.id)
            , rosterTemplateLibraryResource groupId
            ]
        | otherwise = []
    groupId = prepared.preparedTargetWeek.rosterGroupId
    weekOffset = prepared.preparedTargetWeek.weekOffset
