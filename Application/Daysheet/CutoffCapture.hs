{-# LANGUAGE RankNTypes #-}

-- | A pre-armed background capture boundary, not a delivery worker. Preparation
-- sleeps outside a transaction; the final wait and callback own one venue lock.
module Application.Daysheet.CutoffCapture
    ( CutoffClock (..), systemCutoffClock, withScheduledCutoff
    ) where

import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.Locks (lockDaysheetVenue)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Error.Transaction (withAppResultTransaction)
import Application.Error.Types
import Control.Concurrent (threadDelay)
import Generated.Types
import IHP.ControllerPrelude

-- An explicit clock seam keeps all waits deterministic in concurrency tests.
-- Production uses systemCutoffClock; neither clock nor plan comes from forms.
data CutoffClock = CutoffClock
    { now :: IO UTCTime
    , sleep :: NominalDiffTime -> IO ()
    }

systemCutoffClock :: CutoffClock
systemCutoffClock = CutoffClock getCurrentTime (threadDelay . ceiling . (* 1000000))

withScheduledCutoff :: (?modelContext :: ModelContext) => CutoffClock -> UUID -> Cutoff.CutoffPlan
    -> ((?modelContext :: ModelContext) => Venue -> UTCTime -> IO (AppResult value))
    -> IO (AppResult (Maybe value))
withScheduledCutoff clock venueId plan capture = do
    -- An outer transaction could retain locks throughout the early wait or let
    -- a caller reuse admission after rollback. The worker owns this boundary.
    when (isJust ?modelContext.transactionRunner) $
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Scheduled capture requires its own transaction"
    preparedAt <- clock.now
    ready <- case Cutoff.prepareCutoff plan preparedAt of
        Cutoff.AcquireVenueLock -> pure True
        Cutoff.WaitOutsideLock target -> do
            clock.sleep (diffUTCTime target preparedAt)
            resumedAt <- clock.now
            pure (Cutoff.prepareCutoff plan resumedAt == Cutoff.AcquireVenueLock)
        _ -> pure False
    if not ready then pure (Right Nothing) else withAppResultTransaction do
        locked <- lockDaysheetVenue venueId
        if not locked then pure (Right Nothing) else do
            venue <- fetch (Id venueId :: Id Venue)
            config <- query @VenueConfig |> filterWhere (#venueId, venueId) |> fetchOneOrNothing
            let eligible = venue.status == Active && isNothing venue.closedAt && case config of
                    Just current -> Cutoff.planCutoff current.timezone (Cutoff.operationalDate plan) == Right plan
                    Nothing -> False
            acquiredAt <- clock.now
            case (eligible, Cutoff.admitLockedCutoff plan acquiredAt) of
                (True, Right admission) -> case Cutoff.remainingWait admission acquiredAt of
                    Left _ -> pure (Right Nothing)
                    Right remaining -> do
                        clock.sleep remaining
                        observedAt <- clock.now
                        case Cutoff.captureTime admission observedAt of
                            Left _ -> pure (Right Nothing)
                            Right actualCaptureTime -> fmap (fmap Just) (capture venue actualCaptureTime)
                _ -> pure (Right Nothing)
