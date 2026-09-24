module Web.Timesheets.RosterPrefill
    ( TimesheetRosterPrefill (..)
    , newTimesheetEntryFromRosterPrefill
    , timesheetRosterPrefillOperationalDate
    , timesheetRosterPrefillEndTime
    , timesheetRosterPrefillStartTime
    ) where

import Application.VenueTime.Model
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (newRecord, unpackId)
import IHP.Prelude
import Web.Timesheets.RosterGroupClassification

-- Roster prefills carry the same authoritative boundary value that will be
-- persisted. Local facts are projections, never a second authority.
data TimesheetRosterPrefill = TimesheetRosterPrefill
    { prefillRosterSlotId    :: !(Id RosterSlot)
    , prefillOperationalDate :: !Day
    , prefillStaffId         :: !UUID.UUID
    , prefillShiftTypeId     :: !UUID.UUID
    , prefillRosterGroupId   :: !UUID.UUID
    , prefillBoundaries      :: !AuthoritativeBoundaries
    }
    deriving (Eq, Show)

newTimesheetEntryFromRosterPrefill :: UUID.UUID -> TimesheetRosterPrefill -> TimesheetEntry
newTimesheetEntryFromRosterPrefill venueId rosterPrefill =
    newRecord @TimesheetEntry
        |> set #venueId venueId
        |> set #staffId rosterPrefill.prefillStaffId
        |> set #shiftTypeId rosterPrefill.prefillShiftTypeId
        |> set #sourceRosterSlotId (Just (unpackId rosterPrefill.prefillRosterSlotId))
        |> applyTimesheetRosterGroupClassification (TimesheetInRosterGroup rosterPrefill.prefillRosterGroupId)
        |> set #operationalDate rosterPrefill.prefillOperationalDate
        |> applyTimesheetEntryBoundaries rosterPrefill.prefillBoundaries

timesheetRosterPrefillOperationalDate :: TimesheetRosterPrefill -> Day
timesheetRosterPrefillOperationalDate = (.prefillOperationalDate)

timesheetRosterPrefillStartTime :: TimesheetRosterPrefill -> TimeOfDay
timesheetRosterPrefillStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . (.prefillBoundaries)

timesheetRosterPrefillEndTime :: TimesheetRosterPrefill -> TimeOfDay
timesheetRosterPrefillEndTime = (.localTimeOfDay) . authoritativeEndLocalTime . (.prefillBoundaries)
