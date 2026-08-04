module Application.RosterShiftAssignment
    ( RosterShiftAssignment (..)
    , applyRosterShiftAssignment
    , copyRosterShiftAssignment
    , rosterShiftAssignment
    , rosterShiftIsOpen
    , rosterShiftIsStaffAssigned
    ) where

import Generated.Types
import IHP.HaskellSupport (set)
import IHP.ModelSupport (unpackId)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude

data RosterShiftAssignment
    = StaffAssignment !(Id Staff)
    | OpenAssignment
    deriving (Eq, Show)

applyRosterShiftAssignment :: RosterShiftAssignment -> RosterSlot -> RosterSlot
applyRosterShiftAssignment assignment slot =
    case assignment of
        StaffAssignment staffId ->
            slot
                |> set #assignmentState "staff"
                |> set #staffId (Just (unpackId staffId))
        OpenAssignment ->
            slot
                |> set #assignmentState "open"
                |> set #staffId Nothing

copyRosterShiftAssignment :: RosterSlot -> RosterSlot -> Either Text RosterSlot
copyRosterShiftAssignment source target =
    (`applyRosterShiftAssignment` target) <$> rosterShiftAssignment source

rosterShiftIsOpen :: RosterSlot -> Bool
rosterShiftIsOpen slot = rosterShiftAssignment slot == Right OpenAssignment

rosterShiftIsStaffAssigned :: RosterSlot -> Bool
rosterShiftIsStaffAssigned slot =
    case rosterShiftAssignment slot of
        Right StaffAssignment {} -> True
        _                        -> False

rosterShiftAssignment :: RosterSlot -> Either Text RosterShiftAssignment
rosterShiftAssignment slot =
    case (slot.assignmentState, slot.staffId) of
        ("staff", Just staffId) -> Right (StaffAssignment (Id staffId))
        ("open", Nothing) -> Right OpenAssignment
        _ -> Left "Roster shift has an invalid persisted assignment shape."
