{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.RosterWagePrediction
    ( RosterWagePrediction (..)
    , RosterWagePredictionDay (..)
    , fetchRosterWagePredictionForWindow
    , lookupRosterWagePredictionDayByDate
    , formatMoneyAmount
    ) where

import Application.Helper.TimeRules (automaticMealBreakMinutes)
import Application.PayAssignment (EffectivePayAssignment (..),
                                  ShiftPayAssignment (..),
                                  StaffPayAssignment (..), resolvePayAssignment,
                                  staffAssignmentSuppressesTimesheets)
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Application.WageEngine (FinalEarningsSummary (..))
import Application.WageEvaluation
import Application.WageSourcePolicy (SourceDiagnostic)
import Data.Either (isLeft)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import Generated.Types
import IHP.ControllerPrelude

data RosterWagePrediction = RosterWagePrediction
    { predictionDays                 :: ![RosterWagePredictionDay]
    , predictionWeekTotal            :: !Scientific
    , predictionCompleteShiftCount   :: !Int
    , predictionIncompleteShiftCount :: !Int
    , predictionBreakMinutes         :: !Int
    , predictionCalculationFailures  :: ![(UUID, Text)]
    , predictionSourceWarnings       :: ![(UUID, [SourceDiagnostic])]
    }
    deriving (Eq, Show)

data RosterWagePredictionDay = RosterWagePredictionDay
    { predictionDayDate         :: !Day
    , predictionDayTotal        :: !Scientific
    , predictionDayShiftCount   :: !Int
    , predictionDayFailureCount :: !Int
    }
    deriving (Eq, Show)

data PredictedShift = PredictedShift
    { predictedShiftDate   :: !Day
    , predictedShiftAmount :: !Scientific
    }
    deriving (Eq, Show)

fetchRosterWagePredictionForWindow ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    [RosterDay] ->
    [RosterSlot] ->
    IO RosterWagePrediction
fetchRosterWagePredictionForWindow venueConfig rosterDays rosterSlots = do
    let staffAssignedSlots = filter rosterShiftIsStaffAssigned rosterSlots
        referencedStaffIds = List.nub (mapMaybe (.staffId) staffAssignedSlots)
        referencedShiftTypeIds = List.nub (mapMaybe (.shiftTypeId) staffAssignedSlots)
    staffMembers <-
        if null referencedStaffIds
            then pure []
            else query @Staff |> filterWhere (#venueId, venueConfig.venueId) |> filterWhereIn (#id, map Id referencedStaffIds) |> fetch
    shiftTypes <-
        if null referencedShiftTypeIds
            then pure []
            else query @ShiftType |> filterWhere (#venueId, venueConfig.venueId) |> filterWhereIn (#id, map Id referencedShiftTypeIds) |> fetch
    let rosterDaysById = Map.fromList [(unpackId rosterDay.id, rosterDay) | rosterDay <- rosterDays]
        staffById = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
        shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
        wageSubjectFor slot =
            case Map.lookup slot.rosterDayId rosterDaysById of
                Nothing -> Left (WageSubjectBoundariesFailed (RosterSlotSubject (unpackId slot.id)) "Roster slot has no Operational day.")
                Just rosterDay -> rosterSlotWageSubject venueConfig.venueId rosterDay.operationalDate slot
        subjectCandidates =
            [ (slot, Map.lookup slot.rosterDayId rosterDaysById, wageSubjectFor slot)
            | slot <- staffAssignedSlots
            , not (rosterSlotIsRosterOnly staffById shiftTypeById slot)
            ]
        subjects = [subject | (_, Just _, Right subject) <- subjectCandidates]
        incompleteCount = length
            [ ()
            | (_, maybeDay, result) <- subjectCandidates
            , isNothing maybeDay || isLeft result
            ]
    evaluations <- evaluateUnsealedWagesWithPolicy DraftWageEvaluation subjects
    let predictedShifts =
            [ PredictedShift rosterDay.operationalDate (calculationAmount outcome)
            | (_, Just rosterDay, Right subject) <- subjectCandidates
            , Just (Right outcome) <- [Map.lookup subject.wageSubjectKey evaluations]
            ]
        failures =
            [ (unpackId slot.id, failureMessage result)
            | (slot, Just _, Right subject) <- subjectCandidates
            , let result = Map.lookup subject.wageSubjectKey evaluations
            , isNothing result || maybe False isLeft result
            ]
        sourceWarnings =
            [ (unpackId slot.id, outcome.evaluatedSourceDiagnostics)
            | (slot, Just _, Right subject) <- subjectCandidates
            , Just (Right outcome) <- [Map.lookup subject.wageSubjectKey evaluations]
            , not (null outcome.evaluatedSourceDiagnostics)
            ]
        predictionDays =
            [ predictionDay rosterDay predictedShifts failures rosterSlots
            | rosterDay <- rosterDays
            ]
    pure RosterWagePrediction
        { predictionDays
        , predictionWeekTotal = sum (map (.predictionDayTotal) predictionDays)
        , predictionCompleteShiftCount = length subjects
        , predictionIncompleteShiftCount = incompleteCount
        , predictionBreakMinutes = automaticMealBreakMinutes
        , predictionCalculationFailures = failures
        , predictionSourceWarnings = sourceWarnings
        }
  where
    failureMessage maybeResult =
        case maybeResult of
            Nothing         -> "Wage calculation result was not loaded."
            Just (Left err) -> renderWageEvaluationError err
            Just (Right _)  -> ""

rosterSlotIsRosterOnly :: Map.Map UUID Staff -> Map.Map UUID ShiftType -> RosterSlot -> Bool
rosterSlotIsRosterOnly staffById shiftTypeById slot =
    case slot.staffId >>= (`Map.lookup` staffById) of
        Just staff
            | staffAssignmentSuppressesTimesheets (staffAssignment staff) -> True
        Just staff ->
            case slot.shiftTypeId >>= (`Map.lookup` shiftTypeById) of
                Just shiftType -> resolvePayAssignment (staffAssignment staff) (shiftAssignment shiftType) == EffectiveRosterOnly
                Nothing -> False
        Nothing -> False
  where
    staffAssignment staff = StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId
    shiftAssignment shiftType = ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId


lookupRosterWagePredictionDayByDate :: RosterWagePrediction -> Day -> Maybe RosterWagePredictionDay
lookupRosterWagePredictionDayByDate prediction date =
    List.find (\day -> day.predictionDayDate == date) prediction.predictionDays

predictionDay :: RosterDay -> [PredictedShift] -> [(UUID, Text)] -> [RosterSlot] -> RosterWagePredictionDay
predictionDay rosterDay predictedShifts failures rosterSlots =
    let dayShifts = filter (\shift -> shift.predictedShiftDate == rosterDay.operationalDate) predictedShifts
        daySlotIds = [unpackId slot.id | slot <- rosterSlots, slot.rosterDayId == unpackId rosterDay.id]
     in RosterWagePredictionDay
            { predictionDayDate = rosterDay.operationalDate
            , predictionDayTotal = sum (map (.predictedShiftAmount) dayShifts)
            , predictionDayShiftCount = length dayShifts
            , predictionDayFailureCount = length [() | (slotId, _) <- failures, slotId `elem` daySlotIds]
            }

calculationAmount :: WageEvaluationOutcome -> Scientific
calculationAmount outcome =
    fst (Scientific.fromRationalRepetendUnlimited outcome.evaluatedFinalEarnings.finalEarningsTotalAmount)

formatMoneyAmount :: Scientific -> Text
formatMoneyAmount value =
    "$" <> cs (Scientific.formatScientific Scientific.Fixed (Just 2) value)
