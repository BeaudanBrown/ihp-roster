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
import Application.Helper.WeekBoundaries (orderedWeekdayIndexes,
                                          weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Application.RosterTemplates.Mutations (lockRosterTemplateReferenceRows)
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Control.Monad (guard)
import Data.List (nubBy)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
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
startBlankRosterTemplateDesignerDraft actor rosterGroup scale requestedName = do
    content <- blankTemplateContent actor rosterGroup scale
    startRosterTemplateDraftWithContent actor rosterGroup scale requestedName content

replaceBlankRosterTemplateDesignerDraft ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    Text ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateDraft)
replaceBlankRosterTemplateDesignerDraft actor designId rosterGroup scale requestedName expectedDraftRevision = do
    content <- blankTemplateContent actor rosterGroup scale
    replaceRosterTemplateDraftWithContent actor designId rosterGroup scale requestedName content (Just expectedDraftRevision)

blankTemplateContent ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    RosterTemplateScaleEnum ->
    IO RosterTemplateContent
blankTemplateContent actor rosterGroup scale = do
    weekdayIndexes <- case scale of
        Day -> pure [Nothing]
        Week -> do
            venueConfig <- query @VenueConfig
                |> filterWhere (#venueId, unpackId (rosterTemplateActorVenueId actor))
                |> fetchOne
            pure (map Just (orderedWeekdayIndexes venueConfig.rosterWeekStartsOn))
    pure RosterTemplateContent
        { contentDays =
            [ RosterTemplateDayInput dayIndex weekdayIndex False 1
            | (dayIndex, weekdayIndex) <- zip [0 ..] weekdayIndexes
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
    { referenceRosterDays  :: ![RosterDay]
    , referenceRosterSlots :: ![RosterSlot]
    , referenceWeekStart   :: !Day
    }
    deriving (Eq, Show)

fetchRosterTemplateReferenceWeek ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    RosterGroup ->
    Day ->
    IO (Maybe RosterTemplateReferenceWeek)
fetchRosterTemplateReferenceWeek actor rosterGroup windowStart
    | not (rosterTemplateActorCanEditRosters actor) = pure Nothing
    | rosterGroup.venueId /= unpackId (rosterTemplateActorVenueId actor) = pure Nothing
    | otherwise = do
        days <- query @RosterDay
            |> filterWhere (#venueId, rosterGroup.venueId)
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
            |> filterWhereLessThan (#operationalDate, addDays 7 windowStart)
            |> orderByAsc #operationalDate
            |> fetch
        slots <- if null days then pure [] else query @RosterSlot
            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
            |> filterWhere (#deletedAt, Nothing)
            |> orderByAsc #rowIndex
            |> fetch
        pure (Just RosterTemplateReferenceWeek
            { referenceRosterDays = days
            , referenceRosterSlots = slots
            , referenceWeekStart = windowStart
            })

data RosterTemplateReference
    = RosterTemplateDayReference !Day
    | RosterTemplateWeekReference !Day !Day
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
    lockRosterTemplateReferenceRows (rosterTemplateActorVenueId actor) rosterGroup.id (referenceWindowStart reference) (referenceWindowEnd reference) (referenceOperationalDate reference)
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
    lockRosterTemplateReferenceRows (rosterTemplateActorVenueId actor) rosterGroup.id (referenceWindowStart reference) (referenceWindowEnd reference) (referenceOperationalDate reference)
    maybeSource <- fetchReferenceSource rosterGroup reference
    case maybeSource of
        Nothing -> pure (Left RosterTemplateNotFound)
        Just source
            | referenceSourceRevision source /= expectedSourceRevision -> pure (Left RosterTemplateNotFound)
            | otherwise -> startRosterTemplateDraftWithContentInCurrentTransaction actor rosterGroup source.sourceScale requestedName source.sourceContent

referenceWindowStart :: RosterTemplateReference -> Day
referenceWindowStart (RosterTemplateDayReference operationalDate) = operationalDate
referenceWindowStart (RosterTemplateWeekReference windowStart _) = windowStart

referenceWindowEnd :: RosterTemplateReference -> Day
referenceWindowEnd (RosterTemplateDayReference operationalDate) = addDays 1 operationalDate
referenceWindowEnd (RosterTemplateWeekReference _ windowEnd) = windowEnd

referenceOperationalDate :: RosterTemplateReference -> Maybe Day
referenceOperationalDate (RosterTemplateDayReference operationalDate) = Just operationalDate
referenceOperationalDate RosterTemplateWeekReference {} = Nothing

fetchRosterTemplateReferenceRevision ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    RosterTemplateReference ->
    IO (Maybe Text)
fetchRosterTemplateReferenceRevision rosterGroup reference =
    fmap referenceSourceRevision <$> fetchReferenceSource rosterGroup reference

referenceSourceRevision :: ReferenceSource -> Text
referenceSourceRevision source =
    tshow (source.sourceScale, source.sourceCalendarRevision, rosterTemplateContentRevision source.sourceContent)

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
    { sourceScale            :: !RosterTemplateScaleEnum
    , sourceContent          :: !RosterTemplateContent
    , sourceCalendarRevision :: !Int
    }

fetchReferenceSource ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    RosterTemplateReference ->
    IO (Maybe ReferenceSource)
fetchReferenceSource rosterGroup reference = do
    let (windowStart, windowEnd, selectedDate, scale) = case reference of
            RosterTemplateDayReference operationalDate -> (operationalDate, addDays 1 operationalDate, Just operationalDate, Day)
            RosterTemplateWeekReference startDate endDate -> (startDate, endDate, Nothing, Week)
    sourceDays <- query @RosterDay
        |> filterWhere (#venueId, rosterGroup.venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
        |> filterWhereLessThan (#operationalDate, windowEnd)
        |> orderByAsc #operationalDate
        |> fetch
    let expectedDates = case scale of
            Day  -> [windowStart]
            Week -> map (`addDays` windowStart) [0 .. 6]
    if map (.operationalDate) sourceDays /= expectedDates
        then pure Nothing
        else do
            lanes <- query @RosterLane
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) sourceDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
            slots <- query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) sourceDays)
                |> filterWhere (#deletedAt, Nothing)
                |> orderByAsc #rowIndex
                |> fetch
            venueConfig <- query @VenueConfig |> filterWhere (#venueId, rosterGroup.venueId) |> fetchOne
            pure ((\content -> ReferenceSource scale content venueConfig.rosterCalendarRevision) <$> referenceContent windowStart selectedDate sourceDays lanes slots)

referenceContent ::
    Day ->
    Maybe Day ->
    [RosterDay] ->
    [RosterLane] ->
    [RosterSlot] ->
    Maybe RosterTemplateContent
referenceContent windowStart selectedDate sourceDays lanes slots = do
    shiftInputs <- traverse (slotInput windowStart selectedDate dayById laneColumnSortById) slots
    pure RosterTemplateContent
        { contentDays = map dayInput sourceDays
        , contentColumns = columnInputs
        , contentShifts = shiftInputs
        }
  where
    dayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
    dayDateById = Map.fromList [(unpackId day.id, day.operationalDate) | day <- sourceDays]
    orderedLanes = sortOn (\lane -> (Map.lookup lane.rosterDayId dayDateById, lane.sortOrder, lane.id)) lanes
    uniqueLaneNames = nubBy (\left right -> Text.toCaseFold (Text.strip left.name) == Text.toCaseFold (Text.strip right.name)) orderedLanes
    columnSortByName = Map.fromList [(Text.toCaseFold (Text.strip lane.name), sortOrder) | (sortOrder, lane) <- zip [0 ..] uniqueLaneNames]
    laneColumnSortById = Map.fromList
        [ (unpackId lane.id, columnSortByName Map.! Text.toCaseFold (Text.strip lane.name))
        | lane <- lanes
        ]
    dayInput day = RosterTemplateDayInput
        { inputDayIndex = maybe (fromInteger (diffDays day.operationalDate windowStart)) (const 0) selectedDate
        , inputDayWeekdayIndex = case selectedDate of
            Just _  -> Nothing
            Nothing -> Just (weekdayIndexForDay day.operationalDate)
        , inputDayIsClosed = day.isClosed
        , inputDayRowCount = day.rowCount
        }
    columnInputs = case uniqueLaneNames of
        [] -> [RosterTemplateColumnInput "Shift" 0]
        _ -> [RosterTemplateColumnInput lane.name sortOrder | (sortOrder, lane) <- zip [0 ..] uniqueLaneNames]

slotInput ::
    Day ->
    Maybe Day ->
    Map.Map UUID RosterDay ->
    Map.Map UUID Int ->
    RosterSlot ->
    Maybe RosterTemplateShiftInput
slotInput windowStart selectedDate dayById laneColumnSortById slot = do
    sourceDay <- Map.lookup slot.rosterDayId dayById
    columnSortOrder <- Map.lookup slot.rosterLaneId laneColumnSortById
    startsAt <- slot.startsAt
    endsAt <- slot.endsAt
    shiftTypeId <- Id <$> slot.shiftTypeId
    assignment <- case (slot.assignmentState, slot.staffId) of
        ("staff", Just staffId) -> Just (StaffAssignment (Id staffId))
        ("open", Nothing)       -> Just OpenAssignment
        _                       -> Nothing
    startMinute <- minuteRelativeToRosterDate sourceDay.operationalDate startsAt
    endMinute <- minuteRelativeToRosterDate sourceDay.operationalDate endsAt
    guard (endMinute > startMinute && endMinute <= 2880)
    pure RosterTemplateShiftInput
        { inputShiftDayIndex = maybe (fromInteger (diffDays sourceDay.operationalDate windowStart)) (const 0) selectedDate
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
