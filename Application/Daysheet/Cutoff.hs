-- | Cutoff timing policy. Database orchestration must hold the existing venue
-- lock continuously from admitLockedCutoff through capture/commit. These pure
-- decisions do not acquire a lock, authorize a venue, or create a snapshot.
module Application.Daysheet.Cutoff
    ( CutoffPlan, planCutoff, operationalDate, cutoffAt, armAt, lockNotBefore
    , Preparation (..), prepareCutoff
    , LockedCutoff, admitLockedCutoff, remainingWait, captureTime
    , CutoffFailure (..)
    ) where

import Prelude
import Application.VenueTime.Model (BoundaryModelError, resolveBoundaryInstant)
import Data.Text (Text)
import Data.Time

-- Constructors stay private so callers cannot invent a different daily cutoff
-- or widen the pre-lock window. Never fall back to UTC on invalid venue config.
data CutoffPlan = CutoffPlan
    { operationalDate :: Day
    , cutoffAt :: UTCTime
    } deriving (Eq, Show)

data CutoffFailure = OutsideLockWindow | CutoffNotReached | ClockMovedBackwards
    deriving (Eq, Show)

planCutoff :: Text -> Day -> Either BoundaryModelError CutoffPlan
planCutoff timezone day = CutoffPlan day <$> resolveBoundaryInstant timezone (addDays 1 day) (TimeOfDay 6 0 0) Nothing

-- Future AppJobs are polled at a default 60-second interval. Arm earlier than
-- that, but spend the preparation wait outside any database transaction/lock.
armAt :: CutoffPlan -> UTCTime
armAt plan = addUTCTime (-120) (cutoffAt plan)

lockNotBefore :: CutoffPlan -> UTCTime
lockNotBefore plan = addUTCTime (-1) (cutoffAt plan)

data Preparation
    = NotYetArmed UTCTime
    | WaitOutsideLock UTCTime
    | AcquireVenueLock
    | SkipMissedCutoff
    deriving (Eq, Show)

-- Recheck after every wake. A delayed worker is never offered a capture path.
prepareCutoff :: CutoffPlan -> UTCTime -> Preparation
prepareCutoff plan now
    | now < armAt plan = NotYetArmed (armAt plan)
    | now < lockNotBefore plan = WaitOutsideLock (lockNotBefore plan)
    | now < cutoffAt plan = AcquireVenueLock
    | otherwise = SkipMissedCutoff

data LockedCutoff = LockedCutoff CutoffPlan UTCTime deriving (Eq, Show)

-- Call only AFTER obtaining the venue lock and rechecking venue/timezone scope.
-- Waiting for a busy lock can itself miss cutoff, even if preparation was timely.
admitLockedCutoff :: CutoffPlan -> UTCTime -> Either CutoffFailure LockedCutoff
admitLockedCutoff plan acquiredAt
    | prepareCutoff plan acquiredAt == AcquireVenueLock = Right (LockedCutoff plan acquiredAt)
    | otherwise = Left OutsideLockWindow

-- The one-second maximum applies to deliberate pre-cutoff waiting. If wall time
-- moves backwards, release/skip rather than extending a customer-facing lock.
remainingWait :: LockedCutoff -> UTCTime -> Either CutoffFailure NominalDiffTime
remainingWait (LockedCutoff plan acquiredAt) now
    | now < acquiredAt = Left ClockMovedBackwards
    | otherwise = Right (max 0 (diffUTCTime (cutoffAt plan) now))

-- Holding the lock across the boundary excludes later saves. Record the ACTUAL
-- observation time separately from cutoffAt; never backdate captured_at to 6am.
-- Later observation is valid only with uninterrupted ownership of that lock.
-- After rollback/process failure this admission cannot be reused by a retry.
captureTime :: LockedCutoff -> UTCTime -> Either CutoffFailure UTCTime
captureTime locked@(LockedCutoff plan _) now = do
    _ <- remainingWait locked now
    if now < cutoffAt plan then Left CutoffNotReached else Right now
