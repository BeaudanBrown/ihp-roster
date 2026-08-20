module Application.EmailDelivery.Persistence
    ( EmailDeliveryInsert (..)
    , insertPermanentlyDeduplicatedEmailJob
    ) where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery)


data EmailDeliveryInsert = EmailDeliveryInsert
    { payload           :: !Aeson.Value
    , requestedByUserId :: !(Maybe UUID)
    , venueId           :: !(Maybe UUID)
    , relatedTable      :: !Text
    , relatedId         :: !UUID
    , dedupeKey         :: !Text
    }

-- The email-only partial unique index is the serialization primitive for
-- permanent dedupe. Keeping the matching INSERT here isolates unavoidable raw
-- SQL from mail-kind orchestration and transport.
insertPermanentlyDeduplicatedEmailJob ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryInsert ->
    IO [AppJob]
insertPermanentlyDeduplicatedEmailJob request =
    sqlQuery
        "INSERT INTO app_jobs (job_kind, payload, payload_schema_version, requested_by_user_id, venue_id, related_table, related_id, dedupe_key, run_at) VALUES ('email_delivery', ?, 1, ?, ?, ?, ?, ?, NOW()) ON CONFLICT (dedupe_key) WHERE job_kind = 'email_delivery' AND dedupe_key IS NOT NULL DO NOTHING RETURNING id, created_at, updated_at, status, last_error, attempts_count, locked_at, locked_by, run_at, job_kind, payload, payload_schema_version, requested_by_user_id, venue_id, related_table, related_id, dedupe_key, progress, result"
        ( request.payload
        , request.requestedByUserId
        , request.venueId
        , Just request.relatedTable
        , Just request.relatedId
        , Just request.dedupeKey
        )
