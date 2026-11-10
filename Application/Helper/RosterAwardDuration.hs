module Application.Helper.RosterAwardDuration
    ( RosterAwardDurationViolation (..)
    , projectedRosterWorkingSeconds
    , rosterAwardDurationViolation
    , rosterAwardDurationViolationMessage
    ) where

import Application.Helper.TimeRules (automaticMealBreakMinutes,
                                     automaticMealBreakThresholdMinutes)
import Application.VenueTime.Model (AuthoritativeBoundaries,
                                    authoritativeElapsedSeconds)
import qualified Application.VenueTime.Seconds as Seconds
import Generated.Types (StaffEmploymentBasisEnum (Casual, Permanent))
import IHP.Prelude

data RosterAwardDurationViolation
    = PartTimeRosterShiftBelowMinimum
    | PartTimeRosterShiftAboveMaximum
    | CasualRosterShiftAboveMaximum
    deriving (Eq, Show)

projectedRosterWorkingSeconds :: AuthoritativeBoundaries -> Seconds.Seconds
projectedRosterWorkingSeconds boundaries =
    max (Seconds.fromSeconds 0) (Seconds.subtract (authoritativeElapsedSeconds boundaries) projectedAutomaticMealBreakSeconds)
  where
    projectedAutomaticMealBreakSeconds
        | authoritativeElapsedSeconds boundaries >= automaticMealBreakThresholdSeconds = automaticMealBreakDurationSeconds
        | otherwise = Seconds.fromSeconds 0

rosterAwardDurationViolation :: StaffEmploymentBasisEnum -> AuthoritativeBoundaries -> Maybe RosterAwardDurationViolation
rosterAwardDurationViolation employmentBasis boundaries =
    case employmentBasis of
        Permanent
            | projectedWorkingSeconds < partTimeMinimumWorkingSeconds -> Just PartTimeRosterShiftBelowMinimum
            | projectedWorkingSeconds > partTimeMaximumWorkingSeconds -> Just PartTimeRosterShiftAboveMaximum
            | otherwise -> Nothing
        Casual
            | projectedWorkingSeconds > casualMaximumWorkingSeconds -> Just CasualRosterShiftAboveMaximum
            | otherwise -> Nothing
  where
    projectedWorkingSeconds = projectedRosterWorkingSeconds boundaries

rosterAwardDurationViolationMessage :: RosterAwardDurationViolation -> Text
rosterAwardDurationViolationMessage = \case
    PartTimeRosterShiftBelowMinimum -> partTimeDurationMessage
    PartTimeRosterShiftAboveMaximum -> partTimeDurationMessage
    CasualRosterShiftAboveMaximum -> "Casual roster shifts must project no more than 12 working hours after the automatic unpaid meal break."

partTimeDurationMessage :: Text
partTimeDurationMessage =
    "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."

partTimeMinimumWorkingSeconds :: Seconds.Seconds
partTimeMinimumWorkingSeconds = Seconds.fromMinutes 180

partTimeMaximumWorkingSeconds :: Seconds.Seconds
partTimeMaximumWorkingSeconds = Seconds.fromMinutes 690

casualMaximumWorkingSeconds :: Seconds.Seconds
casualMaximumWorkingSeconds = Seconds.fromMinutes 720

automaticMealBreakThresholdSeconds :: Seconds.Seconds
automaticMealBreakThresholdSeconds = Seconds.fromMinutes (fromIntegral automaticMealBreakThresholdMinutes)

automaticMealBreakDurationSeconds :: Seconds.Seconds
automaticMealBreakDurationSeconds = Seconds.fromMinutes (fromIntegral automaticMealBreakMinutes)
