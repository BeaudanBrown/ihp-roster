module Web.Timesheets.Suggestion
    ( TimesheetSuggestion (..)
    , newTimesheetEntryFromSuggestion
    , timesheetSuggestionOperationalDate
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
    { suggestionRosterSlotId    :: !(Id RosterSlot)
    , suggestionOperationalDate :: !Day
    , suggestionStaffId         :: !UUID.UUID
    , suggestionShiftTypeId     :: !UUID.UUID
    , suggestionBoundaries      :: !AuthoritativeBoundaries
    }
    deriving (Eq, Show)

newTimesheetEntryFromSuggestion :: UUID.UUID -> TimesheetSuggestion -> TimesheetEntry
newTimesheetEntryFromSuggestion venueId suggestion =
    newRecord @TimesheetEntry
        |> set #venueId venueId
        |> set #staffId suggestion.suggestionStaffId
        |> set #shiftTypeId suggestion.suggestionShiftTypeId
        |> set #sourceRosterSlotId (Just (unpackId suggestion.suggestionRosterSlotId))
        |> set #operationalDate suggestion.suggestionOperationalDate
        |> applyTimesheetEntryBoundaries suggestion.suggestionBoundaries

timesheetSuggestionOperationalDate :: TimesheetSuggestion -> Day
timesheetSuggestionOperationalDate = (.suggestionOperationalDate)

timesheetSuggestionStartTime :: TimesheetSuggestion -> TimeOfDay
timesheetSuggestionStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . (.suggestionBoundaries)
