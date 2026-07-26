module Application.WageSourceFacts
    ( WageSourceFacts (..)
    , loadWageSourceFactsFor
    , sourceDiagnosticsForFacts
    ) where

import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.WageSourcePolicy
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Calendar (Day, DayOfWeek (..), toGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, unpackId)
import IHP.Prelude

data WageSourceFacts = WageSourceFacts
    { factFwcSnapshots                   :: ![FwcSnapshot]
    , factDataVicSnapshots               :: ![DataVicSnapshot]
    , factVenueConfigs                   :: !(Map.Map UUID VenueConfig)
    , factValidImportedPayItemIdsByVenue :: !(Map.Map UUID (Set.Set UUID))
    }

loadWageSourceFactsFor :: (?modelContext :: ModelContext) => [UUID] -> Set.Set Integer -> IO WageSourceFacts
loadWageSourceFactsFor venueIds targetYears = do
    syncRuns <- query @FwcMapdSyncRun |> orderByAsc #startedAt |> fetch
    venueConfigs <- if null venueIds
        then pure []
        else query @VenueConfig |> filterWhereIn (#venueId, List.nub venueIds) |> fetch
    validImportedPayItems <- if null venueIds
        then pure []
        else query @XeroImportedPayItem
            |> filterWhereIn (#venueId, List.nub venueIds)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
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
        , factValidImportedPayItemIdsByVenue = Map.fromListWith Set.union
            [ (item.venueId, Set.singleton (unpackId item.id))
            | item <- validImportedPayItems
            ]
        }

sourceDiagnosticsForFacts :: PolicyClock -> WageSourceFacts -> UUID -> Day -> Set.Set Integer -> SourceRequirement -> [SourceDiagnostic]
sourceDiagnosticsForFacts clock facts venueId workedOn targetYears requirement =
    case decision.finalDecision of
        FinalSourcesReady               -> []
        FinalSourceBlock allDiagnostics -> allDiagnostics
  where
    weekStartsOnIndex = maybe 1 (.rosterWeekStartsOn) (Map.lookup venueId facts.factVenueConfigs)
    decision = evaluateWageSourcePolicy clock WageSourcePolicyInput
        { sourceRequirement = requirement
        , payWeekStart = startOfWeekFor weekStartsOnIndex workedOn
        , venueWeekStartsOn = weekdayIndexToDayOfWeek weekStartsOnIndex
        , applicableDataVicTargetYears = targetYears
        , fwcSnapshots = facts.factFwcSnapshots
        , dataVicSnapshots = facts.factDataVicSnapshots
        }

fwcSnapshotFromRun :: FwcMapdSyncRun -> FwcSnapshot
fwcSnapshotFromRun run = FwcSnapshot
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
    successfulImports = Set.fromList
        [ (year, importedAt)
        | holiday <- holidays
        , let year = let (value, _, _) = toGregorian holiday.holidayDate in value
        , Set.member year targetYears
        , importedAt <- maybeToList holiday.importedAt
        ]

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
