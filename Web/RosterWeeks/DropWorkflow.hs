module Web.RosterWeeks.DropWorkflow
    ( MoveRosterShiftIntent (..)
    , MoveRosterTimelineShiftIntent (..)
    , RosterDayDropBoundaryResolution (..)
    , RosterDropSource (..)
    , RosterShiftDropDestination (..)
    , RosterShiftDropTarget (..)
    , RosterStaffDropIntent (..)
    , RosterTimelineDropBoundaryResolution (..)
    , TimelineShiftDropTarget (..)
    , firstAvailableRosterDayPlacement
    , parseRosterDropSourceToken
    , parseRosterShiftDropDestinationToken
    , parseTimelineShiftDropTargetToken
    , resolveRosterDayDropBoundaries
    , resolveRosterTimelineDropBoundaries
    , validateDuplicateRosterShiftIntent
    , validateMoveRosterShiftIntent
    , validateMoveRosterTimelineShiftIntent
    , validateRosterShiftDeleteDropIntent
    , validateRosterStaffDropIntent
    ) where

import Application.Helper.RosterGroups (staffIsEligibleForRosterGroup)
import Application.Helper.TimeRules
import Application.RosterShiftAssignment (rosterShiftAssignment)
import Application.VenueTime.Model
import Control.Monad (guard)
import Data.Either (isRight)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay)
import qualified Text.Read as TextRead
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation (invalidRosterSlotTimingMessage)
import Web.RosterWeeks.DateRange (resolveRosterLaneReference,
                                  rosterPlanningWeekForDay)
import Web.RosterWeeks.Service (copyRosterSlotToDay,
                                fetchActiveStaffForCurrentVenue,
                                resolveRosterTimelineTargetBoundaries,
                                rosterSlotCopyAmbiguousEndpoints)

data RosterDropSource
    = ExistingRosterShiftSource !(Id RosterSlot)
    | RosterStaffSource !(Id Staff)
    deriving (Eq, Show)

data RosterShiftDropDestination
    = DeleteRosterShiftDestination
    | PlaceRosterShiftDestination !RosterShiftDropTarget
    deriving (Eq, Show)

parseRosterDropSourceToken :: Text -> Maybe RosterDropSource
parseRosterDropSourceToken token =
    (ExistingRosterShiftSource <$> parseExistingSlotToken token)
        <|> (RosterStaffSource <$> parseStaffToken token)

parseRosterShiftDropDestinationToken :: Text -> Maybe RosterShiftDropDestination
parseRosterShiftDropDestinationToken "delete" = Just DeleteRosterShiftDestination
parseRosterShiftDropDestinationToken token = PlaceRosterShiftDestination <$> parseRosterShiftDropTargetToken token

data MoveRosterShiftIntent = MoveRosterShiftIntent
    { sourceSlot           :: !RosterSlot
    , sourceRosterDay      :: !RosterDay
    , targetRosterDay      :: !RosterDay
    , targetSlotDefinition :: !RosterLane
    , targetRowIndex       :: !Int
    , moveIsNoOp           :: !Bool
    }

data RosterShiftDropTarget
    = PreciseRosterShiftDropTarget !(Id RosterDay) !(Id RosterLane) !Int
    | DayRosterShiftDropTarget !(Id RosterDay)
    deriving (Eq, Show)

data TimelineShiftDropTarget = TimelineShiftDropTarget
    { timelineTargetRosterDayId       :: !(Id RosterDay)
    , timelineTargetSlotDefinitionId  :: !(Id RosterLane)
    , timelineTargetOperationalMinute :: !Int
    }
    deriving (Eq, Show)

data MoveRosterTimelineShiftIntent = MoveRosterTimelineShiftIntent
    { timelineSourceSlot           :: !RosterSlot
    , timelineSourceRosterDay      :: !RosterDay
    , timelineTargetRosterDay      :: !RosterDay
    , timelineTargetSlotDefinition :: !RosterLane
    , timelineTargetRowIndex       :: !Int
    , timelineTargetStartTime      :: !TimeOfDay
    , timelineMoveIsNoOp           :: !Bool
    }

