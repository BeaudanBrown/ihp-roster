module Web.Timesheets.Suggestion
    ( TimesheetSuggestion (..)
    , newTimesheetEntryFromSuggestion
    ) where

import Data.Time.Calendar (Day)
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (newRecord, unpackId)
import IHP.Prelude

data TimesheetSuggestion = TimesheetSuggestion
    { suggestionRosterSlotId :: !(Id RosterSlot)
    , suggestionStaffId      :: !UUID.UUID
    , suggestionShiftTypeId  :: !UUID.UUID
    , suggestionWorkedOn     :: !Day
    , suggestionStartTime    :: !TimeOfDay
    , suggestionEndTime      :: !TimeOfDay
    , suggestionHadBreak     :: !Bool
    , suggestionBreakStart   :: !(Maybe TimeOfDay)
    , suggestionBreakEnd     :: !(Maybe TimeOfDay)
    , suggestionBreakMinutes :: !Int
    }
    deriving (Eq, Show)

newTimesheetEntryFromSuggestion :: UUID.UUID -> TimesheetSuggestion -> TimesheetEntry
newTimesheetEntryFromSuggestion venueId suggestion =
    newRecord @TimesheetEntry
        |> set #venueId venueId
        |> set #staffId suggestion.suggestionStaffId
        |> set #shiftTypeId suggestion.suggestionShiftTypeId
        |> set #workedOn suggestion.suggestionWorkedOn
        |> set #startTime suggestion.suggestionStartTime
        |> set #endTime suggestion.suggestionEndTime
        |> set #hadBreak suggestion.suggestionHadBreak
        |> set #breakStartTime suggestion.suggestionBreakStart
        |> set #breakEndTime suggestion.suggestionBreakEnd
        |> set #breakMinutes suggestion.suggestionBreakMinutes
        |> set #sourceRosterSlotId (Just (unpackId suggestion.suggestionRosterSlotId))
