module Web.RosterWeeks.Conflicts
    ( buildSlotConflicts
    ) where

import Application.Helper.Conflict
import Data.Coerce (coerce)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Time.Calendar as Calendar
import Web.Controller.Prelude

buildSlotConflicts :: (?modelContext :: ModelContext) => Id RosterGroup -> Int -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflicts rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate rosterDays allSlots staffMembers = do
    let assignedStaffIds = nub $ mapMaybe (.staffId) allSlots
    if null assignedStaffIds
        then pure []
        else do
            leaveRequests <- query @LeaveRequest
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            shiftPreferences <- query @StaffShiftPreference
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            let dayById = Map.fromList [ (coerce (get #id day), day) | day <- rosterDays ]
            let weekSlotsByStaff = Map.fromListWith (<>) [ (staffId, [slot]) | slot <- allSlots, staffId <- maybeToList slot.staffId ]
            let daySlotsByStaff = Map.fromListWith (<>) [ ((slot.rosterDayId, staffId), [slot]) | slot <- allSlots, staffId <- maybeToList slot.staffId ]
            let staffIdealShiftsById = Map.fromList [ (coerce (get #id staff), staff.idealShiftsPerWeek) | staff <- staffMembers ]
            let leaveRequestsByStaff = Map.fromListWith (<>) [ (leaveRequest.staffId, [leaveRequest]) | leaveRequest <- leaveRequests ]
            let shiftPreferencesByStaff = Map.fromListWith (<>) [ (preference.staffId, [preference]) | preference <- shiftPreferences ]
            let conflictsBySlot = mapMaybe (conflictsForSlot dayById weekSlotsByStaff daySlotsByStaff staffIdealShiftsById leaveRequestsByStaff shiftPreferencesByStaff) allSlots
            pure conflictsBySlot
    where
        conflictsForSlot dayById weekSlotsByStaff daySlotsByStaff staffIdealShiftsById leaveRequestsByStaff shiftPreferencesByStaff slot = do
            staffUuid <- slot.staffId
            day <- Map.lookup slot.rosterDayId dayById
            let weekSlotsForStaff = Map.findWithDefault [] staffUuid weekSlotsByStaff
            let daySlotsForStaff = Map.findWithDefault [] (slot.rosterDayId, staffUuid) daySlotsByStaff
            let staffIdealShifts = Map.lookup staffUuid staffIdealShiftsById
            let leaveRequestsForStaff = Map.findWithDefault [] staffUuid leaveRequestsByStaff
            let shiftPreferencesForStaff = Map.findWithDefault [] staffUuid shiftPreferencesByStaff
            let rosterDayDate = Calendar.addDays (toInteger day.dayOffset) weekStartDate
            let conflicts = evaluateConflicts ConflictContext
                    { slot
                    , rosterGroupId = unpackId rosterGroupId
                    , weekSlots = weekSlotsForStaff
                    , daySlots = daySlotsForStaff
                    , weekRosterDays = rosterDays
                    , leaveRequests = leaveRequestsForStaff
                    , shiftPreferences = shiftPreferencesForStaff
                    , rosterDayDate
                    , lateToEarlyMinStartGapMinutes
                    , staffIdealShifts
                    }
            if null conflicts
                then Nothing
                else Just (get #id slot, conflicts)
