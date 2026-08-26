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
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterPublication (rosterDaysArePublished)
import Application.RosterPublication.Mutations (withRosterWindowDateLockInCurrentTransaction)
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
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude (isHtmxRequest)
import Web.RosterWeeks.Service (validateRosterSlotForPersistence)
import Web.RosterWeeks.TemplateApplication.Persistence (applyPreparedApplication)
import Web.RosterWeeks.TemplateApplication.Types
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

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
    applied <-
        withDurableLiveMutationOutcome publicationFor do
            fmap (fmap (\result -> liveMutationResult result result.appliedTouchedResources)) $
                applyRosterTemplateApplicationInCurrentTransaction actor request expectedVersion expectedTargetRevision expectedCalendarRevision
    case applied of
        Left RosterTemplateApplicationCalendarConflict
            | isHtmxRequest -> do
                respondAndExit
                    ( Wai.responseLBS
                        status409
                        [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                        "The roster calendar changed. Review the refreshed window and try again."
                    )
                error "unreachable"
        _ -> pure applied
  where
    publicationFor = either (const Nothing) (\result -> Just ("roster.template.apply", result.liveMutationTouchedResources))

applyRosterTemplateApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Int ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplication actor request expectedVersion expectedTargetRevision expectedCalendarRevision =
    withTransaction $
        applyRosterTemplateApplicationInCurrentTransaction actor request expectedVersion expectedTargetRevision expectedCalendarRevision

applyRosterTemplateApplicationInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateApplicationRequest ->
    Int ->
    Text ->
    Int ->
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplicationInCurrentTransaction actor request expectedVersion expectedTargetRevision expectedCalendarRevision =
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
                request.applicationTargetOperationalDate
            preparedResult <- prepareRosterTemplateApplication actor request
            case preparedResult of
                Left failure -> pure (Left failure)
                Right prepared
                    | prepared.preparedCalendarRevision /= expectedCalendarRevision -> pure (Left RosterTemplateApplicationCalendarConflict)
                    | prepared.preparedSaved.savedTemplate.currentVersion /= expectedVersion -> pure (Left (RosterTemplateApplicationVersionConflict prepared.preparedSaved.savedTemplate.currentVersion))
                    | targetRevision prepared /= expectedTargetRevision -> pure (Left RosterTemplateApplicationTargetConflict)
                    | otherwise -> do
                        appliedVersion <- applyPreparedApplication actor prepared
                        let preview = toPreview prepared
                        pure (Right RosterTemplateApplicationResult
                            { appliedTargetWindowStart = prepared.preparedTargetWindowStart
                            , appliedTargetWindowEnd = prepared.preparedTargetWindowEnd
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
                | targetGroup.id /= Id saved.savedTemplate.rosterGroupId -> pure (Left RosterTemplateApplicationScopeMismatch)
                | not (requestMatchesScale saved.savedTemplate.scale request.applicationTargetOperationalDate) -> pure (Left RosterTemplateApplicationScaleMismatch)
                | otherwise -> prepareContent request saved targetGroup

requestMatchesScale :: RosterTemplateScaleEnum -> Maybe Day -> Bool
requestMatchesScale Day (Just _)  = True
requestMatchesScale Day Nothing   = False
requestMatchesScale Week (Just _) = False
requestMatchesScale Week Nothing  = True

templateStructureError :: RosterTemplateScaleEnum -> [RosterTemplateDay] -> Maybe Text
templateStructureError Day days
    | map (\day -> (day.dayIndex, day.weekdayIndex)) days /= [(0, Nothing)] = Just "Day templates must contain target-relative day zero."
    | otherwise = Nothing
templateStructureError Week days
    | sort (mapMaybe (.weekdayIndex) days) /= [0 .. 6] = Just "Week templates must contain all seven weekdays."
    | otherwise = Nothing

prepareContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSaved ->
    RosterGroup ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareContent request saved targetGroup =
    case templateStructureError saved.savedTemplate.scale saved.savedDays of
        Just message -> pure (Left (RosterTemplateApplicationInvalidStructure message))
        Nothing -> prepareStructurallyValidContent request saved targetGroup

prepareStructurallyValidContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateApplicationRequest ->
    RosterTemplateSaved ->
    RosterGroup ->
    IO (Either RosterTemplateApplicationError PreparedApplication)
prepareStructurallyValidContent request saved targetGroup = do
    allTargetDays <- query @RosterDay
        |> filterWhere (#venueId, targetGroup.venueId)
        |> filterWhere (#rosterGroupId, unpackId targetGroup.id)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, request.applicationTargetWindowStart)
        |> filterWhereLessThan (#operationalDate, request.applicationTargetWindowEnd)
        |> orderByAsc #operationalDate
        |> fetch
    let targetDays = case request.applicationTargetOperationalDate of
            Just operationalDate -> filter ((== operationalDate) . (.operationalDate)) allTargetDays
            Nothing -> allTargetDays
    if any ((== Published) . (.publicationState)) allTargetDays
        then pure (Left RosterTemplateApplicationTargetLive)
        else case targetDays of
            [] -> pure (Left RosterTemplateApplicationInvalidTargetDay)
            firstTargetDay : _
                | rosterTemplateScaleIsWeek saved.savedTemplate.scale
                    && map (.operationalDate) targetDays /= map (`addDays` request.applicationTargetWindowStart) [0 .. 6] ->
                        pure (Left RosterTemplateApplicationInvalidTargetDay)
                | otherwise -> do
                    let targetDayByTemplateIndex = case request.applicationTargetOperationalDate of
                            Just _  -> Map.fromList [(0, firstTargetDay)]
                            Nothing -> Map.fromList [(weekdayIndexForDay day.operationalDate, day) | day <- targetDays]
                    let templateDayIndexById = Map.fromList
                            [ (unpackId day.id, fromMaybe day.dayIndex day.weekdayIndex)
                            | day <- saved.savedDays
                            ]
                    let templateColumnById = Map.fromList [(unpackId column.id, column) | column <- saved.savedColumns]
                    venueConfig <- query @VenueConfig |> filterWhere (#venueId, targetGroup.venueId) |> fetchOne
                    let shiftPlans = traverse (prepareShift venueConfig targetDayByTemplateIndex templateDayIndexById templateColumnById request.applicationOccurrenceSelections) saved.savedShifts
                    case shiftPlans of
                        Left failure -> pure (Left failure)
                        Right boundaryPlans -> do
                            invalidShiftTypes <- findInvalidShiftTypes targetGroup boundaryPlans
                            if not (null invalidShiftTypes)
                                then pure (Left (RosterTemplateApplicationInvalidShiftTypes invalidShiftTypes))
                                else do
                                    plans <- validateAssignments targetGroup boundaryPlans
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
                                    pure (Right PreparedApplication
                                        { preparedSaved = saved
                                        , preparedTargetGroup = targetGroup
                                        , preparedTargetWindowStart = request.applicationTargetWindowStart
                                        , preparedTargetWindowEnd = request.applicationTargetWindowEnd
                                        , preparedTargetDays = targetDays
                                        , preparedFirstTargetDay = firstTargetDay
                                        , preparedShiftPlans = plans
                                        , preparedExistingSlots = existingSlots
                                        , preparedTargetLanes = targetLanes
                                        , preparedTimesheetEntries = timesheetEntries
                                        , preparedCalendarRevision = venueConfig.rosterCalendarRevision
                                        })

prepareShift ::
    VenueConfig ->
    Map.Map Int RosterDay ->
    Map.Map UUID Int ->
    Map.Map UUID RosterTemplateColumn ->
    ShiftCopyOccurrenceSelections ->
    RosterTemplateShift ->
    Either RosterTemplateApplicationError PreparedShift
prepareShift venueConfig targetDayByTemplateIndex templateDayIndexById templateColumnById selections shift = do
    templateDayIndex <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateDayId templateDayIndexById)
    targetDay <- maybe invalidStructure Right (Map.lookup templateDayIndex targetDayByTemplateIndex)
    templateColumn <- maybe invalidStructure Right (Map.lookup shift.rosterTemplateColumnId templateColumnById)
    assignment <- case (shift.assignmentState, shift.staffId) of
        ("staff", Just staffId) -> Right (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Right OpenAssignment
        _                       -> invalidStructure
    let rosterDate = targetDay.operationalDate
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
    RosterGroup ->
    [PreparedShift] ->
    IO [Id ShiftType]
findInvalidShiftTypes targetGroup plans = do
    let shiftTypeIds = nub [Id plan.preparedTemplateShift.shiftTypeId :: Id ShiftType | plan <- plans]
    available <- if null shiftTypeIds
        then pure []
        else query @ShiftType
            |> filterWhereIn (#id, shiftTypeIds)
            |> filterWhere (#venueId, targetGroup.venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let availableIds = map (.id) available
    pure (filter (`notElem` availableIds) shiftTypeIds)

validateAssignments ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    [PreparedShift] ->
    IO [PreparedShift]
validateAssignments targetGroup = traverse validateAssignment
  where
    validateAssignment plan = case plan.preparedAssignment of
        OpenAssignment -> pure plan
        StaffAssignment staffId -> do
            maybeStaff <- query @Staff |> filterWhere (#id, staffId) |> fetchOneOrNothing
            case maybeStaff of
                Nothing -> pure (convertToOpen RosterTemplateStaffUnavailable plan)
                Just staff
                    | staff.venueId /= targetGroup.venueId
                        || not staff.isActive
                        || isJust staff.archivedAt ->
                        pure (convertToOpen RosterTemplateStaffUnavailable plan)
                    | otherwise -> do
                        assignedToGroup <- query @StaffRosterGroup
                            |> filterWhere (#staffId, unpackId staffId)
                            |> filterWhere (#rosterGroupId, unpackId targetGroup.id)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetchExists
                        if not assignedToGroup
                            then pure (convertToOpen RosterTemplateStaffOutsideGroup plan)
                            else do
                                let candidate =
                                        newRecord @RosterSlot
                                            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
                                            |> set #slotSortOrder plan.preparedTemplateColumn.sortOrder
                                            |> set #rowIndex plan.preparedTemplateShift.rowIndex
                                            |> set #startsAt (Just plan.preparedStartsAt)
                                            |> set #endsAt (Just plan.preparedEndsAt)
                                            |> set #timezone melbourneTimeZoneName
                                            |> set #shiftTypeId (Just plan.preparedTemplateShift.shiftTypeId)
                                            |> applyRosterShiftAssignment (StaffAssignment staffId)
                                payError <- validateRosterSlotForPersistence (Id targetGroup.venueId) candidate
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
        , applicationPreviewTargetWindowStart = prepared.preparedTargetWindowStart
        , applicationPreviewTargetWindowEnd = prepared.preparedTargetWindowEnd
        , applicationPreviewTargetOperationalDate = case prepared.preparedSaved.savedTemplate.scale of
            Day  -> Just prepared.preparedFirstTargetDay.operationalDate
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
        , resolvedTargetDayOffset = fromInteger (diffDays plan.preparedTargetDay.operationalDate prepared.preparedTargetWindowStart)
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
        Day -> RosterTemplateApplicationClearsDay (fromInteger (diffDays prepared.preparedFirstTargetDay.operationalDate prepared.preparedTargetWindowStart))
        Week -> RosterTemplateApplicationClearsWeek
    timesheetWarnings =
        [RosterTemplateApplicationExistingTimesheetsRemain (length prepared.preparedTimesheetEntries) | not (null prepared.preparedTimesheetEntries)]

targetRevision :: PreparedApplication -> Text
targetRevision prepared =
    tshow (Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256)
  where
    payload = Text.intercalate "|"
        [ tshow (prepared.preparedTargetGroup.id, prepared.preparedTargetWindowStart, prepared.preparedTargetWindowEnd)
        , tshow
            [ (day.id, day.operationalDate, day.publicationState, day.isClosed, day.rowCount, day.updatedAt)
            | day <- prepared.preparedTargetDays
            ]
        , tshow
            [ (lane.id, lane.rosterDayId, lane.name, lane.sortOrder, lane.updatedAt)
            | lane <- prepared.preparedTargetLanes
            ]
        , tshow
            [ ( slot.id
              , slot.rosterDayId
              , slot.assignmentState
              , slot.staffId
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
    , timesheetWeekResource prepared.preparedTargetGroup.venueId windowStart windowEnd
    ] <> templateResources
  where
    templateResources
        | any (isJust . (.preparedAssignmentIssue)) prepared.preparedShiftPlans =
            [ rosterTemplateResource (unpackId prepared.preparedSaved.savedTemplate.id)
            , rosterTemplateLibraryResource groupId
            ]
        | otherwise = []
    groupId = unpackId prepared.preparedTargetGroup.id
    windowStart = prepared.preparedTargetWindowStart
    windowEnd = prepared.preparedTargetWindowEnd
