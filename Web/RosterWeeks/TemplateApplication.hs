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
import Application.VenueTime (RepeatedTimeOccurrence, melbourneTimeZoneName)
import Application.VenueTime.Model
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import Web.RosterWeeks.Service (validateRosterSlotForPersistence)

data RosterTemplateApplicationRequest = RosterTemplateApplicationRequest
    { applicationTemplateId           :: !(Id RosterTemplate)
    , applicationTargetWeekId         :: !(Id RosterWeek)
    , applicationTargetDayOffset      :: !(Maybe Int)
    , applicationOccurrenceSelections :: !ShiftCopyOccurrenceSelections
    }
    deriving (Eq, Show)

data RosterTemplateApplicationAssignmentIssue
    = RosterTemplateStaffUnavailable
    | RosterTemplateStaffOutsideGroup
    | RosterTemplateStaffPayInvalid
    deriving (Eq, Show)

data RosterTemplateApplicationWarning
    = RosterTemplateApplicationClearsDay !Int
    | RosterTemplateApplicationClearsWeek
    | RosterTemplateApplicationExistingTimesheetsRemain !Int
    | RosterTemplateApplicationAssignmentConvertedToOpen !(Id RosterTemplateShift) !RosterTemplateApplicationAssignmentIssue
    deriving (Eq, Show)

data RosterTemplateApplicationResolvedShift = RosterTemplateApplicationResolvedShift
    { resolvedTemplateShiftId :: !(Id RosterTemplateShift)
    , resolvedTargetDayOffset :: !Int
    , resolvedStartsAt        :: !UTCTime
    , resolvedEndsAt          :: !UTCTime
    , resolvedAssignment      :: !RosterShiftAssignment
    }
    deriving (Eq, Show)

data RosterTemplateApplicationPreview = RosterTemplateApplicationPreview
    { applicationPreviewTemplateName    :: !Text
    , applicationPreviewScale           :: !RosterTemplateScaleEnum
    , applicationPreviewTargetWeekOffset :: !Int
    , applicationPreviewTargetDayOffset :: !(Maybe Int)
    , applicationExpectedVersion        :: !Int
    , applicationReplacementShiftCount :: !Int
    , applicationExistingShiftCount    :: !Int
    , applicationResolvedShifts        :: ![RosterTemplateApplicationResolvedShift]
    , applicationWarnings              :: ![RosterTemplateApplicationWarning]
    , applicationTouchedResources      :: ![SurfaceResourceValue]
    }
    deriving (Eq, Show)

data RosterTemplateApplicationResult = RosterTemplateApplicationResult
    { appliedRosterWeek       :: !RosterWeek
    , appliedTemplateVersion  :: !Int
    , appliedWarnings         :: ![RosterTemplateApplicationWarning]
    , appliedTouchedResources :: ![SurfaceResourceValue]
    }
    deriving (Eq, Show)

data RosterTemplateApplicationBoundary
    = RosterTemplateApplicationStartBoundary
    | RosterTemplateApplicationEndBoundary
    deriving (Eq, Show)

data RosterTemplateApplicationError
    = RosterTemplateApplicationForbidden
    | RosterTemplateApplicationNotFound
    | RosterTemplateApplicationScopeMismatch
    | RosterTemplateApplicationTargetLive
    | RosterTemplateApplicationInvalidTargetDay
    | RosterTemplateApplicationScaleMismatch
    | RosterTemplateApplicationVersionConflict !Int
    | RosterTemplateApplicationInvalidShiftTypes ![Id ShiftType]
    | RosterTemplateApplicationBoundaryError !(Id RosterTemplateShift) !RosterTemplateApplicationBoundary !BoundaryModelError
    | RosterTemplateApplicationInvalidStructure !Text
    deriving (Eq, Show)

data PreparedApplication = PreparedApplication
    { preparedSaved          :: !RosterTemplateSaved
    , preparedTargetWeek     :: !RosterWeek
    , preparedTargetDays     :: ![RosterDay]
    , preparedShiftPlans     :: ![PreparedShift]
    , preparedExistingSlots  :: ![RosterSlot]
    , preparedTimesheetCount :: !Int
    }

data PreparedShift = PreparedShift
    { preparedTemplateShift :: !RosterTemplateShift
    , preparedTemplateColumn :: !RosterTemplateColumn
    , preparedTargetDay      :: !RosterDay
    , preparedStartsAt       :: !UTCTime
    , preparedEndsAt         :: !UTCTime
    , preparedAssignment     :: !RosterShiftAssignment
    , preparedAssignmentIssue :: !(Maybe RosterTemplateApplicationAssignmentIssue)
    }

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
    IO (Either RosterTemplateApplicationError RosterTemplateApplicationResult)
