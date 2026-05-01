module Application.Helper.Conflict where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Data.Time.Calendar (Day)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ModelSupport (unpackId)
import IHP.Prelude

data ConflictSeverity
    = CriticalConflict
    | AdvisoryConflict
    deriving (Eq, Show, Ord)

data ConflictType
    = DuplicateAssignment
    | LeaveConflict
    | LateToEarlyConflict
    | ShiftPreferenceDayUnavailable
    | ShiftPreferenceSlotMismatch
    | IdealShiftThresholdExceeded
    deriving (Eq, Show)

data RosterConflict = RosterConflict
    { conflictType :: ConflictType
    , severity     :: ConflictSeverity
    , message      :: Text
    } deriving (Eq, Show)

getConflictSeverity :: ConflictType -> ConflictSeverity
getConflictSeverity DuplicateAssignment           = CriticalConflict
getConflictSeverity LeaveConflict                 = CriticalConflict
getConflictSeverity LateToEarlyConflict           = CriticalConflict
getConflictSeverity ShiftPreferenceDayUnavailable = AdvisoryConflict
getConflictSeverity ShiftPreferenceSlotMismatch   = AdvisoryConflict
getConflictSeverity IdealShiftThresholdExceeded   = AdvisoryConflict

conflictPriority :: ConflictType -> Int
conflictPriority DuplicateAssignment           = 1
conflictPriority LeaveConflict                 = 2
conflictPriority LateToEarlyConflict           = 3
conflictPriority ShiftPreferenceDayUnavailable = 4
conflictPriority ShiftPreferenceSlotMismatch   = 5
conflictPriority IdealShiftThresholdExceeded   = 6

instance Ord ConflictType where
    compare a b = compare (conflictPriority a) (conflictPriority b)

instance Ord RosterConflict where
    compare a b = compare a.conflictType b.conflictType

-- | Roster data needed to evaluate conflicts for a staff member in a given slot
data ConflictContext = ConflictContext
    { slot                          :: RosterSlot
    , rosterGroupId                 :: UUID
    , weekSlots                     :: [RosterSlot] -- All slots for this staff in the current week
    , daySlots                      :: [RosterSlot]  -- All slots for this staff on the current day
    , weekRosterDays                :: [RosterDay] -- All days for the current week
    , leaveRequests                 :: [LeaveRequest] -- All leave requests for this staff
    , shiftPreferences              :: [StaffShiftPreference] -- All recurring shift preferences for this staff
    , rosterDayDate                 :: Day -- The derived date of the roster day
    , lateToEarlyMinStartGapMinutes :: Int -- venue config threshold
    , staffIdealShifts              :: Maybe Int -- staff.idealShiftsPerWeek
    }

evaluateConflicts :: ConflictContext -> [RosterConflict]
evaluateConflicts ctx =
    sort $ catMaybes
        [ checkDuplicateAssignment ctx
        , checkLeaveConflict ctx
        , checkLateToEarlyConflict ctx
        , checkShiftPreferenceDayUnavailable ctx
        , checkShiftPreferenceStartWindowMismatch ctx
        , checkIdealShiftThreshold ctx
        ]

primaryConflict :: [RosterConflict] -> Maybe RosterConflict
primaryConflict conflicts = listToMaybe (sort conflicts)

checkDuplicateAssignment :: ConflictContext -> Maybe RosterConflict
checkDuplicateAssignment ctx =
    if length ctx.daySlots > 1
        then Just RosterConflict
            { conflictType = DuplicateAssignment
            , severity = getConflictSeverity DuplicateAssignment
            , message = "Multiple shifts rostered on the same day."
            }
        else Nothing

checkLeaveConflict :: ConflictContext -> Maybe RosterConflict
checkLeaveConflict ctx =
    let
        isOnLeave = any overlaps ctx.leaveRequests
        overlaps req =
            let status = parseLeaveRequestStatus req.status
            in status == Just LeaveApproved &&
               ctx.rosterDayDate >= req.startDate &&
               ctx.rosterDayDate < req.endDate
    in if isOnLeave
        then Just RosterConflict
            { conflictType = LeaveConflict
            , severity = getConflictSeverity LeaveConflict
            , message = "Staff member is on approved leave."
            }
        else Nothing

