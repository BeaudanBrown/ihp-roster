{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.WageSourceEnforcement
    ( WageEntryFailure (..)
    , WageEntryOutcome (..)
    , enforceFinalWageEntries
    , enforceFinalWageEntriesAt
    , evaluateDraftWageEntries
    , evaluateDraftWageEntriesAt
    , renderWageEntryFailure
    , renderWageEntryFailures
    ) where

import Application.Helper.Controller.Input (parseUUIDText)
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculation)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.VenueTime.Model
import Application.WageEngine
import Application.WageEngine.Adapter
import Application.WageSourcePolicy
import qualified Data.Bifunctor as Bifunctor
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, DayOfWeek (..), addDays, toGregorian)
import Data.Traversable (traverse)
import Data.Time.Clock (getCurrentTime)
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

data WageSourceFacts = WageSourceFacts
    { factFwcSnapshots     :: ![FwcSnapshot]
    , factDataVicSnapshots :: ![DataVicSnapshot]
    , factVenueConfigs     :: !(Map.Map UUID VenueConfig)
    }

evaluateDraftWageEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO [WageEntryOutcome]
evaluateDraftWageEntries entries = do
    now <- getCurrentTime
    evaluateDraftWageEntriesAt (PolicyClock now) entries

evaluateDraftWageEntriesAt :: (?modelContext :: ModelContext) => PolicyClock -> [TimesheetEntry] -> IO [WageEntryOutcome]
evaluateDraftWageEntriesAt clock entries = do
    facts <- loadWageSourceFacts entries
    mapM (evaluateEntry clock facts) entries

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

evaluateEntry :: (?modelContext :: ModelContext) => PolicyClock -> WageSourceFacts -> TimesheetEntry -> IO WageEntryOutcome
evaluateEntry clock facts entry = do
    calculation <- calculateEntryForWorkflow entry
    requirement <- case calculation of
        Left _ -> pure (Right HospitalityAwardSources)
        Right wageCalculation -> sourceRequirementForEntry entry wageCalculation
    let effectiveCalculation = case requirement of
            Left message -> Left message
            Right _      -> calculation
        diagnostics = case (effectiveCalculation, requirement) of
            (Right _, Right sourceRequirement) -> sourceDiagnostics clock facts entry sourceRequirement
            _                                  -> []
    pure WageEntryOutcome
        { outcomeEntryId = unpackId entry.id
        , outcomeCalculation = effectiveCalculation
        , outcomeSourceDiagnostics = diagnostics
        }

calculateEntryForWorkflow :: (?modelContext :: ModelContext) => TimesheetEntry -> IO (Either Text WageCalculation)
calculateEntryForWorkflow entry
    | entry.isApproved =
        loadApprovedTimesheetPayCalculation entry >>= \case
            Left message        -> pure (Left message)
            Right Nothing       -> pure (Left "Approved timesheet entry has no sealed pay calculation.")
            Right (Just result) -> pure (Right result)
    | otherwise = do
        contexts <- loadWageEngineContextsForEntries [entry]
        pure do
            contextMap <- Bifunctor.first (\errors -> "Cannot calculate timesheet pay: " <> tshow errors) contexts
            context <- maybe (Left "Timesheet calculation context was not loaded.") Right (Map.lookup (unpackId entry.id) contextMap)
            boundaries <- Bifunctor.first (\err -> "Invalid timesheet boundaries: " <> tshow err) (timesheetEntryBoundaries entry)
            segments <- Bifunctor.first (\err -> "Cannot segment timesheet: " <> tshow err) (authoritativeAwardSegments boundaries)
            Bifunctor.first
                (\err -> "Cannot calculate timesheet pay: " <> tshow err)
                (calculateTimesheetPay (calculationInputFromLoadedContext context segments (authoritativeUnpaidMealBreak boundaries)))

