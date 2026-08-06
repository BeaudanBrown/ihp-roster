{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.WageSourceEnforcement
    ( WageEntryFailure (..)
    , WageEntryOutcome (..)
    , enforceFinalWageEntries
    , enforceFinalWageEntriesAt
    , evaluateDraftWageEntriesAt
    , renderWageEntryFailure
    , renderWageEntryFailures
    ) where

import Application.Helper.Controller.Input (parseUUIDText)
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculations)
import Application.VenueTime.Model
import Application.WageEngine
import Application.WageEvaluation
import Application.WageSourceFacts
import Application.WageSourcePolicy
import qualified Data.Bifunctor as Bifunctor
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, toGregorian)
import Data.Time.Clock (getCurrentTime)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, unpackId)
import IHP.Prelude

data WageEntryFailure
    = WageCalculationFailed !UUID !Text
    | WageSourcesBlocked !UUID ![SourceDiagnostic]
    deriving (Eq, Show)

data WageEntryOutcome = WageEntryOutcome
    { outcomeEntryId           :: !UUID
    , outcomeCalculation       :: !(Either Text WageCalculation)
    , outcomeSourceDiagnostics :: ![SourceDiagnostic]
    }
    deriving (Eq, Show)


evaluateDraftWageEntriesAt :: (?modelContext :: ModelContext) => PolicyClock -> [TimesheetEntry] -> IO [WageEntryOutcome]
evaluateDraftWageEntriesAt clock entries = do
    facts <- loadWageSourceFacts entries
    let (approvedEntries, draftEntries) = List.partition (.isApproved) entries
    approvedCalculations <- loadApprovedTimesheetPayCalculations approvedEntries
    let draftSubjects = map (\entry -> (unpackId entry.id, timesheetWageSubject entry)) draftEntries
        validDraftSubjects = [subject | (_, Right subject) <- draftSubjects]
        draftSubjectErrors = Map.fromList
            [ (entryId, Left (renderWageEvaluationError err))
            | (entryId, Left err) <- draftSubjects
            ]
    evaluatedDrafts <- if null validDraftSubjects
        then pure Map.empty
        else evaluateUnsealedWages DraftWageEvaluation validDraftSubjects
    let draftCalculations = draftSubjectErrors <> Map.fromList
            [ (entryId, Bifunctor.first renderWageEvaluationError result)
            | (TimesheetSubject entryId, result) <- Map.toList evaluatedDrafts
            ]
    pure (map (evaluateEntry clock facts approvedCalculations draftCalculations) entries)

enforceFinalWageEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either [WageEntryFailure] [WageCalculation])
enforceFinalWageEntries entries = do
    now <- getCurrentTime
    enforceFinalWageEntriesAt (PolicyClock now) entries

enforceFinalWageEntriesAt :: (?modelContext :: ModelContext) => PolicyClock -> [TimesheetEntry] -> IO (Either [WageEntryFailure] [WageCalculation])
enforceFinalWageEntriesAt clock entries = do
    outcomes <- evaluateDraftWageEntriesAt clock entries
    let failures = concatMap finalFailures outcomes
    pure $ if null failures
        then traverse (Bifunctor.first (: []) . outcomeCalculationAsFailure) outcomes
        else Left failures
  where
    outcomeCalculationAsFailure outcome =
        Bifunctor.first (WageCalculationFailed outcome.outcomeEntryId) outcome.outcomeCalculation

finalFailures :: WageEntryOutcome -> [WageEntryFailure]
finalFailures outcome =
    calculationFailures <> sourceFailures
  where
    calculationFailures = case outcome.outcomeCalculation of
        Left message -> [WageCalculationFailed outcome.outcomeEntryId message]
        Right _      -> []
    sourceFailures =
        [ WageSourcesBlocked outcome.outcomeEntryId outcome.outcomeSourceDiagnostics
        | not (null outcome.outcomeSourceDiagnostics)
        ]

evaluateEntry ::
    PolicyClock ->
    WageSourceFacts ->
    Map.Map UUID (Either Text (Maybe WageCalculation)) ->
    Map.Map UUID (Either Text WageCalculation) ->
    TimesheetEntry ->
    WageEntryOutcome
evaluateEntry clock facts approvedCalculations draftContexts entry =
    WageEntryOutcome
        { outcomeEntryId = unpackId entry.id
        , outcomeCalculation = effectiveCalculation
        , outcomeSourceDiagnostics = diagnostics
        }
  where
    calculation = calculateEntryForWorkflow approvedCalculations draftContexts entry
    requirement = case calculation of
        Left _                -> Right HospitalityAwardSources
        Right wageCalculation -> sourceRequirementForEntry facts entry wageCalculation
    effectiveCalculation = case requirement of
            Left message -> Left message
            Right _      -> calculation
    diagnostics = case (effectiveCalculation, requirement) of
        (Right _, Right sourceRequirement) -> sourceDiagnostics clock facts entry sourceRequirement
        _                                  -> []

calculateEntryForWorkflow ::
    Map.Map UUID (Either Text (Maybe WageCalculation)) ->
    Map.Map UUID (Either Text WageCalculation) ->
    TimesheetEntry ->
    Either Text WageCalculation