data RosterDayDropBoundaryResolution
    = RosterDayDropBoundaryFailure
        { dayDropRepeatedEndpoints :: !(Bool, Bool)
        , dayDropBoundaryFailure   :: !BoundaryModelError
        }
    | RosterDayDropBoundaryReady
        { dayDropTargetRosterWeek :: !RosterWeek
        , dayDropCopiedSlot       :: !RosterSlot
        }

data RosterTimelineDropBoundaryResolution
    = RosterTimelineDropInvalid !Text
    | RosterTimelineDropBoundaryFailure
        { timelineDropRepeatedEndpoints :: !(Bool, Bool)
        , timelineDropSelections        :: !ShiftCopyOccurrenceSelections
        , timelineDropBoundaryFailure   :: !BoundaryModelError
        }
    | RosterTimelineDropBoundaryReady
        { timelineDropTargetRosterWeek :: !RosterWeek
        , timelineDropBoundaries       :: !AuthoritativeBoundaries
        }

data RosterStaffDropIntent
    = RosterStaffExistingShiftDropIntent
        { staffDropStaff      :: !Staff
        , staffDropSlot       :: !RosterSlot
        , staffDropRosterDay  :: !RosterDay
        , staffDropRosterWeek :: !RosterWeek
        }
    | RosterStaffCreateShiftDropIntent
        { staffDropStaff          :: !Staff
        , staffDropRosterDay      :: !RosterDay
        , staffDropRosterWeek     :: !RosterWeek
        , staffDropSlotDefinition :: !RosterLane
        , staffDropRowIndex       :: !Int
        }

validateMoveRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateMoveRosterShiftIntent rosterGroupId weekOffset sourceToken targetToken =
    validateRosterShiftDropIntent rosterGroupId weekOffset True sourceToken targetToken

validateDuplicateRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateDuplicateRosterShiftIntent rosterGroupId weekOffset sourceToken targetToken =
    validateRosterShiftDropIntent rosterGroupId weekOffset False sourceToken targetToken

validateMoveRosterTimelineShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> Text -> IO (Either Text MoveRosterTimelineShiftIntent)
validateMoveRosterTimelineShiftIntent rosterGroupId weekOffset sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, parseTimelineShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            maybeResult <- validateRosterTimelineShiftDropTarget rosterGroupId weekOffset sourceSlotId target
            pure (maybe (Left "Drag the shift onto an open timeline time target.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open timeline time target.")

resolveRosterDayDropBoundaries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => MoveRosterShiftIntent -> ShiftCopyOccurrenceSelections -> IO RosterDayDropBoundaryResolution
resolveRosterDayDropBoundaries intent selections = do
    sourceRosterWeek <- rosterPlanningWeekForDay intent.sourceRosterDay
    targetRosterWeek <- rosterPlanningWeekForDay intent.targetRosterDay
    venueConfig <- fetchVenueConfig
    let repeatedEndpoints =
            rosterSlotCopyAmbiguousEndpoints
                venueConfig
                sourceRosterWeek
                intent.sourceRosterDay
                targetRosterWeek
                intent.targetRosterDay
                intent.sourceSlot
    pure $ case copyRosterSlotToDay venueConfig sourceRosterWeek intent.sourceRosterDay targetRosterWeek intent.targetRosterDay selections intent.sourceSlot of
        Left failure -> RosterDayDropBoundaryFailure repeatedEndpoints failure
        Right copiedSlot -> RosterDayDropBoundaryReady targetRosterWeek copiedSlot

resolveRosterTimelineDropBoundaries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => MoveRosterTimelineShiftIntent -> Text -> IO RosterTimelineDropBoundaryResolution
resolveRosterTimelineDropBoundaries intent startOccurrenceValue =
    case parseOccurrenceParam startOccurrenceValue of
        Left message -> pure (RosterTimelineDropInvalid message)
        Right startOccurrence -> do
            rosterWeek <- rosterPlanningWeekForDay intent.timelineTargetRosterDay
            venueConfig <- fetchVenueConfig
            let targetRosterDate = Calendar.addDays (toInteger intent.timelineTargetRosterDay.dayOffset) (venueWeekStartDate venueConfig rosterWeek.weekOffset)
                targetShiftDate = rosterShiftStartDate targetRosterDate intent.timelineTargetStartTime
                repeatedEndpoints = (civilBoundaryIsRepeated targetShiftDate intent.timelineTargetStartTime, False)
                selections = noShiftCopyOccurrenceSelections { copyShiftStartOccurrence = startOccurrence }
            pure $ case rosterSlotElapsedSeconds intent.timelineSourceSlot of
                Nothing -> RosterTimelineDropInvalid invalidRosterSlotTimingMessage
                Just duration ->
                    case resolveRosterTimelineTargetBoundaries venueConfig.timezone duration targetShiftDate intent.timelineTargetStartTime startOccurrence of
                        Left failure -> RosterTimelineDropBoundaryFailure repeatedEndpoints selections failure
                        Right boundaries
                            | not (authoritativeRosterIntervalIsOperationallyValid boundaries) ->
                                RosterTimelineDropInvalid invalidRosterSlotTimingMessage
                            | otherwise -> RosterTimelineDropBoundaryReady rosterWeek boundaries

validateRosterShiftDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Bool -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateRosterShiftDropIntent rosterGroupId weekOffset allowSemanticDayNoOp sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, parseRosterShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            maybeResult <- validateRosterShiftDropTarget rosterGroupId weekOffset allowSemanticDayNoOp sourceSlotId target
            pure (maybe (Left "Choose an open roster day in this week.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open roster day.")

validateRosterShiftDeleteDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> Text -> IO (Either Text RosterSlot)
validateRosterShiftDeleteDropIntent rosterGroupId weekOffset sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, targetToken) of
        (Just rosterSlotId, "delete") -> do
            maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
            case maybeSlot of
                Nothing -> pure (Left "Drag an editable shift to the delete area.")
                Just rosterSlot -> do
                    rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
                    rosterWeek <- rosterPlanningWeekForDay rosterDay
                    let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
                    if matchesScope && not rosterWeek.isLive && not rosterDay.isClosed
                        then pure (Right rosterSlot)
                        else pure (Left "Drag an editable shift from this roster week to the delete area.")
        _ -> pure (Left "Drag a shift to the delete area.")

validateRosterStaffDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> Text -> IO (Either Text RosterStaffDropIntent)
validateRosterStaffDropIntent rosterGroupId weekOffset sourceToken targetToken = do
    case (parseStaffToken sourceToken, parseExistingSlotToken targetToken, parseRosterShiftDropTargetToken targetToken) of
        (Just staffId, Just rosterSlotId, _) -> do
            maybeResult <- validateRosterStaffExistingShiftDropTarget rosterGroupId weekOffset staffId rosterSlotId
            pure (maybe (Left "Drop staff onto an editable shift in this roster week.") Right maybeResult)
        (Just staffId, _, Just createTarget) -> do
            maybeResult <- validateRosterStaffCreateShiftDropTarget rosterGroupId weekOffset staffId createTarget
            pure (maybe (Left "Drop staff onto an open add-shift target in this roster week.") Right maybeResult)
        _ -> pure (Left "Drag a staff member onto a shift or add-shift target.")

validateRosterStaffExistingShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id Staff -> Id RosterSlot -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffExistingShiftDropTarget rosterGroupId weekOffset staffId rosterSlotId = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId rosterGroupId
    maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
    case (maybeStaff, maybeSlot) of
        (Just staff, Just rosterSlot) -> do
            rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
            rosterWeek <- rosterPlanningWeekForDay rosterDay
            let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
            pure do
                guard matchesScope
                guard (not rosterWeek.isLive)
                guard (not rosterDay.isClosed)
                guard staffEligible
                pure RosterStaffExistingShiftDropIntent { staffDropStaff = staff, staffDropSlot = rosterSlot, staffDropRosterDay = rosterDay, staffDropRosterWeek = rosterWeek }
        _ -> pure Nothing

validateRosterStaffCreateShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id Staff -> RosterShiftDropTarget -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffCreateShiftDropTarget rosterGroupId weekOffset staffId dropTarget = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId rosterGroupId
    maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, dropTargetRosterDayId dropTarget))
    case (maybeStaff, maybeTargetRosterDay) of
        (Just staff, Just targetRosterDay) -> do
            rosterWeek <- rosterPlanningWeekForDay targetRosterDay
            maybeResolvedTarget <- resolveRosterShiftDropPlacement rosterWeek targetRosterDay dropTarget
            let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
            pure do
                guard matchesScope
                guard (not rosterWeek.isLive)
                guard (not targetRosterDay.isClosed)
                guard staffEligible
                (slotDefinition, rowIndex) <- maybeResolvedTarget
                pure RosterStaffCreateShiftDropIntent { staffDropStaff = staff, staffDropRosterDay = targetRosterDay, staffDropRosterWeek = rosterWeek, staffDropSlotDefinition = slotDefinition, staffDropRowIndex = rowIndex }
        _ -> pure Nothing

validateRosterShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Bool -> Id RosterSlot -> RosterShiftDropTarget -> IO (Maybe MoveRosterShiftIntent)
validateRosterShiftDropTarget rosterGroupId weekOffset allowSemanticDayNoOp sourceSlotId dropTarget = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId))
    case maybeSourceSlot of
        Nothing -> pure Nothing
        Just sourceSlot -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            sourceRosterWeek <- rosterPlanningWeekForDay sourceRosterDay
            let targetRosterDayId = dropTargetRosterDayId dropTarget
            maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, targetRosterDayId))
            case maybeTargetRosterDay of
                Nothing -> pure Nothing
                Just targetRosterDay -> do
                    targetRosterWeek <- rosterPlanningWeekForDay targetRosterDay
                    maybeResolvedTarget <- resolveRosterShiftDropPlacement targetRosterWeek targetRosterDay dropTarget
                    let sourceMatchesScope = sourceRosterWeek.rosterGroupId == unpackId rosterGroupId && sourceRosterWeek.weekOffset == weekOffset
                    let targetMatchesScope = targetRosterWeek.rosterGroupId == unpackId rosterGroupId && targetRosterWeek.weekOffset == weekOffset
                    let sourceHasValidAssignment = isRight (rosterShiftAssignment sourceSlot)
                    let targetIsOpen = not targetRosterDay.isClosed
                    let semanticSameDayNoOp = allowSemanticDayNoOp && isDayDropTarget dropTarget && sourceSlot.rosterDayId == unpackId targetRosterDay.id
                    pure do
                        guard sourceMatchesScope
                        guard targetMatchesScope
                        guard sourceHasValidAssignment
                        guard targetIsOpen
                        case (semanticSameDayNoOp, maybeResolvedTarget) of
                            (True, Just (targetSlotDefinition, _)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex = sourceSlot.rowIndex, moveIsNoOp = True }
                            (False, Just (targetSlotDefinition, targetRowIndex)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex, moveIsNoOp = False }
                            _ -> Nothing

validateRosterTimelineShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id RosterSlot -> TimelineShiftDropTarget -> IO (Maybe MoveRosterTimelineShiftIntent)
validateRosterTimelineShiftDropTarget rosterGroupId weekOffset sourceSlotId target = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId) |> filterWhere (#deletedAt, Nothing))
    case maybeSourceSlot of
        Nothing -> pure Nothing
        Just sourceSlot -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            sourceRosterWeek <- rosterPlanningWeekForDay sourceRosterDay
            maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, target.timelineTargetRosterDayId))
            maybeTargetSlotDefinition <- case maybeTargetRosterDay of
                Nothing -> pure Nothing
                Just targetRosterDay -> resolveRosterLaneReference (Just targetRosterDay.id) target.timelineTargetSlotDefinitionId
            case (maybeTargetRosterDay, maybeTargetSlotDefinition, rosterSlotStartTime sourceSlot, rosterSlotElapsedSeconds sourceSlot) of
                (Just targetRosterDay, Just targetSlotDefinition, Just sourceStart, Just _) -> do
                    targetRosterWeek <- rosterPlanningWeekForDay targetRosterDay
                    let targetStartTime = minuteOfDayToTimeOfDay target.timelineTargetOperationalMinute
                        sourceMatchesScope = sourceRosterWeek.rosterGroupId == unpackId rosterGroupId && sourceRosterWeek.weekOffset == weekOffset
                        targetMatchesScope = targetRosterWeek.rosterGroupId == unpackId rosterGroupId && targetRosterWeek.weekOffset == weekOffset
                        targetDefinitionMatchesWeek = targetSlotDefinition.rosterDayId == unpackId targetRosterDay.id
                        isNoOp = sourceSlot.rosterDayId == unpackId targetRosterDay.id
                            && sourceSlot.rosterLaneId == unpackId targetSlotDefinition.id
                            && sourceStart == targetStartTime
                        validTargetStart = isNoOp
                            || ( isQuarterHourMinutes target.timelineTargetOperationalMinute
                                 && target.timelineTargetOperationalMinute >= rosterOperationalStartMinuteOfDay
                                 && target.timelineTargetOperationalMinute <= rosterOperationalFinalSelectableMinute
                               )
                    maybeRowIndex <- resolveTimelineTargetRowIndex sourceSlot targetRosterDay targetSlotDefinition
                    pure do
                        targetRowIndex <- maybeRowIndex
                        guard sourceMatchesScope
                        guard targetMatchesScope
                        guard (not sourceRosterWeek.isLive)
                        guard (not targetRosterWeek.isLive)
                        guard (not targetRosterDay.isClosed)
                        guard (isRight (rosterShiftAssignment sourceSlot))
                        guard targetDefinitionMatchesWeek
                        guard (isNothing targetSlotDefinition.deletedAt)
                        guard validTargetStart
                        pure MoveRosterTimelineShiftIntent
                            { timelineSourceSlot = sourceSlot
                            , timelineSourceRosterDay = sourceRosterDay
                            , timelineTargetRosterDay = targetRosterDay
                            , timelineTargetSlotDefinition = targetSlotDefinition
                            , timelineTargetRowIndex = targetRowIndex
                            , timelineTargetStartTime = targetStartTime
                            , timelineMoveIsNoOp = isNoOp
                            }
                _ -> pure Nothing

