module Web.RosterWeeks.TemplateDesigner
    ( RosterTemplateDesignerMutation (..)
    , RosterTemplateReference (..)
    , RosterTemplateReferenceWeek (..)
    , fetchRosterTemplateReferenceWeek
    , mutateRosterTemplateDesignerDraft
    , startBlankRosterTemplateDesignerDraft
    , startRosterTemplateDraftFromReference
    ) where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Application.VenueTime.Model (resolveBoundaryInstant)
import Control.Monad (guard)
import Data.List (find, nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Time.Calendar (addDays, diffDays, fromGregorian)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import Web.RosterWeeks.Service (validateRosterSlotForPersistence)

startBlankRosterTemplateDesignerDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startBlankRosterTemplateDesignerDraft actor rosterGroup scale requestedName =
    startRosterTemplateDraftWithContent actor rosterGroup scale requestedName RosterTemplateContent
        { contentDays =
            [ RosterTemplateDayInput dayIndex False 1
            | dayIndex <- case scale of
                Day  -> [0]
                Week -> [0 .. 6]
            ]
        , contentColumns = [RosterTemplateColumnInput "Shift" 0]
        , contentShifts = []
        }

data RosterTemplateDesignerMutation
    = SetRosterTemplateDay !Int !Bool !Int
    | AddRosterTemplateColumn !Text
    | RenameRosterTemplateColumn !Int !Text
    | DeleteRosterTemplateColumn !Int
    | UpsertRosterTemplateShift !RosterTemplateShiftInput
    | DeleteRosterTemplateShift !Int !Int !Int
    deriving (Eq, Show)

mutateRosterTemplateDesignerDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterTemplateDesignerMutation ->
    IO (Either RosterTemplateError ())
mutateRosterTemplateDesignerDraft actor designId mutation = do
    maybeDraft <- fetchPrivateRosterTemplateDraft actor
    case maybeDraft of
        Just draft | draft.draftDesign.id == designId -> do
            let content = applyDesignerMutation mutation (draftContent draft)
            if not (rosterTemplateContentIsValid draft.draftDesign.scale content)
                then pure (Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid."))
                else do
                    references <- validateDesignerContentReferences actor draft.draftDesign content
                    case references of
                        Left templateError -> pure (Left templateError)
                        Right () -> replaceRosterTemplateDraftContent actor designId content
        _ -> pure (Left RosterTemplateForbidden)

validateDesignerContentReferences ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    RosterTemplateContent ->
    IO (Either RosterTemplateError ())
validateDesignerContentReferences actor design content = do
    let shiftTypeIds = nub (map (.inputShiftTypeId) content.contentShifts)
    validShiftTypes <- if null shiftTypeIds
        then pure []
        else query @ShiftType
            |> filterWhereIn (#id, shiftTypeIds)
            |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let validShiftTypeIds = map (.id) validShiftTypes
    let invalidShiftTypeIds = filter (`notElem` validShiftTypeIds) shiftTypeIds
    if not (null invalidShiftTypeIds)
        then pure (Left (RosterTemplateInvalidShiftTypes invalidShiftTypeIds))
        else do
            assignmentErrors <- traverse (validateDesignerShiftAssignment actor design) content.contentShifts
            pure case find isJust assignmentErrors of
                Just (Just message) -> Left (RosterTemplateInvalidContent message)
                _                   -> Right ()

validateDesignerShiftAssignment ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterTemplateDesign ->
    RosterTemplateShiftInput ->
    IO (Maybe Text)
validateDesignerShiftAssignment _ _ RosterTemplateShiftInput { inputShiftAssignment = OpenAssignment } = pure Nothing
validateDesignerShiftAssignment actor design shift@RosterTemplateShiftInput { inputShiftAssignment = StaffAssignment staffId } = do
    maybeStaff <- query @Staff
        |> filterWhere (#id, staffId)
        |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchOneOrNothing
    inGroup <- query @StaffRosterGroup
        |> filterWhere (#staffId, unpackId staffId)
        |> filterWhere (#rosterGroupId, design.rosterGroupId)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchExists
    case maybeStaff of
        Nothing -> pure (Just invalidAssignmentMessage)
        Just _ | not inGroup -> pure (Just invalidAssignmentMessage)
        Just _ -> do
            venueConfig <- query @VenueConfig
                |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
                |> fetchOne
            case designerShiftCandidate venueConfig shift of
                Nothing -> pure (Just "Choose valid start and end times.")
                Just candidate -> validateRosterSlotForPersistence (rosterTemplateActorVenueId actor) candidate
  where
    invalidAssignmentMessage = "Choose an available roster-group staff member with valid pay configuration."

designerShiftCandidate :: VenueConfig -> RosterTemplateShiftInput -> Maybe RosterSlot
designerShiftCandidate venueConfig shift = do
    startsAt <- resolveMinute shift.inputShiftStartMinute
    endsAt <- resolveMinute shift.inputShiftEndMinute
    pure $ newRecord @RosterSlot
        |> set #startsAt (Just startsAt)
        |> set #endsAt (Just endsAt)
        |> set #timezone venueConfig.timezone
        |> set #shiftTypeId (Just (unpackId shift.inputShiftTypeId))
        |> applyRosterShiftAssignment shift.inputShiftAssignment
  where
    resolveMinute minute =
        let (dayDelta, minuteOfDay) = minute `divMod` 1440
            (hour, minuteWithinHour) = minuteOfDay `divMod` 60
            date = addDays (toInteger dayDelta) (fromGregorian 2025 1 6)
         in either (const Nothing) Just (resolveBoundaryInstant venueConfig.timezone date (TimeOfDay hour minuteWithinHour 0) Nothing)

applyDesignerMutation :: RosterTemplateDesignerMutation -> RosterTemplateContent -> RosterTemplateContent
applyDesignerMutation (SetRosterTemplateDay dayIndex isClosed rowCount) content =
    content
        { contentDays =
            [ if day.inputDayIndex == dayIndex
                then day { inputDayIsClosed = isClosed, inputDayRowCount = rowCount }
                else day
            | day <- content.contentDays
            ]
        , contentShifts =
            [ shift
            | shift <- content.contentShifts
            , shift.inputShiftDayIndex /= dayIndex || (not isClosed && shift.inputShiftRowIndex < rowCount)
            ]
        }
applyDesignerMutation (AddRosterTemplateColumn requestedName) content =
    content
        { contentColumns = content.contentColumns <> [RosterTemplateColumnInput requestedName nextSortOrder]
        }
  where
    nextSortOrder = case map (.inputColumnSortOrder) content.contentColumns of
        []         -> 0
        sortOrders -> maximum sortOrders + 1
applyDesignerMutation (RenameRosterTemplateColumn sortOrder requestedName) content =
    content
        { contentColumns =
            [ if column.inputColumnSortOrder == sortOrder
                then column { inputColumnName = requestedName }
                else column
            | column <- content.contentColumns
            ]
        }
applyDesignerMutation (DeleteRosterTemplateColumn sortOrder) content =
    content
        { contentColumns = filter ((/= sortOrder) . (.inputColumnSortOrder)) content.contentColumns
        , contentShifts = filter ((/= sortOrder) . (.inputShiftColumnSortOrder)) content.contentShifts
        }
applyDesignerMutation (UpsertRosterTemplateShift shift) content =
    content
        { contentShifts = shift : filter (not . sameCell shift) content.contentShifts
        }
  where
    sameCell left right =
        (left.inputShiftDayIndex, left.inputShiftColumnSortOrder, left.inputShiftRowIndex)
            == (right.inputShiftDayIndex, right.inputShiftColumnSortOrder, right.inputShiftRowIndex)
applyDesignerMutation (DeleteRosterTemplateShift dayIndex columnSort rowIndex) content =
    content
        { contentShifts = filter (not . matchesCell) content.contentShifts
        }
  where
    matchesCell shift =
        (shift.inputShiftDayIndex, shift.inputShiftColumnSortOrder, shift.inputShiftRowIndex)
            == (dayIndex, columnSort, rowIndex)

draftContent :: RosterTemplateDraft -> RosterTemplateContent
draftContent draft = RosterTemplateContent
    { contentDays =
        [ RosterTemplateDayInput day.dayIndex day.isClosed day.rowCount
        | day <- draft.draftDays
        ]
    , contentColumns =
        [ RosterTemplateColumnInput column.name column.sortOrder
        | column <- draft.draftColumns
        ]
    , contentShifts = mapMaybe shiftInput draft.draftShifts
    }
  where
    dayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- draft.draftDays]
    columnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- draft.draftColumns]
    shiftInput shift = do
        dayIndex <- Map.lookup shift.rosterTemplateDayId dayIndexById
        columnSort <- Map.lookup shift.rosterTemplateColumnId columnSortById
        assignment <- case (shift.assignmentState, shift.staffId) of
            ("staff", Just staffId) -> Just (StaffAssignment (Id staffId))
            ("open", Nothing)       -> Just OpenAssignment
            _                       -> Nothing
        pure (RosterTemplateShiftInput dayIndex columnSort shift.rowIndex shift.startMinute shift.endMinute (Id shift.shiftTypeId) assignment)

data RosterTemplateReferenceWeek = RosterTemplateReferenceWeek
    { referenceRosterWeek  :: !(Maybe RosterWeek)
    , referenceRosterDays  :: ![RosterDay]
    , referenceColumns     :: ![RosterWeekSlotDefinition]
    , referenceRosterSlots :: ![RosterSlot]
    , referenceWeekStart   :: !Day
    }
    deriving (Eq, Show)

fetchRosterTemplateReferenceWeek ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    Int ->
    IO (Maybe RosterTemplateReferenceWeek)
fetchRosterTemplateReferenceWeek actor rosterGroup weekOffset
    | not (rosterTemplateActorCanEditRosters actor) = pure Nothing
    | rosterGroup.venueId /= unpackId (rosterTemplateActorVenueId actor) = pure Nothing
    | otherwise = do
        venueConfig <- query @VenueConfig
            |> filterWhere (#venueId, rosterGroup.venueId)
            |> fetchOne
        maybeWeek <- query @RosterWeek
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhere (#weekOffset, weekOffset)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
        case maybeWeek of
            Nothing -> pure (Just RosterTemplateReferenceWeek
                { referenceRosterWeek = Nothing
                , referenceRosterDays = []
                , referenceColumns = []
                , referenceRosterSlots = []
                , referenceWeekStart = venueWeekStartDate venueConfig weekOffset
                })
            Just rosterWeek -> do
                days <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> orderByAsc #dayOffset
                    |> fetch
                columns <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> fetch
                slots <- if null days
                    then pure []
                    else query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #rowIndex
                        |> fetch
                pure (Just RosterTemplateReferenceWeek
                    { referenceRosterWeek = Just rosterWeek
                    , referenceRosterDays = days
                    , referenceColumns = columns
                    , referenceRosterSlots = slots
                    , referenceWeekStart = venueWeekStartDate venueConfig weekOffset
                    })

data RosterTemplateReference
    = RosterTemplateDayReference !(Id RosterWeek) !Int
    | RosterTemplateWeekReference !(Id RosterWeek)
    deriving (Eq, Show)

startRosterTemplateDraftFromReference ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateReference ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startRosterTemplateDraftFromReference actor rosterGroup requestedName reference = do
    maybeSource <- fetchReferenceSource rosterGroup reference
    case maybeSource of
        Nothing -> pure (Left RosterTemplateNotFound)
        Just source ->
            startRosterTemplateDraftWithContent actor rosterGroup source.sourceScale requestedName source.sourceContent

data ReferenceSource = ReferenceSource
    { sourceScale   :: !RosterTemplateScaleEnum
    , sourceContent :: !RosterTemplateContent
    }

fetchReferenceSource ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    RosterTemplateReference ->
    IO (Maybe ReferenceSource)
fetchReferenceSource rosterGroup reference = do
    let (rosterWeekId, selectedDayOffset, scale) = case reference of
            RosterTemplateDayReference weekId dayOffset -> (weekId, Just dayOffset, Day)
            RosterTemplateWeekReference weekId          -> (weekId, Nothing, Week)
    maybeWeek <- query @RosterWeek
        |> filterWhere (#id, rosterWeekId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#venueId, rosterGroup.venueId)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchOneOrNothing
    case maybeWeek of
        Nothing -> pure Nothing
        Just rosterWeek -> do
            sourceDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                |> orderByAsc #dayOffset
                |> fetch
            let selectedDays = case selectedDayOffset of
                    Nothing        -> sourceDays
                    Just dayOffset -> filter ((== dayOffset) . (.dayOffset)) sourceDays
            if null selectedDays || (scale == Week && map (.dayOffset) selectedDays /= [0 .. 6])
                then pure Nothing
                else do
                    definitions <- query @RosterWeekSlotDefinition
                        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #sortOrder
                        |> fetch
                    slots <- query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) selectedDays)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #rowIndex
                        |> fetch
                    venueConfig <- query @VenueConfig
                        |> filterWhere (#venueId, rosterGroup.venueId)
                        |> fetchOne
                    let weekStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
                    pure (ReferenceSource scale <$> referenceContent weekStartDate selectedDayOffset selectedDays definitions slots)

referenceContent ::
    Day ->
    Maybe Int ->
    [RosterDay] ->
    [RosterWeekSlotDefinition] ->
    [RosterSlot] ->
    Maybe RosterTemplateContent
referenceContent weekStartDate selectedDayOffset sourceDays definitions slots = do
    shiftInputs <- traverse (slotInput weekStartDate selectedDayOffset dayById definitionSortById) slots
    pure RosterTemplateContent
        { contentDays = map dayInput sourceDays
        , contentColumns = columnInputs
        , contentShifts = shiftInputs
        }
  where
    dayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
    definitionSortById = Map.fromList [(unpackId definition.id, definition.sortOrder) | definition <- definitions]
    dayInput day = RosterTemplateDayInput
        { inputDayIndex = maybe day.dayOffset (const 0) selectedDayOffset
        , inputDayIsClosed = day.isClosed
        , inputDayRowCount = day.rowCount
        }
    columnInputs = case definitions of
        [] -> [RosterTemplateColumnInput "Shift" 0]
        _  ->
            [ RosterTemplateColumnInput definition.name definition.sortOrder
            | definition <- definitions
            ]

slotInput ::
    Day ->
    Maybe Int ->
    Map.Map UUID RosterDay ->
    Map.Map UUID Int ->
    RosterSlot ->
    Maybe RosterTemplateShiftInput
slotInput weekStartDate selectedDayOffset dayById definitionSortById slot = do
    sourceDay <- Map.lookup slot.rosterDayId dayById
    columnSortOrder <- Map.lookup slot.rosterWeekSlotDefinitionId definitionSortById
    startsAt <- slot.startsAt
    endsAt <- slot.endsAt
    shiftTypeId <- Id <$> slot.shiftTypeId
    assignment <- case (slot.assignmentState, slot.staffId) of
        ("staff", Just staffId) -> Just (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Just OpenAssignment
        _                       -> Nothing
    let rosterDate = addDays (toInteger sourceDay.dayOffset) weekStartDate
    startMinute <- minuteRelativeToRosterDate rosterDate startsAt
    endMinute <- minuteRelativeToRosterDate rosterDate endsAt
    guard (endMinute > startMinute && endMinute <= 2880)
    pure RosterTemplateShiftInput
        { inputShiftDayIndex = maybe sourceDay.dayOffset (const 0) selectedDayOffset
        , inputShiftColumnSortOrder = columnSortOrder
        , inputShiftRowIndex = slot.rowIndex
        , inputShiftStartMinute = startMinute
        , inputShiftEndMinute = endMinute
        , inputShiftTypeId = shiftTypeId
        , inputShiftAssignment = assignment
        }

minuteRelativeToRosterDate :: Day -> UTCTime -> Maybe Int
minuteRelativeToRosterDate rosterDate instant = do
    let LocalTime localDate (TimeOfDay hour minute seconds) = resolvedInstantLocalTime (resolvedInstantFromUTC instant)
    guard (seconds == 0)
    pure (fromInteger (diffDays localDate rosterDate) * 1440 + hour * 60 + minute)