calculateEntryForWorkflow approvedCalculations draftContexts entry
    | entry.isApproved =
        case Map.lookup entryId approvedCalculations of
            Nothing -> Left "Approved timesheet pay calculation was not loaded."
            Just (Left message) -> Left message
            Just (Right Nothing) -> Left "Approved timesheet entry has no sealed pay calculation."
            Just (Right (Just result)) -> Right result
    | otherwise =
        case Map.lookup entryId draftContexts of
            Nothing     -> Left "Timesheet calculation was not loaded."
            Just result -> result
  where
    entryId = unpackId entry.id

sourceRequirementForEntry :: WageSourceFacts -> TimesheetEntry -> WageCalculation -> Either Text SourceRequirement
sourceRequirementForEntry facts entry calculation =
    sourceRequirementForVenue facts entry.venueId calculation

sourceRequirementForVenue :: WageSourceFacts -> UUID -> WageCalculation -> Either Text SourceRequirement
sourceRequirementForVenue facts venueId calculation =
    case calculationSourceRequirement calculation of
        HospitalityAwardSources -> Right HospitalityAwardSources
        ImportedXeroOverride ->
            let importedIds =
                    [ itemId
                    | component <- calculation.earningsComponents
                    , ImportedFlatRateCondition rawItemId <- [component.sourceCondition]
                    , itemId <- maybeToList (parseUUIDText rawItemId)
                    ]
                uniqueImportedIds = List.nub importedIds
                validImportedIds = Map.findWithDefault Set.empty venueId facts.factValidImportedPayItemIdsByVenue
                unavailableImportedIds = Map.findWithDefault Set.empty venueId facts.factUnavailableImportedPayItemIdsByVenue
             in if not (null uniqueImportedIds) && all (`Set.member` validImportedIds) uniqueImportedIds
                    then Right ImportedXeroOverride
                    else if any (`Set.member` unavailableImportedIds) uniqueImportedIds
                        then Left "Approved entry is pinned to a Xero earnings rate that is no longer available. Choose a current pay assignment, then correct and reapprove the entry before Xero payroll preparation."
                        else Left "Imported Xero override pay item is missing, owner-archived, or belongs to another venue."

calculationSourceRequirement :: WageCalculation -> SourceRequirement
calculationSourceRequirement calculation
    | all ((== ExternalImportedPayItem) . (.calculationSource)) calculation.earningsComponents
        && not (null calculation.earningsComponents) = ImportedXeroOverride
    | otherwise = HospitalityAwardSources

sourceDiagnostics :: PolicyClock -> WageSourceFacts -> TimesheetEntry -> SourceRequirement -> [SourceDiagnostic]
sourceDiagnostics clock facts entry requirement =
    sourceDiagnosticsFor clock facts entry.venueId (timesheetEntryWorkedOn entry) (entryTargetYears entry) requirement

sourceDiagnosticsFor :: PolicyClock -> WageSourceFacts -> UUID -> Day -> Set.Set Integer -> SourceRequirement -> [SourceDiagnostic]
sourceDiagnosticsFor = sourceDiagnosticsForFacts

entryTargetYears :: TimesheetEntry -> Set.Set Integer
entryTargetYears entry =
    Set.fromList (map dayYear [timesheetEntryWorkedOn entry, timesheetEntryWorkedOnAtEnd entry])
  where
    timesheetEntryWorkedOnAtEnd candidate =
        let startDay = timesheetEntryWorkedOn candidate
            endDay = case timesheetEntryBoundaries candidate of
                Left _             -> startDay
                Right boundaries   -> (authoritativeEndLocalTime boundaries).localDay
         in if endDay < startDay then addDays 1 startDay else endDay

loadWageSourceFacts :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO WageSourceFacts
loadWageSourceFacts entries =
    loadWageSourceFactsFor
        (List.nub (map (.venueId) entries))
        (Set.unions (map entryTargetYears entries))

dayYear :: Day -> Integer
dayYear day = let (year, _, _) = toGregorian day in year

renderWageEntryFailures :: Text -> [WageEntryFailure] -> Text
renderWageEntryFailures prefix failures =
    prefix <> Text.intercalate "; " (map renderWageEntryFailure failures)

renderWageEntryFailure :: WageEntryFailure -> Text
renderWageEntryFailure = \case
    WageCalculationFailed entryId message -> "Entry " <> tshow entryId <> ": " <> message
    WageSourcesBlocked entryId diagnostics ->
        "Entry " <> tshow entryId <> ": wage sources are not ready (" <> Text.intercalate ", " (map renderDiagnostic diagnostics) <> ")."
  where
    renderDiagnostic = \case
        FwcSnapshotMissing -> "FWC snapshot missing"
        FwcSnapshotStale {} -> "FWC snapshot stale"
        FwcAnnualRefreshMissing {} -> "FWC annual refresh missing"
        DataVicSnapshotMissing year -> "DataVic " <> tshow year <> " missing"
        DataVicSnapshotStale year _ _ -> "DataVic " <> tshow year <> " stale"