sourceRequirementForEntry :: (?modelContext :: ModelContext) => TimesheetEntry -> WageCalculation -> IO (Either Text SourceRequirement)
sourceRequirementForEntry entry calculation =
    case calculationSourceRequirement calculation of
        HospitalityAwardSources -> pure (Right HospitalityAwardSources)
        ImportedXeroOverride -> do
            let importedIds =
                    [ itemId
                    | component <- calculation.earningsComponents
                    , ImportedFlatRateCondition rawItemId <- [component.sourceCondition]
                    , itemId <- maybeToList (Id <$> parseUUIDText rawItemId :: Maybe (Id XeroImportedPayItem))
                    ]
            validItems <- query @XeroImportedPayItem
                |> filterWhereIn (#id, importedIds)
                |> filterWhere (#venueId, entry.venueId)
                |> filterWhere (#archivedAt, Nothing)
                |> fetch
            pure $
                if not (null importedIds) && length validItems == length (List.nub importedIds)
                    then Right ImportedXeroOverride
                    else Left "Imported Xero override pay item is missing, archived, or belongs to another venue."

calculationSourceRequirement :: WageCalculation -> SourceRequirement
calculationSourceRequirement calculation
    | all ((== ExternalImportedPayItem) . (.calculationSource)) calculation.earningsComponents
        && not (null calculation.earningsComponents) = ImportedXeroOverride
    | otherwise = HospitalityAwardSources

sourceDiagnostics :: PolicyClock -> WageSourceFacts -> TimesheetEntry -> SourceRequirement -> [SourceDiagnostic]
sourceDiagnostics clock facts entry requirement =
    case decision.finalDecision of
        FinalSourcesReady    -> []
        FinalSourceBlock allDiagnostics -> allDiagnostics
  where
    venueConfig = Map.lookup (entry.venueId) facts.factVenueConfigs
    weekStartsOnIndex = maybe 1 (.rosterWeekStartsOn) venueConfig
    workedOn = timesheetEntryWorkedOn entry
    policyInput = WageSourcePolicyInput
        { sourceRequirement = requirement
        , payWeekStart = startOfWeekFor weekStartsOnIndex workedOn
        , venueWeekStartsOn = weekdayIndexToDayOfWeek weekStartsOnIndex
        , applicableDataVicTargetYears = entryTargetYears entry
        , fwcSnapshots = facts.factFwcSnapshots
        , dataVicSnapshots = facts.factDataVicSnapshots
        }
    decision = evaluateWageSourcePolicy clock policyInput

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
loadWageSourceFacts entries = do
    syncRuns <- query @FwcMapdSyncRun |> orderByAsc #startedAt |> fetch
    let venueIds = List.nub (map (.venueId) entries)
    venueConfigs <- if null venueIds
        then pure []
        else query @VenueConfig |> filterWhereIn (#venueId, venueIds) |> fetch
    let targetYears = Set.unions (map entryTargetYears entries)
    holidays <- if Set.null targetYears
        then pure []
        else query @PublicHoliday
            |> filterWhere (#jurisdiction, "VIC" :: Text)
            |> filterWhere (#isRegional, False)
            |> fetch
    pure WageSourceFacts
        { factFwcSnapshots = map fwcSnapshotFromRun syncRuns
        , factDataVicSnapshots = dataVicSnapshotsFromHolidays targetYears holidays
        , factVenueConfigs = Map.fromList [(config.venueId, config) | config <- venueConfigs]
        }

fwcSnapshotFromRun :: FwcMapdSyncRun -> FwcSnapshot
fwcSnapshotFromRun run =
    FwcSnapshot
        { fwcSnapshotMetadata = SourceSnapshot
            { completedAt = fromMaybe run.startedAt run.finishedAt
            , status = if completeHospitalitySuccess then CompleteSuccess else statusFromRun run.status
            }
        , provenance = if completeHospitalitySuccess then ValidatedMapdSnapshot else UnvalidatedFwcCandidate
        }
  where
    completeHospitalitySuccess = run.status == "succeeded" && 9 `elem` run.syncedAwardFixedIds

statusFromRun :: Text -> SnapshotStatus
statusFromRun "failed"    = FailedCandidate
statusFromRun "succeeded" = IncompleteCandidate
statusFromRun _           = IncompleteCandidate

dataVicSnapshotsFromHolidays :: Set.Set Integer -> [PublicHoliday] -> [DataVicSnapshot]
dataVicSnapshotsFromHolidays targetYears holidays =
    [ DataVicSnapshot
        { targetYear = year
        , snapshot = SourceSnapshot importedAt CompleteSuccess
        , coverage = StatewideVictoria
        }
    | (year, importedAt) <- Set.toAscList successfulImports
    ]
  where
    successfulImports =
        Set.fromList
            [ (year, importedAt)
            | holiday <- holidays
            , let year = dayYear holiday.holidayDate
            , Set.member year targetYears
            , importedAt <- maybeToList holiday.importedAt
            ]

dayYear :: Day -> Integer
dayYear day = let (year, _, _) = toGregorian day in year

weekdayIndexToDayOfWeek :: Int -> DayOfWeek
weekdayIndexToDayOfWeek = \case
    0 -> Sunday
    1 -> Monday
    2 -> Tuesday
    3 -> Wednesday
    4 -> Thursday
    5 -> Friday
    6 -> Saturday
    _ -> Monday

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
