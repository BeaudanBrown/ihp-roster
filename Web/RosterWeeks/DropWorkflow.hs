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
    , RosterTimelineCreateTarget (..)
    , validateRosterTimelineCreateTarget
    , firstAvailableRosterDayPlacement
    , parseRosterDropSourceToken
    , parseRosterShiftDropDestinationToken
    , parseTimelineShiftDropTargetToken
    , resolveRosterDayDropBoundaries
    , resolveRosterTimelineDropBoundaries
    , validateDuplicateRosterShiftIntent
    , validateMoveRosterShiftIntent
    , validateMoveRosterTimelineShiftIntent
    , validateDuplicateRosterTimelineShiftIntent
    , validateRosterShiftDeleteDropIntent
    , validateRosterStaffDropIntent
    ) where

import Application.Helper.RosterGroups (staffIsEligibleForRosterGroup)
import Application.Helper.TimeRules
import Application.RosterShiftAssignment (rosterShiftAssignment,
                                          rosterShiftIsOpen)
import Application.VenueTime.Model
import Control.Monad (guard)
import Data.Either (isRight)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import qualified Text.Read as TextRead
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation (invalidRosterSlotTimingMessage)
import Web.RosterWeeks.DateRange (RosterWindowScope (..), fetchRosterWindow,
                                  resolveRosterLaneReference,
                                  rosterWindowTarget)
import Web.RosterWeeks.Service (copyRosterSlotToDay,
                                fetchActiveStaffForCurrentVenue,
                                rosterSlotCopyAmbiguousEndpoints)
import Web.RosterWeeks.TimelineScale (TimelineScale (..),
                                      timelineCreateInstants,
                                      timelineScaleForDay)

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
    { timelineTargetRosterDayId      :: !(Id RosterDay)
    , timelineTargetSlotDefinitionId :: !(Id RosterLane)
    , timelineTargetStartsAt         :: !UTCTime
    }
    deriving (Eq, Show)

data RosterTimelineCreateTarget = RosterTimelineCreateTarget
    { timelineCreateDay      :: !RosterDay
    , timelineCreateLane     :: !RosterLane
    , timelineCreateRowIndex :: !Int
    , timelineCreateStartsAt :: !UTCTime
    }

data MoveRosterTimelineShiftIntent = MoveRosterTimelineShiftIntent
    { timelineSourceSlot           :: !RosterSlot
    , timelineSourceRosterDay      :: !RosterDay
    , timelineTargetRosterDay      :: !RosterDay
    , timelineTargetSlotDefinition :: !RosterLane
    , timelineTargetRowIndex       :: !Int
    , timelineMoveStartsAt         :: !UTCTime
    , timelineMoveIsNoOp           :: !Bool
    , timelineSourceTiming         :: !ValidatedRosterShiftTiming
    }

data RosterDayDropBoundaryResolution
    = RosterDayDropBoundaryFailure
        { dayDropRepeatedEndpoints :: !(Bool, Bool)
        , dayDropBoundaryFailure   :: !BoundaryModelError
        }
    | RosterDayDropBoundaryReady
        { dayDropCopiedSlot :: !RosterSlot
        }

data RosterTimelineDropBoundaryResolution
    = RosterTimelineDropInvalid !Text
    | RosterTimelineDropBoundaryReady
        { timelineDropBoundaries :: !AuthoritativeBoundaries
        }

data RosterStaffDropIntent
    = RosterStaffExistingShiftDropIntent
        { staffDropStaff     :: !Staff
        , staffDropSlot      :: !RosterSlot
        , staffDropRosterDay :: !RosterDay
        }
    | RosterStaffCreateShiftDropIntent
        { staffDropStaff          :: !Staff
        , staffDropRosterDay      :: !RosterDay
        , staffDropSlotDefinition :: !RosterLane
        , staffDropRowIndex       :: !Int
        , staffDropStartsAt       :: !(Maybe UTCTime)
        }

validateMoveRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateMoveRosterShiftIntent scope sourceToken targetToken =
    validateRosterShiftDropIntent scope True sourceToken targetToken

validateDuplicateRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateDuplicateRosterShiftIntent scope sourceToken targetToken =
    validateRosterShiftDropIntent scope False sourceToken targetToken

validateMoveRosterTimelineShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text MoveRosterTimelineShiftIntent)
validateMoveRosterTimelineShiftIntent = validateTimelineShiftIntent True

validateDuplicateRosterTimelineShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text MoveRosterTimelineShiftIntent)
validateDuplicateRosterTimelineShiftIntent = validateTimelineShiftIntent False

validateTimelineShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Bool -> RosterWindowScope -> Text -> Text -> IO (Either Text MoveRosterTimelineShiftIntent)
validateTimelineShiftIntent isMove scope sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, parseTimelineShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            validateRosterTimelineShiftDropTarget isMove scope sourceSlotId target >>= \case
                Left _ -> pure (Left invalidRosterSlotTimingMessage)
                Right maybeResult -> pure (maybe (Left "The shift or target is unavailable. Review the refreshed timeline and try again.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open timeline time target.")

resolveRosterDayDropBoundaries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => MoveRosterShiftIntent -> ShiftCopyOccurrenceSelections -> IO RosterDayDropBoundaryResolution
resolveRosterDayDropBoundaries intent selections = do
    venueConfig <- fetchVenueConfig
    let repeatedEndpoints =
            rosterSlotCopyAmbiguousEndpoints
                venueConfig
                intent.sourceRosterDay
                intent.targetRosterDay
                intent.sourceSlot
    pure $ case repeatedEndpoints of
        Left failure -> RosterDayDropBoundaryFailure (False, False) failure
        Right endpoints -> case copyRosterSlotToDay venueConfig intent.sourceRosterDay intent.targetRosterDay selections intent.sourceSlot of
            Left failure     -> RosterDayDropBoundaryFailure endpoints failure
            Right copiedSlot -> RosterDayDropBoundaryReady copiedSlot

resolveRosterTimelineDropBoundaries :: MoveRosterTimelineShiftIntent -> RosterTimelineDropBoundaryResolution
resolveRosterTimelineDropBoundaries intent =
    let startsAt = intent.timelineMoveStartsAt
        endsAt = addUTCTime (rosterShiftTimingElapsedSeconds intent.timelineSourceTiming) startsAt
     in case authoritativeBoundariesFromInstants intent.timelineSourceSlot.timezone startsAt endsAt Nothing Nothing of
        Left _ -> RosterTimelineDropInvalid invalidRosterSlotTimingMessage
        Right boundaries
            | not (authoritativeRosterIntervalIsOperationallyValid boundaries) ->
                RosterTimelineDropInvalid invalidRosterSlotTimingMessage
            | operationalDayForLocalTime (authoritativeStartLocalTime boundaries) /= intent.timelineTargetRosterDay.operationalDate ->
                RosterTimelineDropInvalid invalidRosterSlotTimingMessage
            | otherwise -> RosterTimelineDropBoundaryReady boundaries

validateRosterShiftDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Bool -> Text -> Text -> IO (Either Text MoveRosterShiftIntent)
validateRosterShiftDropIntent scope allowSemanticDayNoOp sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, parseRosterShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            maybeResult <- validateRosterShiftDropTarget scope allowSemanticDayNoOp sourceSlotId target
            pure (maybe (Left "Choose an open roster day in this week.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open roster day.")

validateRosterShiftDeleteDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text RosterSlot)
validateRosterShiftDeleteDropIntent scope sourceToken targetToken = do
    case (parseExistingSlotToken sourceToken, targetToken) of
        (Just rosterSlotId, "delete") -> do
            maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
            case maybeSlot of
                Nothing -> pure (Left "Drag an editable shift to the delete area.")
                Just rosterSlot -> do
                    rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
                    if rosterDayMatchesScope scope rosterDay && rosterDayIsEditable rosterDay
                        then pure (Right rosterSlot)
                        else pure (Left "Drag an editable shift from this roster week to the delete area.")
        _ -> pure (Left "Drag a shift to the delete area.")

validateRosterStaffDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> Text -> IO (Either Text RosterStaffDropIntent)
validateRosterStaffDropIntent scope sourceToken targetToken = do
    case (parseStaffToken sourceToken, parseExistingSlotToken targetToken, parseRosterShiftDropTargetToken targetToken) of
        (Just staffId, Just rosterSlotId, _) -> do
            maybeResult <- validateRosterStaffExistingShiftDropTarget scope staffId rosterSlotId
            pure (maybe (Left "Drop staff onto an editable shift in this roster week.") Right maybeResult)
        (Just staffId, _, Just createTarget) -> do
            maybeResult <- validateRosterStaffCreateShiftDropTarget scope staffId createTarget
            pure (maybe (Left "Drop staff onto an open add-shift target in this roster week.") Right maybeResult)
        (Just staffId, _, _) | isJust (parseTimelineShiftDropTargetToken targetToken) -> do
            maybeStaff <- fetchActiveStaffForCurrentVenue staffId
            staffEligible <- staffIsEligibleForRosterGroup staffId scope.rosterWindowRosterGroupId
            target <- validateRosterTimelineCreateTarget scope targetToken
            pure $ case (maybeStaff, staffEligible, target) of
                (Just staff, True, Right placement) -> Right RosterStaffCreateShiftDropIntent
                    { staffDropStaff = staff
                    , staffDropRosterDay = placement.timelineCreateDay
                    , staffDropSlotDefinition = placement.timelineCreateLane
                    , staffDropRowIndex = placement.timelineCreateRowIndex
                    , staffDropStartsAt = Just placement.timelineCreateStartsAt
                    }
                _ -> Left "Drop eligible staff onto an available timeline time."
        _ -> pure (Left "Drag a staff member onto a shift or add-shift target.")

validateRosterStaffExistingShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> Id Staff -> Id RosterSlot -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffExistingShiftDropTarget scope staffId rosterSlotId = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId scope.rosterWindowRosterGroupId
    maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
    case (maybeStaff, maybeSlot) of
        (Just staff, Just rosterSlot) -> do
            rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
            pure do
                _ <- either (const Nothing) Just (decodeRosterShiftTiming rosterSlot)
                guard (rosterDayMatchesScope scope rosterDay)
                guard (not rosterDay.isClosed)
                guard (rosterDay.publicationState == Draft || (rosterDay.publicationState == Published && rosterShiftIsOpen rosterSlot))
                guard staffEligible
                pure RosterStaffExistingShiftDropIntent { staffDropStaff = staff, staffDropSlot = rosterSlot, staffDropRosterDay = rosterDay }
        _ -> pure Nothing

validateRosterStaffCreateShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> Id Staff -> RosterShiftDropTarget -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffCreateShiftDropTarget scope staffId dropTarget = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId scope.rosterWindowRosterGroupId
    window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
    let maybeTarget = rosterWindowTarget
            scope.rosterWindowVenueId
            scope.rosterWindowRosterGroupId
            window
            (dropTargetRosterDayId dropTarget)
    case (maybeStaff, maybeTarget) of
        (Just staff, Just (targetRosterDay, targetSlotDefinitions)) -> do
            maybeResolvedTarget <- resolveRosterShiftDropPlacementWithLanes targetRosterDay targetSlotDefinitions dropTarget
            pure do
                guard (rosterDayMatchesScope scope targetRosterDay)
                guard (rosterDayIsEditable targetRosterDay)
                guard staffEligible
                (slotDefinition, rowIndex) <- maybeResolvedTarget
                pure RosterStaffCreateShiftDropIntent { staffDropStaff = staff, staffDropRosterDay = targetRosterDay, staffDropSlotDefinition = slotDefinition, staffDropRowIndex = rowIndex, staffDropStartsAt = Nothing }
        _ -> pure Nothing

-- Resolve projected days/lanes without materializing them. Only the eventual
-- CreateRosterSlot submission may persist this placement.
validateRosterTimelineCreateTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> Text -> IO (Either Text RosterTimelineCreateTarget)
validateRosterTimelineCreateTarget scope token = do
    result <- case parseTimelineShiftDropTargetToken token of
        Nothing -> pure Nothing
        Just target -> do
            window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
            case rosterWindowTarget scope.rosterWindowVenueId scope.rosterWindowRosterGroupId window target.timelineTargetRosterDayId of
                Just (day, lanes) | rosterDayMatchesScope scope day && rosterDayIsEditable day -> do
                    venueConfig <- fetchVenueConfig
                    slots <- query @RosterSlot
                        |> filterWhere (#rosterDayId, unpackId day.id)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                    let intervals = mapMaybe (either (const Nothing) (Just . rosterShiftTimingBoundaries) . decodeRosterShiftTiming) slots
                    pure do
                        lane <- find (\lane -> lane.id == target.timelineTargetSlotDefinitionId && isNothing lane.deletedAt) lanes
                        scale <- either (const Nothing) Just (timelineScaleForDay day.operationalDate
                            venueConfig.timePickerStartMinuteOfDay venueConfig.timePickerFinalSelectableMinuteOfDay
                            [(authoritativeStartsAt bounds, authoritativeEndsAt bounds) | bounds <- intervals])
                        guard (target.timelineTargetStartsAt `elem` timelineCreateInstants scale day.operationalDate)
                        (_, rowIndex) <- firstAvailableRosterDayPlacement day [lane] slots
                        pure (RosterTimelineCreateTarget day lane rowIndex target.timelineTargetStartsAt)
                _ -> pure Nothing
    pure (maybe (Left "Choose an available time in an editable timeline lane.") Right result)

validateRosterShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> Bool -> Id RosterSlot -> RosterShiftDropTarget -> IO (Maybe MoveRosterShiftIntent)
validateRosterShiftDropTarget scope allowSemanticDayNoOp sourceSlotId dropTarget = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId))
    case maybeSourceSlot of
        Nothing -> pure Nothing
        Just sourceSlot -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            let targetRosterDayId = dropTargetRosterDayId dropTarget
            maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, targetRosterDayId))
            case maybeTargetRosterDay of
                Nothing -> pure Nothing
                Just targetRosterDay -> do
                    maybeResolvedTarget <- resolveRosterShiftDropPlacement targetRosterDay dropTarget
                    let sourceHasValidAssignment = isRight (rosterShiftAssignment sourceSlot)
                    let targetIsOpen = not targetRosterDay.isClosed
                    let semanticSameDayNoOp = allowSemanticDayNoOp && isDayDropTarget dropTarget && sourceSlot.rosterDayId == unpackId targetRosterDay.id
                    pure do
                        guard (rosterDayMatchesScope scope sourceRosterDay)
                        guard (rosterDayMatchesScope scope targetRosterDay)
                        guard (rosterDayIsEditable sourceRosterDay)
                        guard sourceHasValidAssignment
                        guard targetIsOpen
                        case (semanticSameDayNoOp, maybeResolvedTarget) of
                            (True, Just (targetSlotDefinition, _)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex = sourceSlot.rowIndex, moveIsNoOp = True }
                            (False, Just (targetSlotDefinition, targetRowIndex)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex, moveIsNoOp = False }
                            _ -> Nothing

validateRosterTimelineShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Bool -> RosterWindowScope -> Id RosterSlot -> TimelineShiftDropTarget -> IO (Either RosterShiftIntegrityError (Maybe MoveRosterTimelineShiftIntent))
validateRosterTimelineShiftDropTarget isMove scope sourceSlotId target = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId) |> filterWhere (#deletedAt, Nothing))
    case maybeSourceSlot of
        Nothing -> pure (Right Nothing)
        Just sourceSlot -> case decodeRosterShiftTiming sourceSlot of
            Left failure -> pure (Left failure)
            Right sourceTiming -> do
                sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
                maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, target.timelineTargetRosterDayId))
                maybeTargetSlotDefinition <- case maybeTargetRosterDay of
                    Nothing -> pure Nothing
                    Just targetRosterDay -> resolveRosterLaneReference (Just targetRosterDay.id) target.timelineTargetSlotDefinitionId
                case (maybeTargetRosterDay, maybeTargetSlotDefinition) of
                    (Just targetRosterDay, Just targetSlotDefinition) -> do
                        venueConfig <- fetchVenueConfig
                        daySlots <- query @RosterSlot
                            |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetch
                        let intervals = mapMaybe (either (const Nothing) (Just . rosterShiftTimingBoundaries) . decodeRosterShiftTiming) daySlots
                            scale = timelineScaleForDay targetRosterDay.operationalDate
                                venueConfig.timePickerStartMinuteOfDay venueConfig.timePickerFinalSelectableMinuteOfDay
                                [(authoritativeStartsAt boundaries, authoritativeEndsAt boundaries) | boundaries <- intervals]
                            targetStart = target.timelineTargetStartsAt
                            targetEnd = addUTCTime (rosterShiftTimingElapsedSeconds sourceTiming) targetStart
                            sourceStart = authoritativeStartsAt (rosterShiftTimingBoundaries sourceTiming)
                            targetDefinitionMatchesWeek = targetSlotDefinition.rosterDayId == unpackId targetRosterDay.id
                            isNoOp = isMove && sourceSlot.rosterDayId == unpackId targetRosterDay.id
                                && sourceSlot.rosterLaneId == unpackId targetSlotDefinition.id
                                && sourceStart == targetStart
                            validTargetStart = isNoOp || case scale of
                                Left _ -> False
                                Right window -> targetStart >= window.scaleStartsAt
                                    && targetEnd <= window.scaleEndsAt
                                    && utcTimeToPOSIXSeconds targetStart / 300 == fromInteger (floor (utcTimeToPOSIXSeconds targetStart / 300))
                        maybeRowIndex <- resolveTimelineTargetRowIndex isMove sourceSlot targetRosterDay targetSlotDefinition
                        pure $ Right do
                            targetRowIndex <- maybeRowIndex
                            guard (rosterDayMatchesScope scope sourceRosterDay)
                            guard (rosterDayMatchesScope scope targetRosterDay)
                            guard (rosterDayIsEditable sourceRosterDay)
                            guard (rosterDayIsEditable targetRosterDay)
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
                                , timelineMoveStartsAt = targetStart
                                , timelineMoveIsNoOp = isNoOp
                                , timelineSourceTiming = sourceTiming
                                }
                    _ -> pure (Right Nothing)

