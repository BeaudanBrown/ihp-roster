module Application.Helper.Conflict where

import IHP.Prelude

data ConflictSeverity
    = CriticalConflict
    | AdvisoryConflict
    deriving (Eq, Show, Ord)

data ConflictType
    = ConflictDetailsUnavailable
    | InvalidRosterTiming
    | DuplicateAssignment
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
getConflictSeverity ConflictDetailsUnavailable    = CriticalConflict
getConflictSeverity InvalidRosterTiming           = CriticalConflict
getConflictSeverity DuplicateAssignment           = CriticalConflict
getConflictSeverity LeaveConflict                 = CriticalConflict
getConflictSeverity LateToEarlyConflict           = CriticalConflict
getConflictSeverity ShiftPreferenceDayUnavailable = AdvisoryConflict
getConflictSeverity ShiftPreferenceSlotMismatch   = AdvisoryConflict
getConflictSeverity IdealShiftThresholdExceeded   = AdvisoryConflict

conflictPriority :: ConflictType -> Int
conflictPriority ConflictDetailsUnavailable    = 0
conflictPriority InvalidRosterTiming           = 0
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

primaryConflict :: [RosterConflict] -> Maybe RosterConflict
primaryConflict conflicts = listToMaybe (sort conflicts)
