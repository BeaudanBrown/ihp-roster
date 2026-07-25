module Web.Timesheets.Suggestion
    ( TimesheetSuggestion (..)
    , newTimesheetEntryFromSuggestion
    , timesheetSuggestionWorkedOn
    , timesheetSuggestionStartTime
    , timesheetSuggestionEndTime
    , timesheetSuggestionHadBreak
    , timesheetSuggestionBreakStartTime
    , timesheetSuggestionBreakEndTime
    , timesheetSuggestionBreakMinutes
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

timesheetSuggestionEndTime :: TimesheetSuggestion -> TimeOfDay
timesheetSuggestionEndTime = (.localTimeOfDay) . authoritativeEndLocalTime . (.suggestionBoundaries)

timesheetSuggestionHadBreak :: TimesheetSuggestion -> Bool
timesheetSuggestionHadBreak = isJust . authoritativeBreakStartsAt . (.suggestionBoundaries)

timesheetSuggestionBreakStartTime :: TimesheetSuggestion -> Maybe TimeOfDay
timesheetSuggestionBreakStartTime = fmap (.localTimeOfDay) . authoritativeBreakStartLocalTime . (.suggestionBoundaries)

timesheetSuggestionBreakEndTime :: TimesheetSuggestion -> Maybe TimeOfDay
timesheetSuggestionBreakEndTime = fmap (.localTimeOfDay) . authoritativeBreakEndLocalTime . (.suggestionBoundaries)

timesheetSuggestionBreakMinutes :: TimesheetSuggestion -> Int
timesheetSuggestionBreakMinutes = floor . (/ 60) . authoritativeBreakElapsedSeconds . (.suggestionBoundaries)
