-- | Capture-only queue contract/producer. Kept separate from dispatch so daily
-- creation can enqueue atomically without depending on the report evaluator.
module Application.Daysheet.CutoffJob
    ( cutoffJobKind, CutoffJobPayload (..), enqueueCutoffCapture
    ) where

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
    -- Callers hold the venue lock, including legacy handoff. Keep terminal jobs
    -- too: a retry never creates a second capture task for this day/cutoff.
    existing <- query @DaysheetCaptureJob |> filterWhere (#daysheetId, record.id)
        |> filterWhere (#cutoffAt, Cutoff.cutoffAt plan) |> fetchExists
    unless existing do
        _ <- newRecord @DaysheetCaptureJob |> set #daysheetId record.id
            |> set #cutoffAt (Cutoff.cutoffAt plan) |> set #runAt (Cutoff.armAt plan) |> createRecord
        pure ()
