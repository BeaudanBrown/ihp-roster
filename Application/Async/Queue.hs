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

data AppJobRequest = AppJobRequest
    { jobKind              :: !Text
    , payload              :: !Aeson.Value
    , payloadSchemaVersion :: !Int
    , requestedByUserId    :: !(Maybe UUID)
    , tenantId             :: !(Maybe UUID)
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
        Nothing -> do
            appJob <-
                newRecord @AppJob
                    |> set #jobKind request.jobKind
                    |> set #payload request.payload
                    |> set #payloadSchemaVersion request.payloadSchemaVersion
                    |> set #requestedByUserId request.requestedByUserId
                    |> set #tenantId request.tenantId
                    |> set #relatedTable request.relatedTable
                    |> set #relatedId request.relatedId
                    |> set #dedupeKey request.dedupeKey
                    |> setRunAt request.runAt
                    |> createRecord
            pure (EnqueuedAppJob appJob)

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

setRunAt :: Maybe UTCTime -> AppJob -> AppJob
setRunAt Nothing appJob      = appJob
setRunAt (Just runAt) appJob = appJob |> set #runAt runAt
