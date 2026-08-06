{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateDesigner
    ( RosterTemplateDesignerMutation (..)
    , RosterTemplateReference (..)
    , RosterTemplateReferenceWeek (..)
    , fetchRosterTemplateReferenceRevision
    , fetchRosterTemplateReferenceWeek
    , mutateRosterTemplateDesignerDraft
    , replaceBlankRosterTemplateDesignerDraft
    , replaceRosterTemplateDraftFromReference
    , startConfirmedRosterTemplateDraftFromReference
    , startBlankRosterTemplateDesignerDraft
    , startRosterTemplateDraftFromReference
    ) where

import Application.Helper.RosterTemplateScale (rosterTemplateScaleIsWeek)
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateReferenceRows)
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Control.Monad (guard)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (diffDays)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude

startBlankRosterTemplateDesignerDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startBlankRosterTemplateDesignerDraft actor rosterGroup scale requestedName =
    startRosterTemplateDraftWithContent actor rosterGroup scale requestedName (blankTemplateContent scale)

replaceBlankRosterTemplateDesignerDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
replaceBlankRosterTemplateDesignerDraft actor designId rosterGroup scale requestedName expectedDraftRevision =
    replaceRosterTemplateDraftWithContent actor designId rosterGroup scale requestedName (blankTemplateContent scale) (Just expectedDraftRevision)

blankTemplateContent :: RosterTemplateScaleEnum -> RosterTemplateContent
blankTemplateContent scale = RosterTemplateContent
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
mutateRosterTemplateDesignerDraft actor designId mutation =
    updateRosterTemplateDraftContent actor designId \currentContent ->
        if not (designerMutationTargetExists mutation currentContent)
            then Left (RosterTemplateInvalidContent "The selected template day, column, or shift no longer exists.")
            else Right (applyDesignerMutation mutation currentContent)

designerMutationTargetExists :: RosterTemplateDesignerMutation -> RosterTemplateContent -> Bool
designerMutationTargetExists mutation content = case mutation of
    SetRosterTemplateDay dayIndex _ _ -> any ((== dayIndex) . (.inputDayIndex)) content.contentDays
    AddRosterTemplateColumn _ -> True
    RenameRosterTemplateColumn sortOrder _ -> columnExists sortOrder
    DeleteRosterTemplateColumn sortOrder -> columnExists sortOrder
    UpsertRosterTemplateShift shift ->
        any ((== shift.inputShiftDayIndex) . (.inputDayIndex)) content.contentDays
            && columnExists shift.inputShiftColumnSortOrder
    DeleteRosterTemplateShift dayIndex sortOrder rowIndex ->
        any (matchesCell dayIndex sortOrder rowIndex) content.contentShifts
  where
    columnExists sortOrder = any ((== sortOrder) . (.inputColumnSortOrder)) content.contentColumns
    matchesCell dayIndex sortOrder rowIndex shift =
        (shift.inputShiftDayIndex, shift.inputShiftColumnSortOrder, shift.inputShiftRowIndex)
            == (dayIndex, sortOrder, rowIndex)

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

replaceRosterTemplateDraftFromReference ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    Text ->
    RosterTemplateReference ->
    Text ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
replaceRosterTemplateDraftFromReference actor designId rosterGroup requestedName reference expectedSourceRevision expectedDraftRevision = withTransaction do
    lockRosterTemplateReferenceRows (referenceWeekId reference) (referenceDayOffset reference)
    maybeSource <- fetchReferenceSource rosterGroup reference
    case maybeSource of
        Nothing -> pure (Left RosterTemplateNotFound)
        Just source
            | referenceSourceRevision source /= expectedSourceRevision -> pure (Left RosterTemplateNotFound)
            | otherwise ->
                replaceRosterTemplateDraftWithContentInCurrentTransaction actor designId rosterGroup source.sourceScale requestedName source.sourceContent (Just expectedDraftRevision)

startConfirmedRosterTemplateDraftFromReference ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateReference ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
startConfirmedRosterTemplateDraftFromReference actor rosterGroup requestedName reference expectedSourceRevision = withTransaction do
    lockRosterTemplateReferenceRows (referenceWeekId reference) (referenceDayOffset reference)
    maybeSource <- fetchReferenceSource rosterGroup reference
    case maybeSource of
        Nothing -> pure (Left RosterTemplateNotFound)
        Just source
            | referenceSourceRevision source /= expectedSourceRevision -> pure (Left RosterTemplateNotFound)
            | otherwise -> startRosterTemplateDraftWithContentInCurrentTransaction actor rosterGroup source.sourceScale requestedName source.sourceContent

referenceWeekId :: RosterTemplateReference -> Id RosterWeek
referenceWeekId (RosterTemplateDayReference weekId _) = weekId
referenceWeekId (RosterTemplateWeekReference weekId)  = weekId

referenceDayOffset :: RosterTemplateReference -> Maybe Int
referenceDayOffset (RosterTemplateDayReference _ dayOffset) = Just dayOffset
referenceDayOffset RosterTemplateWeekReference {}           = Nothing

fetchRosterTemplateReferenceRevision ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    RosterTemplateReference ->
    IO (Maybe Text)
fetchRosterTemplateReferenceRevision rosterGroup reference =
    fmap referenceSourceRevision <$> fetchReferenceSource rosterGroup reference

referenceSourceRevision :: ReferenceSource -> Text
referenceSourceRevision source =
    tshow (source.sourceScale, rosterTemplateContentRevision source.sourceContent)

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
            if null selectedDays || (rosterTemplateScaleIsWeek scale && map (.dayOffset) selectedDays /= [0 .. 6])
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
