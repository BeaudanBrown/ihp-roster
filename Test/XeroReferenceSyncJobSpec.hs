module Test.XeroReferenceSyncJobSpec where

import Application.Async.Queue
import Application.Helper.Xero
import Application.Xero.ReferenceSyncJob
import Application.Xero.ReferenceSyncRequest
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.IORef
import Data.Time.Clock (addUTCTime, diffUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Xero reference sync jobs" do
        it "turns a demand request into background work without calling Xero inline" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Background Demand"
                owner <- createUserRecord "xero-background-demand@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-background-demand"

                result <- runXeroReferenceDataSyncRequest (Just owner.id) connection

                case result of
                    Left message -> message `shouldBe` "Xero payroll reference data is continuing in the background."
                    Right _ -> expectationFailure "Expected the demand request to remain in the background"
                [job] <- query @AppJob |> fetch
                job.status `shouldBe` JobStatusNotStarted
                query @XeroSyncRun |> fetchCount >>= (`shouldBe` 0)

        it "coalesces active requests for one connection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Job Dedupe"
                owner <- createUserRecord "xero-job-dedupe@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-dedupe"

                EnqueuedAppJob firstJob <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                ExistingActiveAppJob secondJob <- enqueueXeroReferenceSyncJob (Just owner.id) connection

                secondJob.id `shouldBe` firstJob.id
                query @AppJob
                    |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "leases one bulk scan per tenant while allowing different tenants" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Tenant Lease A"
                secondVenue <- createVenueWithConfig "Xero Tenant Lease B"
                otherVenue <- createVenueWithConfig "Xero Tenant Lease C"
                owner <- createUserRecord "xero-tenant-lease@example.com" "staff" True
                firstConnection <- createReferenceSyncConnection venue owner "tenant-shared"
                secondConnection <- createReferenceSyncConnection secondVenue owner "tenant-shared"
                otherConnection <- createReferenceSyncConnection otherVenue owner "tenant-other"
                EnqueuedAppJob firstJob <- enqueueXeroReferenceSyncJob Nothing firstConnection
                EnqueuedAppJob secondJob <- enqueueXeroReferenceSyncJob Nothing secondConnection
                EnqueuedAppJob otherJob <- enqueueXeroReferenceSyncJob Nothing otherConnection
                now <- getCurrentTime

                acquireXeroReferenceSyncLease now firstJob firstConnection.tenantId `shouldReturn` True
                acquireXeroReferenceSyncLease now secondJob secondConnection.tenantId `shouldReturn` False
                acquireXeroReferenceSyncLease now otherJob otherConnection.tenantId `shouldReturn` True
                releaseXeroReferenceSyncLease firstJob firstConnection.tenantId
                acquireXeroReferenceSyncLease now secondJob secondConnection.tenantId `shouldReturn` True

        it "preserves tenant pacing when the lease passes to another connection" $ withContext do
            withCleanDb do
                firstVenue <- createVenueWithConfig "Xero Tenant Pace A"
                secondVenue <- createVenueWithConfig "Xero Tenant Pace B"
                owner <- createUserRecord "xero-tenant-pace@example.com" "staff" True
                firstConnection <- createReferenceSyncConnection firstVenue owner "tenant-paced-handoff"
                secondConnection <- createReferenceSyncConnection secondVenue owner "tenant-paced-handoff"
                EnqueuedAppJob firstJob <- enqueueXeroReferenceSyncJob Nothing firstConnection
                EnqueuedAppJob secondJob <- enqueueXeroReferenceSyncJob Nothing secondConnection
                initialTime <- getCurrentTime
                clock <- newIORef initialTime
                delays <- newIORef []
                let runtime = advancingRuntime clock delays
                    firstSource =
                        (emptyReferenceSource firstConnection)
                            { fetchReferencePayrollSettingsAccounts = \_ _ -> do
                                modifyIORef' clock (addUTCTime 0.4)
                                pure (Right [])
                            }

                performXeroReferenceSyncJobWith runtime firstSource firstJob
                delaysAfterFirst <- readIORef delays
                performXeroReferenceSyncJobWith runtime (emptyReferenceSource secondConnection) secondJob
                allDelays <- readIORef delays

                drop (length delaysAfterFirst) allDelays `shouldSatisfy` \case
                    firstDelay : _ -> firstDelay >= 1199000
                    [] -> False

        it "recovers a tenant lease after its bounded expiry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Lease Recovery A"
                secondVenue <- createVenueWithConfig "Xero Lease Recovery B"
                owner <- createUserRecord "xero-lease-recovery@example.com" "staff" True
                firstConnection <- createReferenceSyncConnection venue owner "tenant-recovery"
                secondConnection <- createReferenceSyncConnection secondVenue owner "tenant-recovery"
                EnqueuedAppJob firstJob <- enqueueXeroReferenceSyncJob Nothing firstConnection
                EnqueuedAppJob secondJob <- enqueueXeroReferenceSyncJob Nothing secondConnection
                now <- getCurrentTime

                acquireXeroReferenceSyncLease now firstJob firstConnection.tenantId `shouldReturn` True
                acquireXeroReferenceSyncLease (addUTCTime (xeroReferenceSyncLeaseSeconds + 1) now) secondJob secondConnection.tenantId `shouldReturn` True

        it "runs every paced phase and finalizes one complete snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Complete Background Sync"
                owner <- createUserRecord "xero-complete-job@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-complete"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                calls <- newIORef []
                let source = recordingReferenceSource calls connection
                now <- getCurrentTime

                performXeroReferenceSyncJobWith (testRuntime now) source job

                readIORef calls `shouldReturn` ["refresh", "employees", "pay-items-1", "calendars", "accounts", "payroll-settings"]
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` "succeeded"
                syncRun.finishedAt `shouldSatisfy` isJust
                completedJob <- fetch job.id
                completedJob.status `shouldBe` JobStatusSucceeded
                completedJob.progress `shouldBe` Aeson.object
                    [ "phase" Aeson..= ("completed" :: Text)
                    , "completedPayItemsPage" Aeson..= (1 :: Int)
                    ]

        it "honours a 429 Retry-After by scheduling a sanitized continuation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Retry Background Sync"
                owner <- createUserRecord "xero-retry-job@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-retry"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                now <- getCurrentTime
                let rateLimitError = XeroHttpResponseError 429 (Just (XeroRetryAfterDelay 120)) "Xero employees request failed with status 429: customer@example.com access-token"
                    source = (emptyReferenceSource connection) { fetchReferenceEmployees = \_ _ -> pure (Left rateLimitError) }

                performXeroReferenceSyncJobWith (testRuntime now) source job

                [_, continuation] <- query @AppJob |> orderByAsc #createdAt |> fetch
                abs (diffUTCTime continuation.runAt (addUTCTime 120 now)) `shouldSatisfy` (< 0.001)
                continuation.dedupeKey `shouldBe` job.dedupeKey
                continuation.payload `shouldSatisfy` \payload -> not ("access-token" `isInfixOf` tshow payload)
                completedAttempt <- fetch job.id
                completedAttempt.result `shouldSatisfy` \result ->
                    "retry_scheduled" `isInfixOf` tshow result
                        && not ("access-token" `isInfixOf` tshow result)
                        && not ("customer@example.com" `isInfixOf` tshow result)
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` "failed"
                syncRun.errorMessage `shouldSatisfy` \case
                    Just message -> not ("access-token" `isInfixOf` message) && not ("customer@example.com" `isInfixOf` message)
                    Nothing -> False

        it "retains completed PayItems progress when a later phase retries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Later Phase Retry"
                owner <- createUserRecord "xero-later-phase@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-later-phase"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                now <- getCurrentTime
                let transientError = XeroHttpResponseError 503 Nothing "Xero calendars request failed with status 503"
                    source =
                        (emptyReferenceSource connection)
                            { fetchReferencePayrollCalendars = \_ _ -> pure (Left transientError) }

                performXeroReferenceSyncJobWith (testRuntime now) source job

                completedAttempt <- fetch job.id
                completedAttempt.progress `shouldSatisfy` \progress ->
                    "completedPayItemsPage" `isInfixOf` tshow progress
                        && "1" `isInfixOf` tshow progress

        it "retains the last completed PayItems page when a later page retries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Page Progress Retry"
                owner <- createUserRecord "xero-page-progress@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-page-progress"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                now <- getCurrentTime
                let transientError = XeroHttpResponseError 503 Nothing "Xero pay items request failed with status 503"
                    source =
                        (emptyReferenceSource connection)
                            { fetchReferenceEarningsRatePage = \_ _ page ->
                                pure if page == 1
                                    then Right (replicate 100 sampleEarningsRate)
                                    else Left transientError
                            }

                performXeroReferenceSyncJobWith (testRuntime now) source job

                completedAttempt <- fetch job.id
                completedAttempt.progress `shouldSatisfy` \progress ->
                    "completedPayItemsPage" `isInfixOf` tshow progress
                        && "1" `isInfixOf` tshow progress

        it "stops creating continuations after the 24-hour retry window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Exhausted Background Sync"
                owner <- createUserRecord "xero-exhausted-job@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-exhausted"
                EnqueuedAppJob queuedJob <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                now <- getCurrentTime
                let exhaustedJob = queuedJob |> set #payload (referenceSyncPayload connection (addUTCTime (negate (24 * 60 * 60)) now) 12) |> updateRecord
                    transientError = XeroHttpResponseError 503 Nothing "Xero employees request failed with status 503"
                    source = (emptyReferenceSource connection) { fetchReferenceEmployees = \_ _ -> pure (Left transientError) }
                persistedJob <- exhaustedJob

                result <- Exception.try (performXeroReferenceSyncJobWith (testRuntime now) source persistedJob) :: IO (Either Exception.SomeException ())

                result `shouldSatisfy` isLeft
                query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount >>= (`shouldBe` 1)
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` "failed"

advancingRuntime :: IORef UTCTime -> IORef [Int] -> XeroReferenceSyncRuntime
advancingRuntime clock delays =
    XeroReferenceSyncRuntime
        { currentReferenceSyncTime = readIORef clock
        , sleepForReferenceSyncMicros = \micros -> do
            modifyIORef' delays (<> [micros])
            modifyIORef' clock (addUTCTime (fromIntegral micros / 1000000))
        , referenceSyncJitterSeconds = pure 0
        }

testRuntime :: UTCTime -> XeroReferenceSyncRuntime
testRuntime now =
    XeroReferenceSyncRuntime
        { currentReferenceSyncTime = pure now
        , sleepForReferenceSyncMicros = const (pure ())
        , referenceSyncJitterSeconds = pure 0
        }

recordingReferenceSource :: IORef [Text] -> XeroConnection -> XeroReferenceDataSource
recordingReferenceSource calls connection =
    (emptyReferenceSource connection)
        { refreshReferenceAccess = \_ -> record "refresh" >> pure (Right (connection, "access-token"))
        , fetchReferenceEmployees = \_ _ -> record "employees" >> pure (Right [])
        , fetchReferenceEarningsRatePage = \_ _ page -> record ("pay-items-" <> tshow page) >> pure (Right [])
        , fetchReferencePayrollCalendars = \_ _ -> record "calendars" >> pure (Right [])
        , fetchReferenceAccounts = \_ _ -> record "accounts" >> pure (Right [])
        , fetchReferencePayrollSettingsAccounts = \_ _ -> record "payroll-settings" >> pure (Right [])
        }
    where
        record label = modifyIORef' calls (<> [label])

emptyReferenceSource :: XeroConnection -> XeroReferenceDataSource
emptyReferenceSource connection =
    XeroReferenceDataSource
        { refreshReferenceAccess = \_ -> pure (Right (connection, "access-token"))
        , fetchReferenceEmployees = \_ _ -> pure (Right [])
        , fetchReferenceEarningsRatePage = \_ _ _ -> pure (Right [])
        , fetchReferencePayrollCalendars = \_ _ -> pure (Right [])
        , fetchReferenceAccounts = \_ _ -> pure (Right [])
        , fetchReferencePayrollSettingsAccounts = \_ _ -> pure (Right [])
        }

sampleEarningsRate :: XeroEarningsRateRef
sampleEarningsRate =
    XeroEarningsRateRef
        { xeroEarningsRateId = "page-rate"
        , xeroEarningsRateName = "Page Rate"
        , xeroEarningsRateType = Just "ORDINARYTIMEEARNINGS"
        , xeroEarningsRateRateType = Just "RATEPERUNIT"
        , xeroEarningsRateAccountCode = Nothing
        , xeroEarningsRateTypeOfUnits = Just "Hours"
        , xeroEarningsRateRatePerUnit = Nothing
        , xeroEarningsRateIsActive = True
        , xeroEarningsRateRaw = Aeson.object []
        }

referenceSyncPayload :: XeroConnection -> UTCTime -> Int -> Aeson.Value
referenceSyncPayload connection requestedAt retryNumber =
    Aeson.object
        [ "xeroConnectionId" Aeson..= tshow connection.id
        , "tenantId" Aeson..= connection.tenantId
        , "requestedAt" Aeson..= requestedAt
        , "retryNumber" Aeson..= retryNumber
        ]

createReferenceSyncConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    Text ->
    IO XeroConnection
createReferenceSyncConnection venue owner tenantId = do
    now <- getCurrentTime
    encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey ("refresh-" <> tshow owner.id <> tenantId)
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId tenantId
        |> set #tenantName (Just ("Tenant " <> tenantId))
        |> set #xeroConnectionRemoteId (Just ("connection-" <> tshow venue.id <> tenantId))
        |> set #connectionStatus "active"
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #accessTokenExpiresAt (Just (addUTCTime 1800 now))
        |> set #connectedByUserId (Just (unpackId owner.id))
        |> createRecord

testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "test-client"
        , clientSecret = "test-secret"
        , redirectUri = "http://localhost/XeroOAuthCallback"
        , tokenEncryptionKey = "12345678901234567890123456789012"
        }
