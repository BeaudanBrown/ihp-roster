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
import Generated.Types (StaffEmploymentBasisEnum (Casual, Permanent))
import IHP.Prelude

data RosterAwardDurationViolation
    = PartTimeRosterShiftBelowMinimum
    | PartTimeRosterShiftAboveMaximum
    | CasualRosterShiftAboveMaximum
    deriving (Eq, Show)

projectedRosterWorkingSeconds :: AuthoritativeBoundaries -> NominalDiffTime
projectedRosterWorkingSeconds boundaries =
    max 0 (authoritativeElapsedSeconds boundaries - projectedAutomaticMealBreakSeconds)
  where
    projectedAutomaticMealBreakSeconds
        | authoritativeElapsedSeconds boundaries >= automaticMealBreakThresholdSeconds = automaticMealBreakDurationSeconds
        | otherwise = 0

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

partTimeMinimumWorkingSeconds :: NominalDiffTime
partTimeMinimumWorkingSeconds = 3 * 60 * 60

partTimeMaximumWorkingSeconds :: NominalDiffTime
partTimeMaximumWorkingSeconds = 11 * 60 * 60 + 30 * 60

casualMaximumWorkingSeconds :: NominalDiffTime
casualMaximumWorkingSeconds = 12 * 60 * 60

automaticMealBreakThresholdSeconds :: NominalDiffTime
automaticMealBreakThresholdSeconds = fromIntegral (automaticMealBreakThresholdMinutes * 60)

automaticMealBreakDurationSeconds :: NominalDiffTime
automaticMealBreakDurationSeconds = fromIntegral (automaticMealBreakMinutes * 60)