applyRosterTemplateApplication actor request expectedVersion =
    withTransaction do
        lockApplicationRows request
        preparedResult <- prepareRosterTemplateApplication actor request
        case preparedResult of
            Left failure -> pure (Left failure)
            Right prepared
                | prepared.preparedSaved.savedTemplate.currentVersion /= expectedVersion ->
                    pure (Left (RosterTemplateApplicationVersionConflict prepared.preparedSaved.savedTemplate.currentVersion))
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
        if null targetDays || (saved.savedTemplate.scale == Week && map (.dayOffset) targetDays /= [0 .. 6])
            then pure (Left RosterTemplateApplicationInvalidTargetDay)
            else do
                let targetDayByTemplateIndex = case request.applicationTargetDayOffset of
                        Just _  -> Map.fromList [(0, targetDays !! 0)]
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
                                        |> fetch
                                timesheetCount <- if null existingSlots
                                    then pure 0
                                    else query @TimesheetEntry
                                        |> filterWhereIn (#sourceRosterSlotId, map (Just . unpackId . (.id)) existingSlots)
                                        |> filterWhere (#deletedAt, Nothing)
                                        |> fetchCount
                                pure (Right PreparedApplication
                                    { preparedSaved = saved
                                    , preparedTargetWeek = targetWeek
                                    , preparedTargetDays = targetDays
                                    , preparedShiftPlans = plans
                                    , preparedExistingSlots = existingSlots
                                    , preparedTimesheetCount = timesheetCount
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
            Day  -> Just (prepared.preparedTargetDays !! 0).dayOffset
            Week -> Nothing
        , applicationExpectedVersion = prepared.preparedSaved.savedTemplate.currentVersion
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
        Day -> RosterTemplateApplicationClearsDay (prepared.preparedTargetDays !! 0).dayOffset
        Week -> RosterTemplateApplicationClearsWeek
    timesheetWarnings =
        [RosterTemplateApplicationExistingTimesheetsRemain prepared.preparedTimesheetCount | prepared.preparedTimesheetCount > 0]

applyPreparedApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Int
applyPreparedApplication actor prepared = do
    now <- getCurrentTime
    forM_ prepared.preparedExistingSlots \slot ->
        slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId (rosterTemplateActorUserId actor)))
            |> set #deleteReason (Just "roster_template_applied")
            |> updateRecord
            |> void
    appliedVersion <- persistCleanedTemplateVersion actor prepared
    applyDayStates prepared
    definitions <- ensureTargetDefinitions prepared
    let definitionByName = Map.fromList [(Text.toCaseFold (Text.strip definition.name), definition) | definition <- definitions]
    forM_ prepared.preparedShiftPlans \plan -> do
        let definition = definitionByName Map.! Text.toCaseFold (Text.strip plan.preparedTemplateColumn.name)
        newRecord @RosterSlot
            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
            |> set #rosterWeekSlotDefinitionId (unpackId definition.id)
            |> set #slotSortOrder definition.sortOrder
            |> set #rowIndex plan.preparedTemplateShift.rowIndex
            |> set #startsAt (Just plan.preparedStartsAt)
            |> set #endsAt (Just plan.preparedEndsAt)
            |> set #timezone melbourneTimeZoneName
            |> set #shiftTypeId (Just plan.preparedTemplateShift.shiftTypeId)
            |> applyRosterShiftAssignment plan.preparedAssignment
            |> createRecord
            |> void
    pure appliedVersion

persistCleanedTemplateVersion ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Int
persistCleanedTemplateVersion actor prepared
    | not (any (isJust . (.preparedAssignmentIssue)) prepared.preparedShiftPlans) =
        pure prepared.preparedSaved.savedTemplate.currentVersion
    | otherwise = do
        let template = prepared.preparedSaved.savedTemplate
        let sourceDesign = prepared.preparedSaved.savedDesign
        let nextVersion = template.currentVersion + 1
        nextDesign <-
            newRecord @RosterTemplateDesign
                |> set #rosterGroupId sourceDesign.rosterGroupId
                |> set #scale sourceDesign.scale
                |> set #draftOwnerUserId Nothing
                |> set #draftName Nothing
                |> set #templateId (Just (unpackId template.id))
                |> set #versionNumber (Just nextVersion)
                |> set #sourceTemplateId Nothing
                |> set #baseVersionNumber Nothing
                |> set #createdByUserId (unpackId (rosterTemplateActorUserId actor))
                |> createRecord
        nextDays <- forM prepared.preparedSaved.savedDays \sourceDay ->
            newRecord @RosterTemplateDay
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #dayIndex sourceDay.dayIndex
                |> set #isClosed sourceDay.isClosed
                |> set #rowCount sourceDay.rowCount
                |> createRecord
        nextColumns <- forM prepared.preparedSaved.savedColumns \sourceColumn ->
            newRecord @RosterTemplateColumn
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #name sourceColumn.name
                |> set #sortOrder sourceColumn.sortOrder
                |> createRecord
        let nextDayByIndex = Map.fromList [(day.dayIndex, day) | day <- nextDays]
        let sourceDayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- prepared.preparedSaved.savedDays]
        let nextColumnBySort = Map.fromList [(column.sortOrder, column) | column <- nextColumns]
        let sourceColumnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- prepared.preparedSaved.savedColumns]
        let planByShiftId = Map.fromList [(unpackId plan.preparedTemplateShift.id, plan) | plan <- prepared.preparedShiftPlans]
        forM_ prepared.preparedSaved.savedShifts \sourceShift -> do
            let dayIndex = sourceDayIndexById Map.! sourceShift.rosterTemplateDayId
            let columnSort = sourceColumnSortById Map.! sourceShift.rosterTemplateColumnId
            let targetDay = nextDayByIndex Map.! dayIndex
            let targetColumn = nextColumnBySort Map.! columnSort
            let assignment = maybe OpenAssignment (.preparedAssignment) (Map.lookup (unpackId sourceShift.id) planByShiftId)
            newRecord @RosterTemplateShift
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #rosterTemplateDayId (unpackId targetDay.id)
                |> set #rosterTemplateColumnId (unpackId targetColumn.id)
                |> set #rowIndex sourceShift.rowIndex
                |> set #startMinute sourceShift.startMinute
                |> set #endMinute sourceShift.endMinute
                |> set #shiftTypeId sourceShift.shiftTypeId
                |> applyTemplateShiftAssignment assignment
                |> createRecord
                |> void
        template |> set #currentVersion nextVersion |> updateRecord |> void
        pure nextVersion

