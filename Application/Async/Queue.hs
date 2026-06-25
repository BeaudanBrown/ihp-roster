module Application.Async.Queue
    ( AppJobRequest (..)
    , EnqueueAppJobResult (..)
    , activeAppJobStatuses
    , enqueueAppJob
    , fetchActiveAppJobByDedupeKey
    , fetchLatestAppJobByKind
    ) where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.ModelSupport (sqlQuery)

data AppJobRequest = AppJobRequest
    { jobKind              :: !Text
    , payload              :: !Aeson.Value
    , payloadSchemaVersion :: !Int
    , requestedByUserId    :: !(Maybe UUID)
    , venueId              :: !(Maybe UUID)
    , relatedTable         :: !(Maybe Text)
    , relatedId            :: !(Maybe UUID)
    , dedupeKey            :: !(Maybe Text)
    , runAt                :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data EnqueueAppJobResult
    = EnqueuedAppJob !AppJob
    | ExistingActiveAppJob !AppJob
    deriving (Eq, Show)

activeAppJobStatuses :: [JobStatus]
activeAppJobStatuses =
    [ JobStatusNotStarted
    , JobStatusRunning
    , JobStatusRetry
    ]

enqueueAppJob ::
    (?modelContext :: ModelContext) =>
    AppJobRequest ->
    IO EnqueueAppJobResult
enqueueAppJob request = do
    existingJob <-
        case request.dedupeKey of
            Nothing  -> pure Nothing
            Just key -> fetchActiveAppJobByDedupeKey key
    case existingJob of
        Just appJob -> pure (ExistingActiveAppJob appJob)
        Nothing     -> insertAppJobHandlingDedupeRace request

fetchActiveAppJobByDedupeKey ::
    (?modelContext :: ModelContext) =>
    Text ->
    IO (Maybe AppJob)
fetchActiveAppJobByDedupeKey key =
    query @AppJob
        |> filterWhere (#dedupeKey, Just key)
        |> filterWhereIn (#status, activeAppJobStatuses)
        |> orderByDesc #createdAt
        |> fetchOneOrNothing

fetchLatestAppJobByKind ::
    (?modelContext :: ModelContext) =>
    Text ->
    IO (Maybe AppJob)
fetchLatestAppJobByKind kind =
    query @AppJob
        |> filterWhere (#jobKind, kind)
        |> orderByDesc #createdAt
        |> fetchOneOrNothing

insertAppJobHandlingDedupeRace ::
    (?modelContext :: ModelContext) =>
    AppJobRequest ->
    IO EnqueueAppJobResult
insertAppJobHandlingDedupeRace request = do
    insertedJobs <- insertAppJobIgnoringActiveDedupeConflict request
    case insertedJobs of
        [appJob] -> pure (EnqueuedAppJob appJob)
        [] -> case request.dedupeKey of
            Just key -> do
                existingJob <- fetchActiveAppJobByDedupeKey key
                case existingJob of
                    Just appJob -> pure (ExistingActiveAppJob appJob)
                    Nothing     -> error "App job dedupe conflict occurred but no active job could be fetched"
            Nothing -> error "App job insert returned no row without a dedupe key"
        _ -> error "App job insert unexpectedly returned multiple rows"

insertAppJobIgnoringActiveDedupeConflict ::
    (?modelContext :: ModelContext) =>
    AppJobRequest ->
    IO [AppJob]
insertAppJobIgnoringActiveDedupeConflict request =
    sqlQuery
        "INSERT INTO app_jobs (job_kind, payload, payload_schema_version, requested_by_user_id, venue_id, related_table, related_id, dedupe_key, run_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?::timestamptz, NOW())) ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL AND (status = 'job_status_not_started' OR status = 'job_status_running' OR status = 'job_status_retry') DO NOTHING RETURNING id, created_at, updated_at, status, last_error, attempts_count, locked_at, locked_by, run_at, job_kind, payload, payload_schema_version, requested_by_user_id, venue_id, related_table, related_id, dedupe_key, progress, result"
        ( request.jobKind
        , request.payload
        , request.payloadSchemaVersion
        , request.requestedByUserId
        , request.venueId
        , request.relatedTable
        , request.relatedId
        , request.dedupeKey
        , request.runAt
        )
