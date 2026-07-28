module Application.PayAssignment
    ( StaffPayAssignment (..)
    , ShiftPayAssignment (..)
    , EffectivePayAssignment (..)
    , PayAssignmentError (..)
    , resolvePayAssignment
    , staffAssignmentAllowsTimesheets
    , staffAssignmentSuppressesTimesheets
    , shiftAssignmentAllowsTimesheets
    , shiftAssignmentSuppressesTimesheets
    , selectableStaffAssignmentMode
    , selectableShiftAssignmentMode
    , staffPayAssignmentRequiresRemediation
    , shiftPayAssignmentRequiresRemediation
    ) where

import Generated.Types
import IHP.ModelSupport (Id)
import IHP.Prelude

-- | Persisted staff facts required to resolve one roster pay disposition.
data StaffPayAssignment = StaffPayAssignment
    { staffAssignmentMode              :: !PayAssignmentModeEnum
    , staffAssignmentAwardLevelId      :: !(Maybe (Id AwardLevel))
    , staffAssignmentImportedPayItemId :: !(Maybe (Id XeroImportedPayItem))
    }
    deriving (Eq, Show)

-- | Persisted shift-type facts required to resolve one roster pay disposition.
data ShiftPayAssignment = ShiftPayAssignment
    { shiftAssignmentMode              :: !PayAssignmentModeEnum
    , shiftAssignmentAwardLevelId      :: !(Maybe (Id AwardLevel))
    , shiftAssignmentImportedPayItemId :: !(Maybe (Id XeroImportedPayItem))
    }
    deriving (Eq, Show)

-- | The only effective outcomes consumed by roster, Timesheet, and wage callers.
data EffectivePayAssignment
    = EffectiveAwardRate !(Id AwardLevel)
    | EffectiveXeroRate !(Id XeroImportedPayItem)
    | EffectiveRosterOnly
    | InvalidPayAssignment { payAssignmentErrors :: ![PayAssignmentError] }
    deriving (Eq, Show)

data PayAssignmentError
    = InvalidStaffAssignmentShape !PayAssignmentModeEnum
    | InvalidShiftAssignmentShape !PayAssignmentModeEnum
    | LegacyStaffAssignmentRequiresRemediation
    deriving (Eq, Show)

-- | Normal staff mutations can only produce selectable modes. Supplying both
-- rate kinds is anomalous and must be rejected by the caller.
selectableStaffAssignmentMode :: Maybe award -> Maybe xero -> Maybe PayAssignmentModeEnum
selectableStaffAssignmentMode award xero =
    selectableMode RosterOnly (rateReferenceShape award xero)

-- | A shift with no override explicitly delegates to the staff assignment.
selectableShiftAssignmentMode :: Maybe award -> Maybe xero -> Maybe PayAssignmentModeEnum
selectableShiftAssignmentMode award xero =
    selectableMode StaffDefault (rateReferenceShape award xero)

selectableMode :: PayAssignmentModeEnum -> RateReferenceShape -> Maybe PayAssignmentModeEnum
selectableMode emptyMode = \case
    AwardReference       -> Just AwardRate
    XeroReference        -> Just XeroRate
    NoRateReference      -> Just emptyMode
    ConflictingReferences -> Nothing

data RateReferenceShape
    = AwardReference
    | XeroReference
    | NoRateReference
    | ConflictingReferences

rateReferenceShape :: Maybe award -> Maybe xero -> RateReferenceShape
rateReferenceShape award xero
    | isJust award && isNothing xero = AwardReference
    | isNothing award && isJust xero = XeroReference
    | isNothing award && isNothing xero = NoRateReference
    | otherwise = ConflictingReferences

resolvePayAssignment :: StaffPayAssignment -> ShiftPayAssignment -> EffectivePayAssignment
resolvePayAssignment staff shift =
    case validateStaffAssignment staff <> validateShiftAssignment shift of
        errors@(_ : _) -> InvalidPayAssignment errors
        []             -> resolveValidAssignments staff shift

resolveValidAssignments :: StaffPayAssignment -> ShiftPayAssignment -> EffectivePayAssignment
resolveValidAssignments staff shift
    | staff.staffAssignmentMode == RosterOnly = EffectiveRosterOnly
    | shift.shiftAssignmentMode == RosterOnly = EffectiveRosterOnly
    | shift.shiftAssignmentMode == AwardRate =
        maybe invalidShift EffectiveAwardRate shift.shiftAssignmentAwardLevelId
    | shift.shiftAssignmentMode == XeroRate =
        maybe invalidShift EffectiveXeroRate shift.shiftAssignmentImportedPayItemId
    | staff.staffAssignmentMode == AwardRate =
        maybe invalidStaff EffectiveAwardRate staff.staffAssignmentAwardLevelId
    | staff.staffAssignmentMode == XeroRate =
        maybe invalidStaff EffectiveXeroRate staff.staffAssignmentImportedPayItemId
    | otherwise = InvalidPayAssignment [InvalidShiftAssignmentShape shift.shiftAssignmentMode]
  where
    invalidStaff = InvalidPayAssignment [InvalidStaffAssignmentShape staff.staffAssignmentMode]
    invalidShift = InvalidPayAssignment [InvalidShiftAssignmentShape shift.shiftAssignmentMode]

