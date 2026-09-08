module Application.Helper.RosterTimesheetBoundaries
    ( RosterSlotBoundaryError (..)
    , projectRosterSlotTimesheetBoundaries
    ) where

import Application.Helper.TimeRules (authoritativeRosterIntervalIsOperationallyValid,
                                     automaticMealBreakMinutes,
                                     automaticMealBreakStartOffsetMinutes,
                                     automaticMealBreakThresholdMinutes)
import Application.VenueTime.Model
import qualified Data.Bifunctor as Bifunctor
import Generated.Types
import IHP.Prelude

data RosterSlotBoundaryError
    = RosterSlotBoundariesIncomplete
    | RosterSlotBoundariesInvalid !BoundaryModelError
    | RosterSlotDurationUnsupported
    deriving (Eq, Show)

-- | Project the exact authoritative boundary snapshot materialized by a
-- Timesheet suggestion, including its automatic unpaid meal break.
projectRosterSlotTimesheetBoundaries :: RosterSlot -> Either RosterSlotBoundaryError AuthoritativeBoundaries
projectRosterSlotTimesheetBoundaries slot = do
    startsAt <- maybe (Left RosterSlotBoundariesIncomplete) Right slot.startsAt
    endsAt <- maybe (Left RosterSlotBoundariesIncomplete) Right slot.endsAt
    grossBoundaries <- Bifunctor.first RosterSlotBoundariesInvalid $
        authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing
    unless (authoritativeRosterIntervalIsOperationallyValid grossBoundaries) $
        Left RosterSlotDurationUnsupported
    if authoritativeElapsedSeconds grossBoundaries < fromIntegral (automaticMealBreakThresholdMinutes * 60)
        then Right grossBoundaries
        else
            let breakStart = addUTCTime (fromIntegral (automaticMealBreakStartOffsetMinutes * 60)) startsAt
                breakEnd = addUTCTime (fromIntegral (automaticMealBreakMinutes * 60)) breakStart
             in Bifunctor.first RosterSlotBoundariesInvalid $
                    authoritativeBoundariesFromInstants
                        slot.timezone
                        startsAt
                        endsAt
                        (Just breakStart)
                        (Just breakEnd)