rosterDayMatchesScope :: RosterWindowScope -> RosterDay -> Bool
rosterDayMatchesScope scope rosterDay =
    rosterDay.venueId == unpackId scope.rosterWindowVenueId
        && rosterDay.rosterGroupId == unpackId scope.rosterWindowRosterGroupId
        && rosterDay.operationalDate >= scope.rosterWindowStart
        && rosterDay.operationalDate < scope.rosterWindowEnd

rosterDayIsEditable :: RosterDay -> Bool
rosterDayIsEditable rosterDay =
    rosterDay.publicationState == Draft && not rosterDay.isClosed

resolveTimelineTargetRowIndex :: (?modelContext :: ModelContext) => Bool -> RosterSlot -> RosterDay -> RosterLane -> IO (Maybe Int)
resolveTimelineTargetRowIndex isMove sourceSlot targetRosterDay targetSlotDefinition = do
    daySlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
        |> filterWhere (#rosterLaneId, unpackId targetSlotDefinition.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let occupiedRows = Set.fromList [ slot.rowIndex | slot <- daySlots, not isMove || slot.id /= sourceSlot.id ]
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
        ["instant", rawRosterDayId, rawSlotDefinitionId, rawSeconds] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            seconds <- TextRead.readMaybe @Integer (cs rawSeconds)
            -- Bound untrusted epochs before timezone/calendar conversion.
            guard (seconds >= 0 && seconds <= 253402300799)
            pure TimelineShiftDropTarget
                { timelineTargetRosterDayId = rosterDayId
                , timelineTargetSlotDefinitionId = slotDefinitionId
                , timelineTargetStartsAt = posixSecondsToUTCTime (fromInteger seconds)
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

resolveRosterShiftDropPlacementWithLanes :: (?modelContext :: ModelContext) => RosterDay -> [RosterLane] -> RosterShiftDropTarget -> IO (Maybe (RosterLane, Int))
resolveRosterShiftDropPlacementWithLanes targetRosterDay targetSlotDefinitions = \case
    PreciseRosterShiftDropTarget _ targetSlotDefinitionId targetRowIndex -> do
        let maybeTargetSlotDefinition = find ((== targetSlotDefinitionId) . (.id)) targetSlotDefinitions
        targetExists <- maybe (pure False) (\lane -> rosterSlotCellExists targetRosterDay.id lane.id targetRowIndex) maybeTargetSlotDefinition
        pure do
            targetSlotDefinition <- maybeTargetSlotDefinition
            guard (targetRowIndex >= 0)
            guard (targetSlotDefinition.rosterDayId == unpackId targetRosterDay.id)
            guard (isNothing targetSlotDefinition.deletedAt)
            guard (not targetExists)
            pure (targetSlotDefinition, targetRowIndex)
    DayRosterShiftDropTarget _ -> do
        daySlots <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
        pure (firstAvailableRosterDayPlacement targetRosterDay targetSlotDefinitions daySlots)

resolveRosterShiftDropPlacement :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterDay -> RosterShiftDropTarget -> IO (Maybe (RosterLane, Int))
resolveRosterShiftDropPlacement targetRosterDay = \case
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
