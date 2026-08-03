module Test.XeroReferenceSyncPolicySpec where

import Application.Helper.Xero
import Application.Xero.Admin.ReferenceSyncPolicy
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Monad (replicateM, void)
import qualified Data.Aeson as Aeson
import Data.IORef
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = do
    describe "Xero reference sync retry policy" do
        it "honours Retry-After while the retry window remains open" do
            let startedAt = testUtc 2026 7 30 0 0
                now = testUtc 2026 7 30 0 5
                errorValue = XeroHttpResponseError 429 (Just (XeroRetryAfterDelay 120)) "Xero rate limit reached."
            xeroReferenceSyncRetryDecision startedAt now 3 7 errorValue
                `shouldBe` RetryXeroReferenceSyncAt (addUTCTime 120 now)

        it "uses bounded jittered exponential delay when Retry-After is unavailable" do
            let startedAt = testUtc 2026 7 30 0 0
                now = testUtc 2026 7 30 0 5
                errorValue = XeroHttpResponseError 503 Nothing "Xero is temporarily unavailable."
            xeroReferenceSyncRetryDecision startedAt now 3 7 errorValue
                `shouldBe` RetryXeroReferenceSyncAt (addUTCTime 247 now)

        it "stops retrying at the 24-hour boundary" do
            let startedAt = testUtc 2026 7 30 0 0
                now = addUTCTime (24 * 60 * 60) startedAt
                errorValue = XeroHttpResponseError 429 (Just (XeroRetryAfterDelay 120)) "Xero rate limit reached."
            xeroReferenceSyncRetryDecision startedAt now 12 0 errorValue
                `shouldBe` FailXeroReferenceSync

        it "does not retry permanent provider failures" do
            let startedAt = testUtc 2026 7 30 0 0
                now = testUtc 2026 7 30 0 5
                errorValue = XeroHttpResponseError 400 Nothing "Xero rejected the request."
            xeroReferenceSyncRetryDecision startedAt now 1 0 errorValue
                `shouldBe` FailXeroReferenceSync
            xeroReferenceSyncRetryDecision startedAt now 1 0 (XeroSemanticError "Xero ValidationException")
                `shouldBe` FailXeroReferenceSync
            xeroReferenceSyncRetryDecision startedAt now 1 0 (XeroHttpError "Xero reference sync tenant lease was lost.")
                `shouldBe` FailXeroReferenceSync
            xeroReferenceSyncRetryDecision startedAt now 1 0 (XeroHttpError "Xero payroll earnings rates pagination repeated a full page without new items.")
                `shouldBe` FailXeroReferenceSync
            xeroReferenceSyncRetryDecision startedAt now 1 0 (XeroHttpError "Xero payroll earnings rates pagination reached the configured safety limit of 1000 pages.")
                `shouldBe` FailXeroReferenceSync
            xeroReferenceSyncRetryDecision startedAt now 1 0 (XeroHttpError "XERO_EARNINGS_RATES_MAX_PAGES must be a positive integer.")
                `shouldBe` FailXeroReferenceSync

    describe "Xero tenant request pacing" do
        it "spaces request starts at no more than 50 requests per minute" do
            xeroReferenceRequestDelayMicros (Just (testUtc 2026 7 30 0 0)) (addUTCTime 0.45 (testUtc 2026 7 30 0 0))
                `shouldBe` 750000

        it "serializes concurrent requests through one in-flight boundary" do
            pacer <- newXeroReferencePacer
            active <- newIORef (0 :: Int)
            maximumActive <- newIORef (0 :: Int)
            done <- replicateM 2 newEmptyMVar
            forM_ done \signal -> void $ forkIO do
                runPacedXeroReferenceRequest pacer getCurrentTime (const (pure ())) do
                    current <- atomicModifyIORef' active \count -> let next = count + 1 in (next, next)
                    atomicModifyIORef' maximumActive \maximumSeen -> (max maximumSeen current, ())
                    threadDelay 10000
                    modifyIORef' active (subtract 1)
                putMVar signal ()
            mapM_ takeMVar done
            readIORef maximumActive `shouldReturn` 1

    describe "paced Xero earnings rates pagination" do
        it "reports each completed page and returns the complete snapshot" do
            requestedPages <- newIORef []
            completedPages <- newIORef []
            let fetchPage page = do
                    modifyIORef' requestedPages (<> [page])
                    pure (Right (if page == 1 then map earningsRate [1 .. 100] else [earningsRate 101]))
            result <- fetchPacedXeroEarningsRates
                (\_ -> pure ())
                fetchPage
                (\page -> modifyIORef' completedPages (<> [page]))
            fmap (map (.xeroEarningsRateId)) result
                `shouldBe` Right (map (\index -> "rate-" <> tshow index) [1 .. 101 :: Int])
            readIORef requestedPages `shouldReturn` [1, 2]
            readIORef completedPages `shouldReturn` [1, 2]

        it "continues beyond 100 pages until the first partial page" do
            requestedPages <- newIORef []
            let fetchPage page = do
                    modifyIORef' requestedPages (<> [page])
                    let firstIndex = (page - 1) * 100 + 1
                    pure (Right (if page <= 101 then map earningsRate [firstIndex .. firstIndex + 99] else [earningsRate firstIndex]))
            result <- fetchPacedXeroEarningsRates (\_ -> pure ()) fetchPage (\_ -> pure ())
            fmap length result `shouldBe` Right 10101
            readIORef requestedPages `shouldReturn` [1 .. 102]

        it "stops at the configured emergency page limit" do
            requestedPages <- newIORef []
            let fetchPage page = do
                    modifyIORef' requestedPages (<> [page])
                    let firstIndex = (page - 1) * 100 + 1
                    pure (Right (map earningsRate [firstIndex .. firstIndex + 99]))
            result <- fetchPacedXeroEarningsRatesWithLimit 2 (\_ -> pure ()) fetchPage (\_ -> pure ())
            result `shouldSatisfy` \case
                Left (XeroHttpError message) -> "configured safety limit of 2 pages" `isInfixOf` message
                _ -> False
            readIORef requestedPages `shouldReturn` [1, 2]

        it "fails safely without reporting a repeated page as completed" do
            requestedPages <- newIORef []
            completedPages <- newIORef []
            let repeatedPage = map earningsRate [1 .. 100]
            let fetchPage page = do
                    modifyIORef' requestedPages (<> [page])
                    pure (Right repeatedPage)
            result <- fetchPacedXeroEarningsRates
                (\_ -> pure ())
                fetchPage
                (\page -> modifyIORef' completedPages (<> [page]))
            result `shouldSatisfy` \case
                Left (XeroHttpError message) -> "repeated a full page" `isInfixOf` message
                _ -> False
            readIORef requestedPages `shouldReturn` [1, 2]
            readIORef completedPages `shouldReturn` [1]

testUtc :: Integer -> Int -> Int -> Integer -> Integer -> UTCTime
testUtc year month day hour minute =
    UTCTime (fromGregorian year month day) (secondsToDiffTime (hour * 3600 + minute * 60))

earningsRate :: Int -> XeroEarningsRateRef
earningsRate index =
    XeroEarningsRateRef
        { xeroEarningsRateId = "rate-" <> tshow index
        , xeroEarningsRateName = "Rate " <> tshow index
        , xeroEarningsRateType = Just "ORDINARYTIMEEARNINGS"
        , xeroEarningsRateRateType = Just "RATEPERUNIT"
        , xeroEarningsRateAccountCode = Nothing
        , xeroEarningsRateTypeOfUnits = Just "Hours"
        , xeroEarningsRateRatePerUnit = Nothing
        , xeroEarningsRateIsActive = True
        , xeroEarningsRateRaw = Aeson.object []
        }
