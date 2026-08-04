module Application.RosterShiftAssignment
    ( RosterShiftAssignment (..)
    , applyRosterShiftAssignment
    , rosterShiftAssignment
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

rosterShiftAssignment :: RosterSlot -> Either Text RosterShiftAssignment
rosterShiftAssignment slot =
    case (slot.assignmentState, slot.staffId) of
        ("staff", Just staffId) -> Right (StaffAssignment (Id staffId))
        ("open", Nothing) -> Right OpenAssignment
        _ -> Left "Roster shift has an invalid persisted assignment shape."
