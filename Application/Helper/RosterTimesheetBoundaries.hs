module Application.Helper.RosterTimesheetBoundaries
    ( RosterSlotBoundaryError (..)
    , projectRosterSlotTimesheetBoundaries
    ) where

import Application.Helper.TimeRules (authoritativeRosterIntervalIsOperationallyValid,
                                     automaticMealBreakMinutes,
                                     automaticMealBreakStartOffsetMinutes,
                                     automaticMealBreakThresholdMinutes)
import Application.VenueTime.Model
import qualified Application.VenueTime.Seconds as Seconds
import qualified Data.Bifunctor as Bifunctor
import Generated.Types
import IHP.Prelude

data RosterSlotBoundaryError
    = RosterSlotBoundariesIncomplete
    | RosterSlotBoundariesInvalid !BoundaryModelError
    | RosterSlotDurationUnsupported
    deriving (Eq, Show)

-- | Project the exact authoritative boundary snapshot materialized by a
-- Timesheet roster prefill, including its automatic unpaid meal break.
projectRosterSlotTimesheetBoundaries :: RosterSlot -> Either RosterSlotBoundaryError AuthoritativeBoundaries
projectRosterSlotTimesheetBoundaries slot = do
    startsAt <- maybe (Left RosterSlotBoundariesIncomplete) Right slot.startsAt
    endsAt <- maybe (Left RosterSlotBoundariesIncomplete) Right slot.endsAt
    grossBoundaries <- Bifunctor.first RosterSlotBoundariesInvalid $
        authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing
    unless (authoritativeRosterIntervalIsOperationallyValid grossBoundaries) $
        Left RosterSlotDurationUnsupported
    if authoritativeElapsedSeconds grossBoundaries < Seconds.fromMinutes (fromIntegral automaticMealBreakThresholdMinutes)
        then Right grossBoundaries
        else
            let breakStart = Seconds.addTo (Seconds.fromMinutes (fromIntegral automaticMealBreakStartOffsetMinutes)) startsAt
                breakEnd = Seconds.addTo (Seconds.fromMinutes (fromIntegral automaticMealBreakMinutes)) breakStart
             in Bifunctor.first RosterSlotBoundariesInvalid $
                    authoritativeBoundariesFromInstants
                        slot.timezone
                        startsAt
                        endsAt
                        (Just breakStart)
                        (Just breakEnd)
