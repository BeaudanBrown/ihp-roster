module Application.Async.Heartbeat
    ( performWorkerHeartbeatJob
    , workerHeartbeatJobKind
    ) where

import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

workerHeartbeatJobKind :: Text
workerHeartbeatJobKind = "worker_heartbeat"

performWorkerHeartbeatJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
performWorkerHeartbeatJob appJob = do
    now <- getCurrentTime
    void $
        appJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> set #result (Aeson.object ["status" Aeson..= ("heartbeat" :: Text), "completedAt" Aeson..= now])
            |> updateRecord
