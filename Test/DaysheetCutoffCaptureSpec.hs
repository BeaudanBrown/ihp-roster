module Test.DaysheetCutoffCaptureSpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.CutoffCapture
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Locks (lockDaysheetVenue)
import Control.Concurrent (newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.Async (withAsync, wait)
import Control.Exception (SomeException, try)
import Data.IORef
import Data.Either (isLeft)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import System.Timeout (timeout)
import Test.DaysheetDailyStorageSpec (setup, day)
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import Test.Support

makeClock :: UTCTime -> IO (CutoffClock, IORef UTCTime)
makeClock time = do
    current <- newIORef time
    pure (CutoffClock (readIORef current) (\duration -> modifyIORef' current (addUTCTime duration)), current)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet scheduled capture boundary" do
        it "holds the same venue lock across cutoff and excludes later saved edits" $ withContext do
            withCleanDb do
                (_, member) <- setup
                Right original <- createDailySheet (memberAccess member) day
                Right planned <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (addUTCTime (-60) (Cutoff.cutoffAt planned))
                preparing <- newEmptyMVar
                beginLockWindow <- newEmptyMVar
                atBoundary <- newEmptyMVar
                release <- newEmptyMVar
                editStarted <- newEmptyMVar
                let controlled = clock { sleep = \duration -> do
                        when (duration == 59) (putMVar preparing () >> takeMVar beginLockWindow)
                        clock.sleep duration
                        when (duration == 1) (putMVar atBoundary () >> takeMVar release) }
                withAsync (withScheduledCutoff controlled member.venueId planned \_ capturedAt -> do
                    capturedAt `shouldBe` Cutoff.cutoffAt planned
                    fmap (.content) <$> readDailySheet (memberAccess member) original.daysheet.id) \capturing -> do
                    takeMVar preparing
                    Just (Right before) <- timeout 1000000 (editDailyCell (memberAccess member) original.daysheet.id
                        (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Before cutoff"))
                    putMVar beginLockWindow ()
                    takeMVar atBoundary
                    withAsync (putMVar editStarted () >> editDailyCell (memberAccess member) original.daysheet.id
                        (Daily.RootCell (Fixture.field 1)) 1 (Fixture.text "After cutoff")) \editing -> do
                        takeMVar editStarted
                        isNothing <$> timeout 50000 (wait editing) `shouldReturn` True
                        putMVar release ()
                        wait capturing `shouldReturn` Right (Just before.content)
                        Right edited <- wait editing
                        edited.content `shouldNotBe` before.content
        it "skips late acquisition and never calls the capture callback on a retry" $ withContext do
            withCleanDb do
                (_, member) <- setup
                Right planned <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                calls <- newIORef (0 :: Int)
                let clock = CutoffClock (pure (Cutoff.cutoffAt planned)) (\_ -> expectationFailure "Late retry must not wait")
                withScheduledCutoff clock member.venueId planned (\_ _ -> modifyIORef' calls (+1) >> pure (Right ())) `shouldReturn` Right Nothing
                readIORef calls `shouldReturn` 0
        it "skips when a competing transaction releases the venue lock after cutoff" $ withContext do
            withCleanDb do
                (_, member) <- setup
                Right planned <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, current) <- makeClock (addUTCTime (-0.5) (Cutoff.cutoffAt planned))
                held <- newEmptyMVar
                unlock <- newEmptyMVar
                started <- newEmptyMVar
                calls <- newIORef (0 :: Int)
                firstRead <- newIORef True
                let observed = clock { now = do
                        value <- clock.now
                        first <- atomicModifyIORef' firstRead (\old -> (False, old))
                        when first (putMVar started ())
                        pure value }
                withAsync (withTransaction do
                    lockDaysheetVenue member.venueId `shouldReturn` True
                    putMVar held ()
                    takeMVar unlock) \holding -> do
                    takeMVar held
                    withAsync (withScheduledCutoff observed member.venueId planned
                        (\_ _ -> modifyIORef' calls (+1) >> pure (Right ()))) \capturing -> do
                        takeMVar started
                        writeIORef current (addUTCTime 1 (Cutoff.cutoffAt planned))
                        putMVar unlock ()
                        wait holding
                        wait capturing `shouldReturn` Right Nothing
                readIORef calls `shouldReturn` 0
        it "rechecks live venue eligibility and releases without a capture after a clock rewind" $ withContext do
            withCleanDb do
                (_, member) <- setup
                Right planned <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, current) <- makeClock (addUTCTime (-0.5) (Cutoff.cutoffAt planned))
                let rewind = clock { sleep = \_ -> modifyIORef' current (addUTCTime (-2)) }
                calls <- newIORef (0 :: Int)
                let capture _ _ = modifyIORef' calls (+1) >> pure (Right ())
                withScheduledCutoff rewind member.venueId planned capture `shouldReturn` Right Nothing
                venue <- fetch (Id member.venueId :: Id Venue)
                _ <- venue |> set #closedAt (Just (Cutoff.cutoffAt planned)) |> updateRecord
                writeIORef current (addUTCTime (-0.5) (Cutoff.cutoffAt planned))
                withScheduledCutoff clock member.venueId planned capture `shouldReturn` Right Nothing
                readIORef calls `shouldReturn` 0
        it "rolls back all callback writes if capture fails and releases the lock" $ withContext do
            withCleanDb do
                (_, member) <- setup
                Right original <- createDailySheet (memberAccess member) day
                Right planned <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (addUTCTime (-0.5) (Cutoff.cutoffAt planned))
                failed <- try @SomeException (withScheduledCutoff clock member.venueId planned \_ _ -> do
                    Right _ <- editDailyCell (memberAccess member) original.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Must roll back")
                    throwIO (userError "simulated capture failure")
                    pure (Right ()))
                failed `shouldSatisfy` isLeft
                Right retained <- readDailySheet (memberAccess member) original.daysheet.id
                retained.content `shouldBe` original.content
