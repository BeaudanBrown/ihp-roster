module Test.DaysheetCutoffSpec where

import Prelude
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.VenueTime.Model (BoundaryModelError (..))
import Data.Time
import Test.Hspec

plan :: IO Cutoff.CutoffPlan
plan = do
    Right value <- pure (Cutoff.planCutoff "Australia/Melbourne" (fromGregorian 2026 10 5))
    pure value

tests :: Spec
tests = describe "Daysheet cutoff policy" do
    it "targets the following venue-local 6am for the previous Operational day" do
        scheduled <- plan
        Cutoff.operationalDate scheduled `shouldBe` fromGregorian 2026 10 5
        Cutoff.cutoffAt scheduled `shouldBe` UTCTime (fromGregorian 2026 10 5) (secondsToDiffTime (19 * 3600))
    it "resolves DST boundaries as civil cutoffs rather than adding 24 hours" do
        Right beforeEnd <- pure (Cutoff.planCutoff "Australia/Melbourne" (fromGregorian 2026 4 3))
        Right afterEnd <- pure (Cutoff.planCutoff "Australia/Melbourne" (fromGregorian 2026 4 4))
        diffUTCTime (Cutoff.cutoffAt afterEnd) (Cutoff.cutoffAt beforeEnd) `shouldBe` 25 * 3600
        Right beforeStart <- pure (Cutoff.planCutoff "Australia/Melbourne" (fromGregorian 2026 10 2))
        Right afterStart <- pure (Cutoff.planCutoff "Australia/Melbourne" (fromGregorian 2026 10 3))
        diffUTCTime (Cutoff.cutoffAt afterStart) (Cutoff.cutoffAt beforeStart) `shouldBe` 23 * 3600
    it "fails closed for unsupported timezone configuration, without a UTC fallback" do
        Cutoff.planCutoff "Not/AZone" (fromGregorian 2026 10 5) `shouldBe` Left (BoundaryUnsupportedTimezone "Not/AZone")
    it "arms early but waits outside the lock until the final second" do
        scheduled <- plan
        let at seconds = addUTCTime seconds (Cutoff.cutoffAt scheduled)
        Cutoff.prepareCutoff scheduled (at (-121)) `shouldBe` Cutoff.NotYetArmed (at (-120))
        mapM_ (\offset -> Cutoff.prepareCutoff scheduled (at offset) `shouldBe` Cutoff.WaitOutsideLock (at (-1))) [-120, -60, -2, -1.001]
        mapM_ (\offset -> Cutoff.prepareCutoff scheduled (at offset) `shouldBe` Cutoff.AcquireVenueLock) [-1, -0.5, -0.001]
        mapM_ (\offset -> Cutoff.prepareCutoff scheduled (at offset) `shouldBe` Cutoff.SkipMissedCutoff) [0, 0.001, 60, 3600, 86400]
    it "rechecks time after lock contention and cannot admit a late retry" do
        scheduled <- plan
        let boundary = Cutoff.cutoffAt scheduled
        Cutoff.prepareCutoff scheduled (addUTCTime (-0.5) boundary) `shouldBe` Cutoff.AcquireVenueLock
        Cutoff.admitLockedCutoff scheduled boundary `shouldBe` Left Cutoff.OutsideLockWindow
        Cutoff.admitLockedCutoff scheduled (addUTCTime 600 boundary) `shouldBe` Left Cutoff.OutsideLockWindow
        Cutoff.admitLockedCutoff scheduled (addUTCTime (-1.001) boundary) `shouldBe` Left Cutoff.OutsideLockWindow
    it "does not capture early or backdate the actual capture observation" do
        scheduled <- plan
        let boundary = Cutoff.cutoffAt scheduled
        Right locked <- pure (Cutoff.admitLockedCutoff scheduled (addUTCTime (-0.5) boundary))
        Cutoff.remainingWait locked (addUTCTime (-0.2) boundary) `shouldBe` Right 0.2
        Cutoff.captureTime locked (addUTCTime (-0.001) boundary) `shouldBe` Left Cutoff.CutoffNotReached
        Cutoff.captureTime locked boundary `shouldBe` Right boundary
        Cutoff.captureTime locked (addUTCTime 0.01 boundary) `shouldBe` Right (addUTCTime 0.01 boundary)
        Cutoff.remainingWait locked (addUTCTime 0.01 boundary) `shouldBe` Right 0
    it "refuses to lengthen a held lock after a backwards wall-clock movement" do
        scheduled <- plan
        let boundary = Cutoff.cutoffAt scheduled
        Right locked <- pure (Cutoff.admitLockedCutoff scheduled (addUTCTime (-0.5) boundary))
        Cutoff.remainingWait locked (addUTCTime (-1.5) boundary) `shouldBe` Left Cutoff.ClockMovedBackwards
        Cutoff.captureTime locked (addUTCTime (-1.5) boundary) `shouldBe` Left Cutoff.ClockMovedBackwards