staffAssignmentAllowsTimesheets :: StaffPayAssignment -> Bool
staffAssignmentAllowsTimesheets assignment =
    null (validateStaffAssignment assignment)
        && assignment.staffAssignmentMode `elem` [AwardRate, XeroRate]

staffAssignmentSuppressesTimesheets :: StaffPayAssignment -> Bool
staffAssignmentSuppressesTimesheets assignment =
    assignment.staffAssignmentMode == RosterOnly && null (validateStaffAssignment assignment)

shiftAssignmentAllowsTimesheets :: ShiftPayAssignment -> Bool
shiftAssignmentAllowsTimesheets assignment =
    null (validateShiftAssignment assignment)
        && assignment.shiftAssignmentMode `elem` [StaffDefault, AwardRate, XeroRate]

shiftAssignmentSuppressesTimesheets :: ShiftPayAssignment -> Bool
shiftAssignmentSuppressesTimesheets assignment =
    assignment.shiftAssignmentMode == RosterOnly && null (validateShiftAssignment assignment)

validateStaffAssignment :: StaffPayAssignment -> [PayAssignmentError]
validateStaffAssignment assignment =
    case assignment.staffAssignmentMode of
        AwardRate
            | hasOnlyAward assignment.staffAssignmentAwardLevelId assignment.staffAssignmentImportedPayItemId -> []
        XeroRate
            | hasOnlyXero assignment.staffAssignmentAwardLevelId assignment.staffAssignmentImportedPayItemId -> []
        RosterOnly
            | hasNoRate assignment.staffAssignmentAwardLevelId assignment.staffAssignmentImportedPayItemId -> []
        LegacyUnresolved
            | hasNoRate assignment.staffAssignmentAwardLevelId assignment.staffAssignmentImportedPayItemId -> [LegacyStaffAssignmentRequiresRemediation]
        _ -> [InvalidStaffAssignmentShape assignment.staffAssignmentMode]

validateShiftAssignment :: ShiftPayAssignment -> [PayAssignmentError]
validateShiftAssignment assignment =
    case assignment.shiftAssignmentMode of
        AwardRate
            | hasOnlyAward assignment.shiftAssignmentAwardLevelId assignment.shiftAssignmentImportedPayItemId -> []
        XeroRate
            | hasOnlyXero assignment.shiftAssignmentAwardLevelId assignment.shiftAssignmentImportedPayItemId -> []
        RosterOnly
            | hasNoRate assignment.shiftAssignmentAwardLevelId assignment.shiftAssignmentImportedPayItemId -> []
        StaffDefault
            | hasNoRate assignment.shiftAssignmentAwardLevelId assignment.shiftAssignmentImportedPayItemId -> []
        _ -> [InvalidShiftAssignmentShape assignment.shiftAssignmentMode]

hasOnlyAward :: Maybe award -> Maybe xero -> Bool
hasOnlyAward award xero = isJust award && isNothing xero

hasOnlyXero :: Maybe award -> Maybe xero -> Bool
hasOnlyXero award xero = isNothing award && isJust xero

hasNoRate :: Maybe award -> Maybe xero -> Bool
hasNoRate award xero = isNothing award && isNothing xero

-- | A selected reference must still be present in the currently selectable
-- inventory. Callers supply active Award and venue-valid Xero ids.
staffPayAssignmentRequiresRemediation :: [Id AwardLevel] -> [Id XeroImportedPayItem] -> StaffPayAssignment -> Bool
staffPayAssignmentRequiresRemediation activeAwardIds activeXeroIds assignment =
    case assignment.staffAssignmentMode of
        LegacyUnresolved -> True
        AwardRate -> maybe True (`notElem` activeAwardIds) assignment.staffAssignmentAwardLevelId
        XeroRate -> maybe True (`notElem` activeXeroIds) assignment.staffAssignmentImportedPayItemId
        RosterOnly -> False
        StaffDefault -> True

shiftPayAssignmentRequiresRemediation :: [Id AwardLevel] -> [Id XeroImportedPayItem] -> ShiftPayAssignment -> Bool
shiftPayAssignmentRequiresRemediation activeAwardIds activeXeroIds assignment =
    case assignment.shiftAssignmentMode of
        AwardRate -> maybe True (`notElem` activeAwardIds) assignment.shiftAssignmentAwardLevelId
        XeroRate -> maybe True (`notElem` activeXeroIds) assignment.shiftAssignmentImportedPayItemId
        RosterOnly -> False
        StaffDefault -> False
        LegacyUnresolved -> True