checkShiftPreferenceDayUnavailable :: ConflictContext -> Maybe RosterConflict
checkShiftPreferenceDayUnavailable ctx =
    case ctx.slot.staffId of
        Nothing -> Nothing
        Just _ ->
            let dayPreferences = shiftPreferencesForDay ctx
             in if null dayPreferences
                    then Just RosterConflict
                        { conflictType = ShiftPreferenceDayUnavailable
                        , severity = getConflictSeverity ShiftPreferenceDayUnavailable
                        , message = "Preference conflict"
                        }
                    else Nothing

checkShiftPreferenceStartWindowMismatch :: ConflictContext -> Maybe RosterConflict
checkShiftPreferenceStartWindowMismatch ctx =
    case (ctx.slot.staffId, ctx.slot.startTime) of
        (Just _, Just startTime) ->
            case shiftPreferencesForDay ctx of
                [] -> Nothing
                dayPreference:_ ->
                    let startMinute = todHour startTime * 60 + todMin startTime
                        preferredStartMinute = dayPreference.preferredStartHour * 60
                        preferredEndMinute = dayPreference.preferredEndHour * 60
                     in if startMinute < preferredStartMinute || startMinute > preferredEndMinute
                            then Just RosterConflict
                                { conflictType = ShiftPreferenceSlotMismatch
                                , severity = getConflictSeverity ShiftPreferenceSlotMismatch
                                , message = "Preferred start window conflict"
                                }
                            else Nothing
        _ -> Nothing

shiftPreferencesForDay :: ConflictContext -> [StaffShiftPreference]
shiftPreferencesForDay ctx =
    let weekdayIndex = weekdayIndexForDay ctx.rosterDayDate
     in filter
            (\preference -> preference.weekdayIndex == weekdayIndex)
            ctx.shiftPreferences

checkLateToEarlyConflict :: ConflictContext -> Maybe RosterConflict
checkLateToEarlyConflict ctx
    | ctx.lateToEarlyMinStartGapMinutes <= 0 = Nothing
    | otherwise =
        case findIndex ((== get #id ctx.slot) . fst) timeline of
            Nothing -> Nothing
            Just currentIndex ->
                let previousGap = if currentIndex > 0 then Just (snd (timeline !! currentIndex) - snd (timeline !! (currentIndex - 1))) else Nothing
                    nextGap = if currentIndex + 1 < length timeline then Just (snd (timeline !! (currentIndex + 1)) - snd (timeline !! currentIndex)) else Nothing
                    isBelowThreshold = any (< ctx.lateToEarlyMinStartGapMinutes) (catMaybes [previousGap, nextGap])
                 in if isBelowThreshold
                        then Just RosterConflict
                            { conflictType = LateToEarlyConflict
                            , severity = getConflictSeverity LateToEarlyConflict
                            , message = "Start-to-start gap is below venue minimum."
                            }
                        else Nothing
    where
        timeline =
            ctx.weekSlots
                |> mapMaybe (\candidate -> (,) (get #id candidate) <$> slotStartMinuteOfWeek ctx.weekRosterDays candidate)
                |> sortBy (comparing snd)

slotStartMinuteOfWeek :: [RosterDay] -> RosterSlot -> Maybe Int
slotStartMinuteOfWeek rosterDays candidate = do
    dayOffset <- findDayOffset candidate.rosterDayId
    startTime <- candidate.startTime
    let minutesFromDayStart = todHour startTime * 60 + todMin startTime
    pure (dayOffset * 1440 + minutesFromDayStart)
    where
        findDayOffset rosterDayId =
            rosterDays
                |> find (\day -> unpackId (get #id day) == rosterDayId)
                |> fmap (.dayOffset)

checkIdealShiftThreshold :: ConflictContext -> Maybe RosterConflict
checkIdealShiftThreshold ctx =
    case ctx.staffIdealShifts of
        Just threshold ->
            if length ctx.weekSlots > threshold
                then Just RosterConflict
                    { conflictType = IdealShiftThresholdExceeded
                    , severity = getConflictSeverity IdealShiftThresholdExceeded
                    , message = "Ideal shifts exceeded"
                    }
                else Nothing
        Nothing -> Nothing