applyTemplateShiftAssignment :: RosterShiftAssignment -> RosterTemplateShift -> RosterTemplateShift
applyTemplateShiftAssignment assignment shift = case assignment of
    StaffAssignment staffId ->
        shift
            |> set #assignmentState "staff"
            |> set #staffId (Just (unpackId staffId))
    OpenAssignment ->
        shift
            |> set #assignmentState "open"
            |> set #staffId Nothing

applyDayStates :: (?modelContext :: ModelContext) => PreparedApplication -> IO ()
applyDayStates prepared = do
    let templateDayByIndex = Map.fromList [(day.dayIndex, day) | day <- prepared.preparedSaved.savedDays]
    forM_ prepared.preparedTargetDays \targetDay -> do
        let templateIndex = case prepared.preparedSaved.savedTemplate.scale of
                Day  -> 0
                Week -> targetDay.dayOffset
        case Map.lookup templateIndex templateDayByIndex of
            Nothing -> pure ()
            Just templateDay ->
                targetDay
                    |> set #isClosed templateDay.isClosed
                    |> set #rowCount templateDay.rowCount
                    |> updateRecord
                    |> void

ensureTargetDefinitions ::
    (?modelContext :: ModelContext) =>
    PreparedApplication ->
    IO [RosterWeekSlotDefinition]
ensureTargetDefinitions prepared = do
    existing <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId prepared.preparedTargetWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> fetch
    case prepared.preparedSaved.savedTemplate.scale of
        Week -> do
            now <- getCurrentTime
            forM_ existing \definition ->
                definition
                    |> set #deletedAt (Just now)
                    |> set #deleteReason (Just "roster_template_applied")
                    |> updateRecord
                    |> void
            forM prepared.preparedSaved.savedColumns \column ->
                createDefinition prepared.preparedTargetWeek column.name column.sortOrder
        Day -> do
            let existingNames = Map.fromList [(Text.toCaseFold (Text.strip definition.name), definition) | definition <- existing]
            let missing = filter (\column -> Map.notMember (Text.toCaseFold (Text.strip column.name)) existingNames) prepared.preparedSaved.savedColumns
            created <- forM (zip missing [nextSortOrder existing ..]) \(column, sortOrder) ->
                createDefinition prepared.preparedTargetWeek column.name sortOrder
            pure (existing <> created)

createDefinition :: (?modelContext :: ModelContext) => RosterWeek -> Text -> Int -> IO RosterWeekSlotDefinition
createDefinition rosterWeek name sortOrder =
    newRecord @RosterWeekSlotDefinition
        |> set #rosterWeekId (unpackId rosterWeek.id)
        |> set #name name
        |> set #sortOrder sortOrder
        |> createRecord

nextSortOrder :: [RosterWeekSlotDefinition] -> Int
nextSortOrder []          = 0
nextSortOrder definitions = maximum (map (.sortOrder) definitions) + 1

lockApplicationRows :: (?modelContext :: ModelContext) => RosterTemplateApplicationRequest -> IO ()
lockApplicationRows request = do
    _templateLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM roster_templates WHERE id = ? FOR UPDATE"
        (PG.Only (unpackId request.applicationTemplateId))
    _weekLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM roster_weeks WHERE id = ? FOR UPDATE"
        (PG.Only (unpackId request.applicationTargetWeekId))
    _shiftTypeLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT shift_types.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \JOIN shift_types ON shift_types.id = roster_template_shifts.shift_type_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY shift_types.id \
        \FOR UPDATE OF shift_types"
        (PG.Only (unpackId request.applicationTemplateId))
    _staffLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT staff.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \JOIN staff ON staff.id = roster_template_shifts.staff_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY staff.id \
        \FOR UPDATE OF staff"
        (PG.Only (unpackId request.applicationTemplateId))
    pure ()

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
