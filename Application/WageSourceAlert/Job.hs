module Application.WageSourceAlert.Job
    ( enqueueWageSourceFreshnessCheck
    , handleWageSourceRefreshFailureAfterFinalAttempt
    , performWageSourceHealthCheckJob
    , performWageSourceHealthCheckJobAt
    , wageSourceHealthCheckJobKind
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayloadV1)
import Application.Async.Queue
import Application.EmailDelivery
import Application.Error.Parser (parserFailure)
import Application.PublicHolidays.Policy (targetPublicHolidayYears)
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Application.WageSourceAlert.Types
import Application.WageSourceFacts
import Application.WageSourcePolicy
import Control.Monad (void)
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (DayOfWeek (..), fromGregorian, toGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.ModelSupport (withTransaction)


wageSourceHealthCheckJobKind :: Text
wageSourceHealthCheckJobKind = "wage_source_health_check"

data HealthCheckPayload = HealthCheckPayload
    { payloadSource          :: !WageSourceKind
    , payloadTrigger         :: !RefreshTrigger
    , payloadSourceJobId     :: !UUID
    , payloadEnqueuedAt      :: !UTCTime
    , payloadAnchorSuccessAt :: !(Maybe UTCTime)
    }

instance Aeson.ToJSON HealthCheckPayload where
    toJSON payload =
        Aeson.object
            [ "source" Aeson..= wageSourceText payload.payloadSource
            , "trigger" Aeson..= refreshTriggerText payload.payloadTrigger
            , "sourceJobId" Aeson..= payload.payloadSourceJobId
            , "enqueuedAt" Aeson..= payload.payloadEnqueuedAt
            , "anchorSuccessAt" Aeson..= payload.payloadAnchorSuccessAt
            ]

instance Aeson.FromJSON HealthCheckPayload where
    parseJSON = Aeson.withObject "WageSourceHealthCheckPayload" \object -> do
        rawSource <- object Aeson..: "source"
        source <- maybe (parserFailure "Unknown wage source") pure (parseWageSourceKind rawSource)
        rawTrigger <- object Aeson..: "trigger"
        trigger <- maybe (parserFailure "Unknown wage-source health-check trigger") pure (parseRefreshTrigger rawTrigger)
        HealthCheckPayload
            <$> pure source
            <*> pure trigger
            <*> object Aeson..: "sourceJobId"
            <*> object Aeson..: "enqueuedAt"
            <*> object Aeson..:? "anchorSuccessAt"

data AlertCandidate = AlertCandidate
    { snapshot    :: !WageSourceAlertSnapshot
    , semanticKey :: !Text
    }

data AnnualEvaluation
    = AnnualNotDue
    | AnnualDeferredNoActiveVenue
    | AnnualEvaluated
    deriving (Eq, Show)

enqueueWageSourceFreshnessCheck ::
    (?modelContext :: ModelContext) =>
    WageSourceKind ->
    AppJob ->
    UTCTime ->
    IO AppJob
enqueueWageSourceFreshnessCheck source sourceJob completedAt =
    enqueueHealthCheckOnce
        HealthCheckPayload
            { payloadSource = source
            , payloadTrigger = ScheduledFreshnessCheck
            , payloadSourceJobId = unpackId sourceJob.id
            , payloadEnqueuedAt = completedAt
            , payloadAnchorSuccessAt = Just completedAt
            }
        (Just (addUTCTime (sourceMaximumAge source + 1) completedAt))

handleWageSourceRefreshFailureAfterFinalAttempt ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO [AppJob]
handleWageSourceRefreshFailureAfterFinalAttempt sourceJob
    | sourceJob.attemptsCount < appJobMaxAttempts = pure []
    | otherwise = case sourceForRefreshJobKind sourceJob.jobKind of
        Nothing -> pure []
        Just source -> do
            persistedSourceJob <- fetch sourceJob.id
            if persistedSourceJob.status == JobStatusSucceeded
                then pure []
                else do
                    now <- getCurrentTime
                    enqueueResult <-
                        enqueueHealthCheckOnceWithResult
                            HealthCheckPayload
                                { payloadSource = source
                                , payloadTrigger = FinalRefreshFailure
                                , payloadSourceJobId = unpackId persistedSourceJob.id
                                , payloadEnqueuedAt = now
                                , payloadAnchorSuccessAt = Nothing
                                }
                            Nothing
                    case enqueueResult of
                        ExistingHealthCheck existing -> pure [existing]
                        NewHealthCheck healthCheck -> do
                            performWageSourceHealthCheckJob healthCheck
                            pure [healthCheck]

performWageSourceHealthCheckJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performWageSourceHealthCheckJob appJob = do
    payload <- decodeAppJobPayloadV1 appJob
    now <- getCurrentTime
    performHealthCheck appJob payload now

performWageSourceHealthCheckJobAt ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    AppJob ->
    IO ()
performWageSourceHealthCheckJobAt now appJob =
    decodeAppJobPayloadV1 appJob >>= \payload -> performHealthCheck appJob payload now

performHealthCheck ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    HealthCheckPayload ->
    UTCTime ->
    IO ()
performHealthCheck appJob payload now = do
    unless
        ( appJob.relatedTable == Just "app_jobs"
            && appJob.relatedId == Just payload.payloadSourceJobId
        )
        (throwAppJobError JobInvalidProvenance)
    sourceJob <-
        fetchOneOrNothing (Id payload.payloadSourceJobId :: Id AppJob)
            >>= maybe (throwAppJobError JobInvalidProvenance) pure
    unless (sourceForRefreshJobKind sourceJob.jobKind == Just payload.payloadSource) (throwAppJobError JobInvalidProvenance)
    let localToday = (resolvedInstantLocalTime (resolvedInstantFromUTC now)).localDay
    let targetYears = Set.fromList (targetPublicHolidayYears localToday)
    activeVenues <-
        query @Venue
            |> filterWhere (#status, Active)
            |> filterWhere (#closedAt, Nothing)
            |> orderByAsc #id
            |> fetch
    let activeVenueIds = map (unpackId . (.id)) activeVenues
    facts <- loadWageSourceFactsFor activeVenueIds targetYears
    if scheduledCheckIsSuperseded now targetYears facts payload
        then completeHealthCheck appJob payload [] AnnualNotDue 0 "superseded"
        else do
            let (healthCandidates, annualEvaluation) = evaluateHealthCandidates now localToday activeVenues facts sourceJob payload
            let failureCandidates = evaluateFailureCandidate now targetYears facts sourceJob payload
            let candidates = failureCandidates <> healthCandidates
            recipients <- activeSuperAdmins
            withTransaction do
                completed <-
                    appJob
                        |> set #status JobStatusSucceeded
                        |> set #lastError Nothing
                        |> set #lockedAt Nothing
                        |> set #lockedBy Nothing
                        |> set #result (healthCheckResult payload candidates annualEvaluation (length recipients) "evaluated")
                        |> updateRecord
                forM_ candidates \candidate ->
                    forM_ recipients \recipient ->
                        void $
                            enqueueEmailDelivery
                                EmailDeliveryRequest
                                    { mailKind = alertMailKind candidate.snapshot.source candidate.snapshot.alertKind
                                    , recipientAccountId = unpackId recipient.id
                                    , recipientAddress = recipient.email
                                    , domainReferenceTable = "app_jobs"
                                    , domainReferenceId = unpackId completed.id
                                    , semanticEventKey = candidate.semanticKey
                                    , requestedByUserId = sourceJob.requestedByUserId
                                    , venueId = candidate.snapshot.annualTriggerVenueId
                                    }
            emitBoundedTelemetry payload (length candidates) (length recipients) "evaluated"

completeHealthCheck ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    HealthCheckPayload ->
    [AlertCandidate] ->
    AnnualEvaluation ->
    Int ->
    Text ->
    IO ()
completeHealthCheck appJob payload candidates annualEvaluation recipientCount evaluationStatus = do
    void $
        appJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> set #result (healthCheckResult payload candidates annualEvaluation recipientCount evaluationStatus)
            |> updateRecord
    emitBoundedTelemetry payload (length candidates) recipientCount evaluationStatus

healthCheckResult :: HealthCheckPayload -> [AlertCandidate] -> AnnualEvaluation -> Int -> Text -> Aeson.Value
healthCheckResult payload candidates annualEvaluation recipientCount evaluationStatus =
    Aeson.object
        [ "source" Aeson..= wageSourceText payload.payloadSource
        , "trigger" Aeson..= refreshTriggerText payload.payloadTrigger
        , "evaluationStatus" Aeson..= evaluationStatus
        , "annualEvaluation" Aeson..= annualEvaluationText annualEvaluation
        , "alertCount" Aeson..= length candidates
        , "recipientCount" Aeson..= recipientCount
        , "alerts" Aeson..= map (.snapshot) candidates
        ]

evaluateFailureCandidate ::
    UTCTime ->
    Set.Set Integer ->
    WageSourceFacts ->
    AppJob ->
    HealthCheckPayload ->
    [AlertCandidate]
evaluateFailureCandidate now targetYears facts sourceJob payload
    | payload.payloadTrigger /= FinalRefreshFailure = []
    | otherwise =
        [ AlertCandidate
            { snapshot =
                WageSourceAlertSnapshot
                    { alertKind = RefreshFailedAlert
                    , source = payload.payloadSource
                    , detectedAt = payload.payloadEnqueuedAt
                    , sourceJobId = unpackId sourceJob.id
                    , refreshTriggerClass = Just (if isJust sourceJob.requestedByUserId then ManualRefresh else TimerRefresh)
                    , affectedYears = if payload.payloadSource == DataVicWageSource then Set.toAscList targetYears else []
                    , latestValidSuccessAt = maximumMaybe (catMaybes (map snd basis))
                    , freshnessMaximumAge = Nothing
                    , annualRequiredOnOrAfter = Nothing
                    , annualTriggerVenueId = Nothing
                    }
            , semanticKey =
                Text.intercalate
                    ":"
                    [ "wage-source"
                    , wageSourceText payload.payloadSource
                    , "refresh-failed"
                    , digestText (renderBasis basis)
                    ]
            }
        ]
  where
    basis = validSuccessBasis now targetYears facts payload.payloadSource

evaluateHealthCandidates ::
    UTCTime ->
    Day ->
    [Venue] ->
    WageSourceFacts ->
    AppJob ->
    HealthCheckPayload ->
    ([AlertCandidate], AnnualEvaluation)
evaluateHealthCandidates now localToday activeVenues facts sourceJob payload =
    case payload.payloadSource of
        FwcWageSource ->
            let freshnessCandidates = fwcFreshnessCandidates now facts sourceJob
                (annualCandidates, annualEvaluation) = fwcAnnualCandidates now localToday activeVenues facts sourceJob
             in (freshnessCandidates <> annualCandidates, annualEvaluation)
        DataVicWageSource ->
            (dataVicHealthCandidates now localToday facts sourceJob, AnnualNotDue)

fwcFreshnessCandidates :: UTCTime -> WageSourceFacts -> AppJob -> [AlertCandidate]
fwcFreshnessCandidates now facts sourceJob =
    mapMaybe fromDiagnostic (evaluateFwcFreshnessDiagnostics (PolicyClock now) facts.factFwcSnapshots)
  where
    fromDiagnostic FwcSnapshotMissing =
        Just
            (candidate SourceMissingAlert [] Nothing (Just fwcMaximumAge) "missing")
    fromDiagnostic FwcSnapshotStale { staleCompleteFwcSuccess, maximumFwcAge } =
        Just
            (candidate SourceStaleAlert [] (Just staleCompleteFwcSuccess) (Just maximumFwcAge) ("stale:" <> tshow staleCompleteFwcSuccess))
    fromDiagnostic _ = Nothing
    candidate kind years latest maximumAge key =
        AlertCandidate
            { snapshot = baseSnapshot kind FwcWageSource now sourceJob years latest maximumAge
            , semanticKey = "wage-source:fwc_mapd:" <> key
            }

dataVicHealthCandidates :: UTCTime -> Day -> WageSourceFacts -> AppJob -> [AlertCandidate]
dataVicHealthCandidates now localToday facts sourceJob =
    missingCandidate <> staleCandidate
  where
    targetYears = Set.fromList (targetPublicHolidayYears localToday)
    diagnostics = evaluateDataVicDiagnostics (PolicyClock now) targetYears facts.factDataVicSnapshots
    missingYears = sort [year | DataVicSnapshotMissing year <- diagnostics]
    staleFacts = sort [(year, completedAt) | DataVicSnapshotStale year completedAt _ <- diagnostics]
    missingCandidate =
        [ AlertCandidate
            { snapshot = baseSnapshot SourceMissingAlert DataVicWageSource now sourceJob missingYears Nothing (Just dataVicMaximumAge)
            , semanticKey = "wage-source:data_vic_public_holidays:missing:" <> renderYears missingYears
            }
        | not (null missingYears)
        ]
    staleCandidate =
        [ AlertCandidate
            { snapshot = baseSnapshot SourceStaleAlert DataVicWageSource now sourceJob (map fst staleFacts) (minimumMaybe (map snd staleFacts)) (Just dataVicMaximumAge)
            , semanticKey = "wage-source:data_vic_public_holidays:stale:" <> digestText (renderBasis (map (\(year, at) -> (Just year, Just at)) staleFacts))
            }
        | not (null staleFacts)
        ]

fwcAnnualCandidates ::
    UTCTime ->
    Day ->
    [Venue] ->
    WageSourceFacts ->
    AppJob ->
    ([AlertCandidate], AnnualEvaluation)
fwcAnnualCandidates now localToday activeVenues facts sourceJob =
    case earliestAnnualVenue localToday activeVenues facts.factVenueConfigs of
        Nothing
            | null activeVenues -> ([], AnnualDeferredNoActiveVenue)
            | otherwise -> ([], AnnualNotDue)
        Just (venue, weekStart, weekStartsOn) ->
            case evaluateFwcAnnualDiagnostics (PolicyClock now) weekStart weekStartsOn facts.factFwcSnapshots of
                [FwcAnnualRefreshMissing { annualRefreshRequiredOnOrAfter }] ->
                    let (annualYear, _, _) = toGregorian annualRefreshRequiredOnOrAfter
                     in ( [ AlertCandidate
                                { snapshot =
                                    (baseSnapshot FwcAnnualRefreshMissingAlert FwcWageSource now sourceJob [annualYear] (latestFwcSuccess now facts) Nothing)
                                        { annualRequiredOnOrAfter = Just annualRefreshRequiredOnOrAfter
                                        , annualTriggerVenueId = Just (unpackId venue.id)
                                        }
                                , semanticKey = "wage-source:fwc_mapd:annual-refresh-missing:" <> tshow annualYear
                                }
                          ]
                        , AnnualEvaluated
                        )
                _ -> ([], AnnualEvaluated)

earliestAnnualVenue :: Day -> [Venue] -> Map.Map UUID VenueConfig -> Maybe (Venue, Day, DayOfWeek)
earliestAnnualVenue localToday venues venueConfigs =
    candidates
        |> filter (\(_, firstWeek, _) -> localToday >= firstWeek)
        |> List.sortOn (\(venue, firstWeek, _) -> (firstWeek, venue.id))
        |> listToMaybe
  where
    (year, _, _) = toGregorian localToday
    annualStart = fromGregorian year 7 1
    candidates =
        [ let weekStartsOn = weekdayIndexToDayOfWeek (maybe 1 (.rosterWeekStartsOn) (Map.lookup (unpackId venue.id) venueConfigs))
           in (venue, firstVenueWeekStartingOnOrAfter weekStartsOn annualStart, weekStartsOn)
        | venue <- venues
        ]

baseSnapshot :: WageSourceAlertKind -> WageSourceKind -> UTCTime -> AppJob -> [Integer] -> Maybe UTCTime -> Maybe NominalDiffTime -> WageSourceAlertSnapshot
baseSnapshot kind source now sourceJob years latest maximumAge =
    WageSourceAlertSnapshot
        { alertKind = kind
        , source
        , detectedAt = now
        , sourceJobId = unpackId sourceJob.id
        , refreshTriggerClass = Nothing
        , affectedYears = years
        , latestValidSuccessAt = latest
        , freshnessMaximumAge = maximumAge
        , annualRequiredOnOrAfter = Nothing
        , annualTriggerVenueId = Nothing
        }

scheduledCheckIsSuperseded :: UTCTime -> Set.Set Integer -> WageSourceFacts -> HealthCheckPayload -> Bool
scheduledCheckIsSuperseded now targetYears facts payload =
    case (payload.payloadTrigger, payload.payloadAnchorSuccessAt) of
        (ScheduledFreshnessCheck, Just anchor) ->
            case payload.payloadSource of
                FwcWageSource -> maybe False (> anchor) (latestFwcSuccess now facts)
                DataVicWageSource ->
                    all
                        (\year -> maybe False (> anchor) (latestDataVicSuccessForYear now year facts))
                        (Set.toAscList targetYears)
        _ -> False

latestFwcSuccess :: UTCTime -> WageSourceFacts -> Maybe UTCTime
latestFwcSuccess now facts =
    facts.factFwcSnapshots
        |> mapMaybe
            ( \snapshot ->
                let metadata = snapshot.fwcSnapshotMetadata
                 in if snapshot.provenance == ValidatedMapdSnapshot
                        && metadata.status == CompleteSuccess
                        && metadata.completedAt <= now
                        then Just metadata.completedAt
                        else Nothing
            )
        |> maximumMaybe

latestDataVicSuccessForYear :: UTCTime -> Integer -> WageSourceFacts -> Maybe UTCTime
latestDataVicSuccessForYear now year facts =
    facts.factDataVicSnapshots
        |> mapMaybe
            ( \snapshot ->
                if snapshot.targetYear == year
                    && snapshot.coverage == StatewideVictoria
                    && snapshot.snapshot.status == CompleteSuccess
                    && snapshot.snapshot.completedAt <= now
                    then Just snapshot.snapshot.completedAt
                    else Nothing
            )
        |> maximumMaybe

validSuccessBasis :: UTCTime -> Set.Set Integer -> WageSourceFacts -> WageSourceKind -> [(Maybe Integer, Maybe UTCTime)]
validSuccessBasis now targetYears facts FwcWageSource = [(Nothing, latestFwcSuccess now facts)]
validSuccessBasis now targetYears facts DataVicWageSource =
    [ (Just year, latestDataVicSuccessForYear now year facts)
    | year <- Set.toAscList targetYears
    ]

activeSuperAdmins :: (?modelContext :: ModelContext) => IO [User]
activeSuperAdmins =
    query @User
        |> filterWhere (#platformRole, Just SuperAdmin)
        |> filterWhere (#deactivatedAt, Nothing)
        |> orderByAsc #id
        |> fetch

sourceForRefreshJobKind :: Text -> Maybe WageSourceKind
sourceForRefreshJobKind "fwc_mapd_refresh"       = Just FwcWageSource
sourceForRefreshJobKind "public_holiday_refresh" = Just DataVicWageSource
sourceForRefreshJobKind _                        = Nothing

sourceMaximumAge :: WageSourceKind -> NominalDiffTime
sourceMaximumAge FwcWageSource     = fwcMaximumAge
sourceMaximumAge DataVicWageSource = dataVicMaximumAge

data HealthCheckEnqueueResult
    = NewHealthCheck !AppJob
    | ExistingHealthCheck !AppJob

enqueueHealthCheckOnce :: (?modelContext :: ModelContext) => HealthCheckPayload -> Maybe UTCTime -> IO AppJob
enqueueHealthCheckOnce payload runAt = do
    result <- enqueueHealthCheckOnceWithResult payload runAt
    pure case result of
        NewHealthCheck appJob      -> appJob
        ExistingHealthCheck appJob -> appJob

enqueueHealthCheckOnceWithResult :: (?modelContext :: ModelContext) => HealthCheckPayload -> Maybe UTCTime -> IO HealthCheckEnqueueResult
enqueueHealthCheckOnceWithResult payload runAt = do
    let dedupeKey = healthCheckDedupeKey payload
    existing <-
        query @AppJob
            |> filterWhere (#jobKind, wageSourceHealthCheckJobKind)
            |> filterWhere (#dedupeKey, Just dedupeKey)
            |> orderByAsc #createdAt
            |> fetchOneOrNothing
    case existing of
        Just appJob -> pure (ExistingHealthCheck appJob)
        Nothing -> do
            enqueueResult <-
                enqueueAppJob
                    AppJobRequest
                        { jobKind = wageSourceHealthCheckJobKind
                        , payload = Aeson.toJSON payload
                        , payloadSchemaVersion = 1
                        , requestedByUserId = Nothing
                        , venueId = Nothing
                        , relatedTable = Just "app_jobs"
                        , relatedId = Just payload.payloadSourceJobId
                        , dedupeKey = Just dedupeKey
                        , runAt
                        }
            pure case enqueueResult of
                EnqueuedAppJob appJob       -> NewHealthCheck appJob
                ExistingActiveAppJob appJob -> ExistingHealthCheck appJob

healthCheckDedupeKey :: HealthCheckPayload -> Text
healthCheckDedupeKey payload =
    Text.intercalate
        ":"
        [ "wage-source-health-check"
        , wageSourceText payload.payloadSource
        , refreshTriggerText payload.payloadTrigger
        , tshow payload.payloadSourceJobId
        ]

renderBasis :: [(Maybe Integer, Maybe UTCTime)] -> Text
renderBasis basis =
    Text.intercalate
        "|"
        [ maybe "all" tshow year <> "=" <> maybe "missing" tshow completedAt
        | (year, completedAt) <- basis
        ]

renderYears :: [Integer] -> Text
renderYears = Text.intercalate "," . map tshow

digestText :: Text -> Text
digestText value =
    tshow (Hash.hash (TextEncoding.encodeUtf8 value) :: Hash.Digest Hash.SHA256)

annualEvaluationText :: AnnualEvaluation -> Text
annualEvaluationText AnnualNotDue                = "not_due"
annualEvaluationText AnnualDeferredNoActiveVenue = "deferred_no_active_venue"
annualEvaluationText AnnualEvaluated             = "evaluated"

emitBoundedTelemetry :: HealthCheckPayload -> Int -> Int -> Text -> IO ()
emitBoundedTelemetry payload alertCount recipientCount evaluationStatus =
    TextIO.putStrLn $
        Text.intercalate
            " "
            [ "wage_source_health_check"
            , "source=" <> wageSourceText payload.payloadSource
            , "trigger=" <> refreshTriggerText payload.payloadTrigger
            , "status=" <> evaluationStatus
            , "alerts=" <> tshow alertCount
            , "recipients=" <> tshow recipientCount
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

maximumMaybe :: Ord value => [value] -> Maybe value
maximumMaybe []             = Nothing
maximumMaybe (first : rest) = Just (foldl' max first rest)

minimumMaybe :: Ord value => [value] -> Maybe value
minimumMaybe []             = Nothing
minimumMaybe (first : rest) = Just (foldl' min first rest)
