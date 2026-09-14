{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.WageEvaluation
    ( WageSubjectKey (..)
    , WageEvaluationMode (..)
    , UnsealedWageSubject (..)
    , WageEvaluationError (..)
    , WageEvaluationOutcome (..)
    , evaluateUnsealedWages
    , evaluateUnsealedWagesWithPolicy
    , timesheetWageSubject
    , rosterSlotWageSubject
    , renderWageEvaluationError
    ) where

import Application.Helper.RosterTimesheetBoundaries
import Application.VenueTime.Model
import Application.WageEngine
import Application.WageEngine.Adapter
import Application.WageSourceFacts
import Application.WageSourcePolicy
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

data WageSubjectKey
    = TimesheetSubject !UUID
    | RosterSlotSubject !UUID
    deriving (Eq, Ord, Show)

data WageEvaluationMode
    = DraftWageEvaluation
    | ApprovalWageEvaluation
    | HistoricalBackfillWageEvaluation
    deriving (Eq, Show)

data UnsealedWageSubject = UnsealedWageSubject
    { wageSubjectKey                   :: !WageSubjectKey
    , wageSubjectVenueId               :: !UUID
    , wageSubjectStaffId               :: !UUID
    , wageSubjectShiftTypeId           :: !UUID
    , wageSubjectOperationalDate       :: !Day
    , wageSubjectBoundaries            :: !AuthoritativeBoundaries
    , wageSubjectStaffPayVersionId     :: !(Maybe UUID)
    , wageSubjectShiftTypePayVersionId :: !(Maybe UUID)
    }
    deriving (Eq, Show)

data WageEvaluationError
    = WageSubjectRequiresImmutablePayVersions !WageSubjectKey
    | WageSubjectAdapterFailed !WageEngineAdapterError
    | WageSubjectSegmentationFailed !WageSubjectKey !BoundaryModelError
    | WageSubjectCalculationFailed !WageSubjectKey !WageCalculationError
    | WageSubjectBoundariesFailed !WageSubjectKey !Text
    | WageSubjectSourcesBlocked !WageSubjectKey ![SourceDiagnostic]
    deriving (Eq, Show)

data WageEvaluationOutcome = WageEvaluationOutcome
    { evaluatedCalculation       :: !WageCalculation
    , evaluatedFinalEarnings     :: !FinalEarningsSummary
    , evaluatedSourceDiagnostics :: ![SourceDiagnostic]
    }
    deriving (Eq, Show)

-- | Compatibility projection for callers that need only the canonical
-- calculation. Source policy is still evaluated by the deep seam.
evaluateUnsealedWages ::
    (?modelContext :: ModelContext) =>
    WageEvaluationMode ->
    [UnsealedWageSubject] ->
    IO (Map.Map WageSubjectKey (Either WageEvaluationError WageCalculation))
evaluateUnsealedWages mode subjects =
    fmap (fmap (fmap (.evaluatedCalculation))) (evaluateUnsealedWagesWithPolicy mode subjects)

-- | Sole production calculation authority for unsealed wage subjects. Context
-- is bulk-loaded independently of Timesheet persistence; each subject is
-- segmented, evaluated, finalized, and passed through the selected source mode.
evaluateUnsealedWagesWithPolicy ::
    (?modelContext :: ModelContext) =>
    WageEvaluationMode ->
    [UnsealedWageSubject] ->
    IO (Map.Map WageSubjectKey (Either WageEvaluationError WageEvaluationOutcome))
evaluateUnsealedWagesWithPolicy mode subjects = do
    contexts <- loadWageEngineContextResultsForSubjects (map subjectRequest validSubjects)
    sourceFacts <- loadWageSourceFactsFor
        (map (.wageSubjectVenueId) subjects)
        (Set.unions (map subjectTargetYears subjects))
    now <- getCurrentTime
    pure $ Map.fromList (map (evaluateOne (PolicyClock now) sourceFacts contexts) subjects)
  where
    validSubjects = filter (isNothing . immutableVersionError mode) subjects

    evaluateOne clock sourceFacts contexts subject =
        (subject.wageSubjectKey, do
            maybe (Right ()) Left (immutableVersionError mode subject)
            context <-
                Map.lookup (subjectIdentity subject.wageSubjectKey) contexts
                    |> maybe (Left (WageSubjectAdapterFailed (MissingCalculationContext (subjectIdentity subject.wageSubjectKey)))) (Bifunctor.first WageSubjectAdapterFailed)
            segments <- Bifunctor.first (WageSubjectSegmentationFailed subject.wageSubjectKey) (authoritativeAwardSegments subject.wageSubjectBoundaries)
            calculation <- Bifunctor.first (WageSubjectCalculationFailed subject.wageSubjectKey) $
                calculateTimesheetPay
                    (calculationInputFromLoadedContext context segments (authoritativeUnpaidMealBreak subject.wageSubjectBoundaries))
            let diagnostics = case mode of
                    HistoricalBackfillWageEvaluation -> []
                    _ -> subjectSourceDiagnostics clock sourceFacts subject calculation
            case mode of
                ApprovalWageEvaluation | not (null diagnostics) ->
                    Left (WageSubjectSourcesBlocked subject.wageSubjectKey diagnostics)
                _ -> Right WageEvaluationOutcome
                    { evaluatedCalculation = calculation
                    , evaluatedFinalEarnings = deriveFinalEarnings calculation.earningsComponents
                    , evaluatedSourceDiagnostics = diagnostics
                    }
        )

subjectSourceDiagnostics :: PolicyClock -> WageSourceFacts -> UnsealedWageSubject -> WageCalculation -> [SourceDiagnostic]
subjectSourceDiagnostics clock facts subject calculation =
    sourceDiagnosticsForFacts
        clock
        facts
        subject.wageSubjectVenueId
        subject.wageSubjectOperationalDate
        (subjectTargetYears subject)
        (if calculationUsesImportedOverride calculation then ImportedXeroOverride else HospitalityAwardSources)

calculationUsesImportedOverride :: WageCalculation -> Bool
calculationUsesImportedOverride calculation =
    not (null calculation.earningsComponents)
        && all ((== ExternalImportedPayItem) . (.calculationSource)) calculation.earningsComponents

subjectTargetYears :: UnsealedWageSubject -> Set.Set Integer
subjectTargetYears subject = Set.fromList
    [ dayYear (authoritativeStartLocalTime subject.wageSubjectBoundaries).localDay
    , dayYear (authoritativeEndLocalTime subject.wageSubjectBoundaries).localDay
    ]

dayYear :: Day -> Integer
dayYear day = let (year, _, _) = toGregorian day in year

immutableVersionError :: WageEvaluationMode -> UnsealedWageSubject -> Maybe WageEvaluationError
immutableVersionError DraftWageEvaluation _ = Nothing
immutableVersionError ApprovalWageEvaluation subject = requiredImmutableVersions subject
immutableVersionError HistoricalBackfillWageEvaluation subject = requiredImmutableVersions subject

requiredImmutableVersions :: UnsealedWageSubject -> Maybe WageEvaluationError
requiredImmutableVersions candidate
    | isJust candidate.wageSubjectStaffPayVersionId
        && isJust candidate.wageSubjectShiftTypePayVersionId = Nothing
    | otherwise = Just (WageSubjectRequiresImmutablePayVersions candidate.wageSubjectKey)

subjectRequest :: UnsealedWageSubject -> WageEngineSubjectRequest
subjectRequest subject = WageEngineSubjectRequest
    { subjectRequestId = subjectIdentity subject.wageSubjectKey
    , subjectRequestOperationalDate = subject.wageSubjectOperationalDate
    , subjectRequestComponentStartDate = (authoritativeStartLocalTime subject.wageSubjectBoundaries).localDay
    , subjectRequestComponentEndDate = (authoritativeEndLocalTime subject.wageSubjectBoundaries).localDay
    , subjectRequestVenueId = subject.wageSubjectVenueId
    , subjectRequestStaffId = subject.wageSubjectStaffId
    , subjectRequestShiftTypeId = subject.wageSubjectShiftTypeId
    , subjectRequestStaffPayVersionId = subject.wageSubjectStaffPayVersionId
    , subjectRequestShiftTypePayVersionId = subject.wageSubjectShiftTypePayVersionId
    }

subjectIdentity :: WageSubjectKey -> UUID
subjectIdentity (TimesheetSubject value)  = value
subjectIdentity (RosterSlotSubject value) = value

timesheetWageSubject :: TimesheetEntry -> Either WageEvaluationError UnsealedWageSubject
timesheetWageSubject entry = do
    let key = TimesheetSubject (unpackId entry.id)
    boundaries <- Bifunctor.first (const (WageSubjectBoundariesFailed key "Timesheet timing is invalid and must be repaired before payroll.")) (timesheetEntryBoundaries entry)
    pure UnsealedWageSubject
        { wageSubjectKey = key
        , wageSubjectVenueId = entry.venueId
        , wageSubjectStaffId = entry.staffId
        , wageSubjectShiftTypeId = entry.shiftTypeId
        , wageSubjectOperationalDate = entry.operationalDate
        , wageSubjectBoundaries = boundaries
        , wageSubjectStaffPayVersionId = entry.staffPayVersionId
        , wageSubjectShiftTypePayVersionId = entry.shiftTypePayVersionId
        }

rosterSlotWageSubject :: UUID -> Day -> RosterSlot -> Either WageEvaluationError UnsealedWageSubject
rosterSlotWageSubject venueId operationalDate slot = do
    let key = RosterSlotSubject (unpackId slot.id)
    staffId <- maybe (Left (WageSubjectBoundariesFailed key "Roster slot has no staff member.")) Right slot.staffId
    shiftTypeId <- maybe (Left (WageSubjectBoundariesFailed key "Roster slot has no shift type.")) Right slot.shiftTypeId
    boundaries <- Bifunctor.first (const (WageSubjectBoundariesFailed key "Roster shift timing is invalid and must be repaired before payroll.")) (projectRosterSlotTimesheetBoundaries slot)
    pure UnsealedWageSubject
        { wageSubjectKey = key
        , wageSubjectVenueId = venueId
        , wageSubjectStaffId = staffId
        , wageSubjectShiftTypeId = shiftTypeId
        , wageSubjectOperationalDate = operationalDate
        , wageSubjectBoundaries = boundaries
        , wageSubjectStaffPayVersionId = Nothing
        , wageSubjectShiftTypePayVersionId = Nothing
        }

renderWageEvaluationError :: WageEvaluationError -> Text
renderWageEvaluationError = \case
    WageSubjectRequiresImmutablePayVersions _ -> "Immutable staff and shift pay versions are required."
    WageSubjectAdapterFailed (InvalidPersistedTiming _) -> "Timesheet timing is invalid and must be repaired before payroll."
    WageSubjectAdapterFailed err -> "Cannot load wage context: " <> tshow err
    WageSubjectSegmentationFailed _ err -> "Cannot segment authoritative shift boundaries: " <> tshow err
    WageSubjectCalculationFailed _ (MissingValidatedRate key) ->
        "Cannot calculate pay because the validated wage rate is unavailable: " <> tshow key <> "."
    WageSubjectCalculationFailed _ err -> "Cannot calculate pay: " <> tshow err
    WageSubjectBoundariesFailed _ message -> message
    WageSubjectSourcesBlocked _ diagnostics -> "Wage sources are not ready: " <> tshow diagnostics
