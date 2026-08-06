module Web.Timesheets.Suggestion
    ( TimesheetSuggestion (..)
    , newTimesheetEntryFromSuggestion
    , timesheetSuggestionWorkedOn
    , timesheetSuggestionStartTime
    ) where

import Application.VenueTime.Model
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (newRecord, unpackId)
import IHP.Prelude

-- Suggestions carry the same authoritative boundary value that will be
-- persisted. Local facts are projections, never a second authority.
data TimesheetSuggestion = TimesheetSuggestion
    { suggestionRosterSlotId :: !(Id RosterSlot)
    , suggestionStaffId      :: !UUID.UUID
    , suggestionShiftTypeId  :: !UUID.UUID
    , suggestionBoundaries   :: !AuthoritativeBoundaries
    }
    deriving (Eq, Show)

newTimesheetEntryFromSuggestion :: UUID.UUID -> TimesheetSuggestion -> TimesheetEntry
newTimesheetEntryFromSuggestion venueId suggestion =
    newRecord @TimesheetEntry
        |> set #venueId venueId
        |> set #staffId suggestion.suggestionStaffId
        |> set #shiftTypeId suggestion.suggestionShiftTypeId
        |> set #sourceRosterSlotId (Just (unpackId suggestion.suggestionRosterSlotId))
        |> applyTimesheetEntryBoundaries suggestion.suggestionBoundaries

timesheetSuggestionWorkedOn :: TimesheetSuggestion -> Day
timesheetSuggestionWorkedOn = (.localDay) . authoritativeStartLocalTime . (.suggestionBoundaries)

timesheetSuggestionStartTime :: TimesheetSuggestion -> TimeOfDay
timesheetSuggestionStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . (.suggestionBoundaries)
