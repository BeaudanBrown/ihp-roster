-- | Capture-only queue contract/producer. Kept separate from dispatch so daily
-- creation can enqueue atomically without depending on the report evaluator.
module Application.Daysheet.CutoffJob
    ( cutoffJobKind, CutoffJobPayload (..), enqueueCutoffCapture
    ) where

import Application.Async.Queue
import qualified Application.Daysheet.Cutoff as Cutoff
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

cutoffJobKind :: Text
cutoffJobKind = "daysheet_report_capture"

data CutoffJobPayload = CutoffJobPayload
    { daysheetId :: UUID
    , operationalDate :: Day
    , cutoffAt :: UTCTime
    } deriving (Eq, Show)

instance Aeson.ToJSON CutoffJobPayload where
    toJSON value = Aeson.object ["daysheetId" Aeson..= value.daysheetId, "operationalDate" Aeson..= value.operationalDate, "cutoffAt" Aeson..= value.cutoffAt]
instance Aeson.FromJSON CutoffJobPayload where
    parseJSON = Aeson.withObject "Daysheet cutoff" \value -> do
        unless (length value == 3) (fail "invalid cutoff envelope")
        CutoffJobPayload <$> value Aeson..: "daysheetId" <*> value Aeson..: "operationalDate" <*> value Aeson..: "cutoffAt"

-- Called inside explicit creation's venue transaction. Never create a business
-- day from a timer, and never enqueue historical catch-up work.
enqueueCutoffCapture :: (?modelContext :: ModelContext) => UTCTime -> Daysheet -> Cutoff.CutoffPlan -> IO ()
enqueueCutoffCapture now record plan = when (now < Cutoff.cutoffAt plan) do
    _ <- enqueueAppJob AppJobRequest
        { jobKind = cutoffJobKind
        , payload = Aeson.toJSON (CutoffJobPayload (unpackId record.id) record.operationalDate (Cutoff.cutoffAt plan))
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing
        , venueId = Just (unpackId record.venueId)
        , relatedTable = Just "daysheets"
        , relatedId = Just (unpackId record.id)
        , dedupeKey = Just ("daysheet-cutoff:" <> tshow (unpackId record.id) <> ":" <> tshow (Cutoff.cutoffAt plan))
        , runAt = Just (Cutoff.armAt plan)
        }
    pure ()
