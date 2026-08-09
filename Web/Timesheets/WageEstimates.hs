module Web.Timesheets.WageEstimates
    ( TimesheetWageEstimateSummary (..)
    , TimesheetWageEstimates (..)
    , canViewTimesheetWageEstimates
    , evaluateTimesheetWageEstimates
    , lookupTimesheetDayWageEstimate
    ) where

import Application.Helper.Controller (hasRole)
import Application.VenueTime.Model (timesheetEntryWorkedOn)
import Application.WageEngine (FinalEarningsSummary (..), WageCalculation (..),
                               deriveFinalEarnings)
import Application.WageEvaluation
import Application.WageSourceEnforcement (WageEntryOutcome (..),
                                          evaluateDraftWageEntriesAt)
import Application.WageSourcePolicy (PolicyClock (..))
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude
import Web.Timesheets.Suggestion

data TimesheetWageEstimateSummary = TimesheetWageEstimateSummary
    { wageEstimateAmount             :: !Scientific
    , wageEstimateUnavailableCount   :: !Int
    , wageEstimateSourceWarningCount :: !Int
    }
    deriving (Eq, Show)

data TimesheetWageEstimates = TimesheetWageEstimates
    { timesheetWeekWageEstimate :: !TimesheetWageEstimateSummary
    , timesheetDayWageEstimates :: !(Map.Map Day TimesheetWageEstimateSummary)
    }
    deriving (Eq, Show)

data WageEstimateItem = WageEstimateItem
    { wageEstimateItemDay           :: !Day
    , wageEstimateItemAmount        :: !(Maybe Scientific)
    , wageEstimateItemSourceWarning :: !Bool
    }

canViewTimesheetWageEstimates :: (?context :: ControllerContext) => Bool
canViewTimesheetWageEstimates =
    hasRole VenueAdmin || not (hasRole Manager)

-- Approved entries consume their sealed calculation. Unapproved entries and
-- transient roster suggestions use the canonical draft evaluation boundary.
evaluateTimesheetWageEstimates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
    [TimesheetSuggestion] ->
    IO TimesheetWageEstimates
evaluateTimesheetWageEstimates entries suggestions = do
    now <- getCurrentTime
    entryOutcomes <- evaluateDraftWageEntriesAt (PolicyClock now) entries
    suggestionOutcomes <- evaluateUnsealedWagesWithPolicy DraftWageEvaluation (map suggestionSubject suggestions)
    let entryItems = zipWith entryItem entries entryOutcomes
        suggestionItems = map (suggestionItem suggestionOutcomes) suggestions
        items = entryItems <> suggestionItems
    pure TimesheetWageEstimates
        { timesheetWeekWageEstimate = summarize items
        , timesheetDayWageEstimates = Map.map summarize (Map.fromListWith (<>) [(item.wageEstimateItemDay, [item]) | item <- items])
        }
  where
    entryItem entry outcome =
        WageEstimateItem
            { wageEstimateItemDay = timesheetEntryWorkedOn entry
            , wageEstimateItemAmount = calculationAmountFromCalculation <$> eitherToMaybe outcome.outcomeCalculation
            , wageEstimateItemSourceWarning = not entry.isApproved && not (null outcome.outcomeSourceDiagnostics)
            }

    suggestionItem outcomes suggestion =
        let result = Map.lookup (RosterSlotSubject (unpackId suggestion.suggestionRosterSlotId)) outcomes
         in WageEstimateItem
                { wageEstimateItemDay = timesheetSuggestionWorkedOn suggestion
                , wageEstimateItemAmount = calculationAmount <$> (result >>= eitherToMaybe)
                , wageEstimateItemSourceWarning = maybe False (either (const False) (not . null . (.evaluatedSourceDiagnostics))) result
                }

    eitherToMaybe = either (const Nothing) Just

suggestionSubject :: (?context :: ControllerContext) => TimesheetSuggestion -> UnsealedWageSubject
suggestionSubject suggestion =
    UnsealedWageSubject
        { wageSubjectKey = RosterSlotSubject (unpackId suggestion.suggestionRosterSlotId)
        , wageSubjectVenueId = unpackId currentVenueId
        , wageSubjectStaffId = suggestion.suggestionStaffId
        , wageSubjectShiftTypeId = suggestion.suggestionShiftTypeId
        , wageSubjectBoundaries = suggestion.suggestionBoundaries
        , wageSubjectStaffPayVersionId = Nothing
        , wageSubjectShiftTypePayVersionId = Nothing
        }

calculationAmount :: WageEvaluationOutcome -> Scientific
calculationAmount = scientificAmount . (.finalEarningsTotalAmount) . (.evaluatedFinalEarnings)

calculationAmountFromCalculation :: WageCalculation -> Scientific
calculationAmountFromCalculation = scientificAmount . (.finalEarningsTotalAmount) . deriveFinalEarnings . (.earningsComponents)

scientificAmount :: Rational -> Scientific
scientificAmount = fst . Scientific.fromRationalRepetendUnlimited

summarize :: [WageEstimateItem] -> TimesheetWageEstimateSummary
summarize items =
    TimesheetWageEstimateSummary
        { wageEstimateAmount = sum (mapMaybe (.wageEstimateItemAmount) items)
        , wageEstimateUnavailableCount = length (filter (isNothing . (.wageEstimateItemAmount)) items)
        , wageEstimateSourceWarningCount = length (filter (.wageEstimateItemSourceWarning) items)
        }

lookupTimesheetDayWageEstimate :: TimesheetWageEstimates -> Day -> TimesheetWageEstimateSummary
lookupTimesheetDayWageEstimate estimates day =
    Map.findWithDefault (summarize []) day estimates.timesheetDayWageEstimates