resolveTimelineTargetRowIndex :: (?modelContext :: ModelContext) => RosterSlot -> RosterDay -> RosterLane -> IO (Maybe Int)
resolveTimelineTargetRowIndex sourceSlot targetRosterDay targetSlotDefinition = do
    daySlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
        |> filterWhere (#rosterLaneId, unpackId targetSlotDefinition.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let occupiedRows = Set.fromList [ slot.rowIndex | slot <- daySlots, slot.id /= sourceSlot.id ]
        preferredRow = sourceSlot.rowIndex
        candidateRows = preferredRow : filter (/= preferredRow) [0 .. max preferredRow targetRosterDay.rowCount]
        fallbackRow = max preferredRow targetRosterDay.rowCount
    pure (listToMaybe (filter (`Set.notMember` occupiedRows) candidateRows) <|> Just fallbackRow)

parseStaffToken :: Text -> Maybe (Id Staff)
parseStaffToken token =
    case Text.splitOn ":" token of
        ["staff", rawStaffId] -> Id <$> parseUUIDText rawStaffId
        _                     -> Nothing

parseExistingSlotToken :: Text -> Maybe (Id RosterSlot)
parseExistingSlotToken token =
    case Text.splitOn ":" token of
        ["existing", rawSlotId] -> Id <$> parseUUIDText rawSlotId
        _                       -> Nothing

parseRosterShiftDropTargetToken :: Text -> Maybe RosterShiftDropTarget
parseRosterShiftDropTargetToken token =
    case Text.splitOn ":" token of
        ["day", rawRosterDayId] ->
            DayRosterShiftDropTarget . Id <$> parseUUIDText rawRosterDayId
        ["new", rawRosterDayId, rawSlotDefinitionId, rawRowIndex] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            rowIndex <- TextRead.readMaybe (cs rawRowIndex)
            pure (PreciseRosterShiftDropTarget rosterDayId slotDefinitionId rowIndex)
        _ -> Nothing

parseTimelineShiftDropTargetToken :: Text -> Maybe TimelineShiftDropTarget
parseTimelineShiftDropTargetToken token =
    case Text.splitOn ":" token of
        ["time", rawRosterDayId, rawSlotDefinitionId, rawMinute] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            minute <- TextRead.readMaybe (cs rawMinute)
            pure TimelineShiftDropTarget
                { timelineTargetRosterDayId = rosterDayId
                , timelineTargetSlotDefinitionId = slotDefinitionId
                , timelineTargetOperationalMinute = minute
                }
        _ -> Nothing

dropTargetRosterDayId :: RosterShiftDropTarget -> Id RosterDay
dropTargetRosterDayId = \case
    PreciseRosterShiftDropTarget rosterDayId _ _ -> rosterDayId
    DayRosterShiftDropTarget rosterDayId -> rosterDayId

isDayDropTarget :: RosterShiftDropTarget -> Bool
isDayDropTarget = \case
    DayRosterShiftDropTarget {} -> True
    _ -> False

resolveRosterShiftDropPlacement :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> RosterDay -> RosterShiftDropTarget -> IO (Maybe (RosterLane, Int))
resolveRosterShiftDropPlacement targetRosterWeek targetRosterDay = \case
    PreciseRosterShiftDropTarget _ targetSlotDefinitionId targetRowIndex -> do
        maybeTargetSlotDefinition <- resolveRosterLaneReference (Just targetRosterDay.id) targetSlotDefinitionId
        targetExists <- maybe (pure False) (\lane -> rosterSlotCellExists targetRosterDay.id lane.id targetRowIndex) maybeTargetSlotDefinition
        pure do
            targetSlotDefinition <- maybeTargetSlotDefinition
            guard (targetRowIndex >= 0)
            guard (targetSlotDefinition.rosterDayId == unpackId targetRosterDay.id)
            guard (isNothing targetSlotDefinition.deletedAt)
            guard (not targetExists)
            pure (targetSlotDefinition, targetRowIndex)
    DayRosterShiftDropTarget _ -> do
        targetSlotDefinitions <- query @RosterLane
            |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
            |> filterWhere (#deletedAt, Nothing)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetch
        daySlots <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
        pure (firstAvailableRosterDayPlacement targetRosterDay targetSlotDefinitions daySlots)

firstAvailableRosterDayPlacement :: RosterDay -> [RosterLane] -> [RosterSlot] -> Maybe (RosterLane, Int)
firstAvailableRosterDayPlacement targetRosterDay targetSlotDefinitions daySlots = do
    firstDefinition <- listToMaybe targetSlotDefinitions
    let occupiedCells = Set.fromList [(slot.rowIndex, slot.rosterLaneId) | slot <- daySlots]
    let candidateRows = [0 .. max 0 targetRosterDay.rowCount]
    let candidates = [(definition, rowIndex) | rowIndex <- candidateRows, definition <- targetSlotDefinitions, (rowIndex, unpackId definition.id) `Set.notMember` occupiedCells]
    pure (fromMaybe (firstDefinition, max 0 targetRosterDay.rowCount) (listToMaybe candidates))

rosterSlotCellExists :: (?modelContext :: ModelContext) => Id RosterDay -> Id RosterLane -> Int -> IO Bool
rosterSlotCellExists rosterDayId targetSlotDefinitionId targetRowIndex =
    query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDayId)
        |> filterWhere (#rosterLaneId, unpackId targetSlotDefinitionId)
        |> filterWhere (#rowIndex, targetRowIndex)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchExists
