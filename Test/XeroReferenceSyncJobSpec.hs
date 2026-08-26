module Test.XeroReferenceSyncJobSpec where

import Application.Async.Queue
import Application.Helper.Xero
import Application.Xero.Admin.ReferenceData (XeroReferenceDataSyncResult,
                                             completeXeroReferenceDataSync,
                                             startXeroReferenceDataSync)
import Application.Xero.ReferenceSyncJob
import Application.Xero.ReferenceSyncRequest
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Application.Xero.ReferenceTrust.Service
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.IORef
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, diffUTCTime, getCurrentTime,
                        secondsToDiffTime)
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
                publications <- newIORef []

                (firstJob, secondJob) <- withXeroReferenceSyncRuntimeForTest (recordingRuntime fixedReferenceSyncTime publications) do
                    EnqueuedAppJob firstJob <- requestXeroReferenceSyncJob (Just owner.id) connection
                    ExistingActiveAppJob secondJob <- requestXeroReferenceSyncJob (Just owner.id) connection
                    pure (firstJob, secondJob)

                readIORef publications `shouldReturn` ["xero.reference_sync.queued"]
                secondJob.id `shouldBe` firstJob.id
                query @AppJob
                    |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "publishes a queued transition from the manual request boundary" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Manual Request Publication"
                owner <- createUserRecord "xero-manual-request-publication@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-manual-request-publication"
                publications <- newIORef []

                result <- withXeroReferenceSyncRuntimeForTest (recordingRuntime fixedReferenceSyncTime publications) $
                    runXeroReferenceDataSyncRequest (Just owner.id) connection

                case result of
                    Left message -> message `shouldBe` "Xero payroll reference data is continuing in the background."
                    Right _ -> expectationFailure "Expected a queued background reference-sync request"
                readIORef publications `shouldReturn` ["xero.reference_sync.queued"]

        it "converges repeated command requests after one successful refresh" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Successful Request Convergence"
                owner <- createUserRecord "xero-successful-request-convergence@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-successful-request-convergence"
                let requestedAt = fixedReferenceSyncTime

                firstState <- requestTrustedXeroReferenceData requestedAt (Just owner.id) connection NoMissingPayrollReferenceDemand
                firstState.trustDecision `shouldSatisfy` \case
                    WaitForTrustedXeroReferenceSnapshot _ -> True
                    _ -> False
                [job] <- query @AppJob |> fetch
                let durableRuntime = (testRuntime requestedAt) { publishReferenceSyncTransition = publishReferenceSyncTransitionLive }
                performXeroReferenceSyncJobWith durableRuntime (emptyReferenceSource connection) job
                [durableEvent] <- query @LiveInvalidationEvent |> filterWhere (#source, "xero.reference_sync.completed" :: Text) |> fetch
                query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetchCount `shouldReturn` 1
                let observedAt = addUTCTime 60 requestedAt

                forM_ [1 .. 3 :: Int] \_ -> do
                    state <- requestTrustedXeroReferenceData observedAt (Just owner.id) connection MissingPayrollEligibleStaffReference
                    state.trustDecision `shouldBe` UseTrustedXeroReferenceSnapshot

                query @AppJob |> fetchCount >>= (`shouldBe` 1)
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` Succeeded

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

        it "publishes tenant-lease contention as a failure before retry waiting" $ withContext do
            withCleanDb do
                firstVenue <- createVenueWithConfig "Xero Lease Publication First"
                secondVenue <- createVenueWithConfig "Xero Lease Publication Second"
                owner <- createUserRecord "xero-lease-publication@example.com" "staff" True
                firstConnection <- createReferenceSyncConnection firstVenue owner "tenant-lease-publication"
                secondConnection <- createReferenceSyncConnection secondVenue owner "tenant-lease-publication"
                EnqueuedAppJob firstJob <- enqueueXeroReferenceSyncJob Nothing firstConnection
                EnqueuedAppJob secondJob <- enqueueXeroReferenceSyncJob Nothing secondConnection
                let now = fixedReferenceSyncTime
                publications <- newIORef []
                acquireXeroReferenceSyncLease now firstJob firstConnection.tenantId `shouldReturn` True

                performXeroReferenceSyncJobWith (recordingRuntime now publications) (emptyReferenceSource secondConnection) secondJob

                publishedTransitions <- readIORef publications
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.failed" `elem`)
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.retry_wait" `elem`)

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

        it "does not repeat provider work when a retry follows a committed snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Committed Snapshot Retry"
                owner <- createUserRecord "xero-committed-snapshot-retry@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-committed-snapshot-retry"
                let now = fixedReferenceSyncTime
                currentConnection <- connection |> set #lastSyncAt (Just now) |> updateRecord
                EnqueuedAppJob queuedJob <- enqueueXeroReferenceSyncJob (Just owner.id) currentConnection
                job <- queuedJob
                    |> set #payload (referenceSyncPayload currentConnection (addUTCTime (-1) now) 1)
                    |> updateRecord
                calls <- newIORef []
                publications <- newIORef []

                performXeroReferenceSyncJobWith (recordingRuntime now publications) (recordingReferenceSource calls currentConnection) job

                readIORef publications `shouldReturn` ["xero.reference_sync.skipped"]
                readIORef calls `shouldReturn` []
                query @XeroSyncRun |> fetchCount >>= (`shouldBe` 0)
                completedJob <- fetch job.id
                completedJob.status `shouldBe` JobStatusSucceeded
                completedJob.result `shouldBe` Aeson.object
                    [ "status" Aeson..= ("skipped" :: Text)
                    , "reason" Aeson..= ("snapshot_already_current" :: Text)
                    ]

        it "terminalizes a run when an unexpected interruption escapes the worker" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Interrupted Worker Sync"
                owner <- createUserRecord "xero-interrupted-worker@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-interrupted-worker"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                publications <- newIORef []
                let now = fixedReferenceSyncTime
                    interruptedSource =
                        (emptyReferenceSource connection)
                            { fetchReferenceEmployees = \_ _ -> Exception.throwIO (userError "worker interrupted")
                            }

                result <- Exception.try (performXeroReferenceSyncJobWith (recordingRuntime now publications) interruptedSource job) :: IO (Either Exception.SomeException ())

                result `shouldSatisfy` isLeft
                publishedTransitions <- readIORef publications
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.interrupted" `elem`)
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed
                syncRun.finishedAt `shouldSatisfy` isJust
                syncRun.errorMessage `shouldBe` Just "Xero worker sync failed."
                interruptedJob <- fetch job.id
                interruptedJob.progress `shouldBe` Aeson.object
                    [ "phase" Aeson..= ("worker" :: Text)
                    , "failureCode" Aeson..= ("transport_error" :: Text)
                    ]

        it "terminalizes an interrupted run before starting its replacement" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Interrupted Background Sync"
                owner <- createUserRecord "xero-interrupted-job@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-interrupted"
                interruptedRun <- startXeroReferenceDataSync connection
                EnqueuedAppJob replacementJob <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                let now = fixedReferenceSyncTime

                performXeroReferenceSyncJobWith (testRuntime now) (emptyReferenceSource connection) replacementJob
                lateCompletion <- Exception.try (completeXeroReferenceDataSync Nothing interruptedRun connection [] [] [] [] []) :: IO (Either Exception.SomeException XeroReferenceDataSyncResult)

                case lateCompletion of
                    Left _ -> pure ()
                    Right _ -> expectationFailure "Expected a superseded sync run to reject late completion"
                terminalizedRun <- fetch interruptedRun.id
                terminalizedRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed
                terminalizedRun.finishedAt `shouldSatisfy` isJust
                terminalizedRun.errorMessage `shouldBe` Just "Xero worker sync failed."
                runs <- query @XeroSyncRun |> orderByAsc #createdAt |> fetch
                map (.syncStatus) runs `shouldBe` [XeroSyncStatusEnumFailed, Succeeded]

        it "runs every paced phase and finalizes one complete snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Complete Background Sync"
                owner <- createUserRecord "xero-complete-job@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-complete"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                calls <- newIORef []
                publications <- newIORef []
                let source = recordingReferenceSource calls connection
                now <- getCurrentTime

                performXeroReferenceSyncJobWith (recordingRuntime now publications) source job

                readIORef publications `shouldReturn` ["xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.progress", "xero.reference_sync.completed"]
                readIORef calls `shouldReturn` ["refresh", "employees", "pay-items-1", "calendars", "accounts", "payroll-settings"]
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` Succeeded
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
                publications <- newIORef []
                now <- getCurrentTime
                let rateLimitError = XeroHttpResponseError 429 (Just (XeroRetryAfterDelay 120)) "Xero employees request failed with status 429: customer@example.com access-token"
                    source = (emptyReferenceSource connection) { fetchReferenceEmployees = \_ _ -> pure (Left rateLimitError) }

                performXeroReferenceSyncJobWith (recordingRuntime now publications) source job

                publishedTransitions <- readIORef publications
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.failed" `elem`)
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.retry_wait" `elem`)
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
                syncRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed
                syncRun.errorMessage `shouldSatisfy` \case
                    Just message -> not ("access-token" `isInfixOf` message) && not ("customer@example.com" `isInfixOf` message)
                    Nothing -> False

        it "retains completed earnings-rate progress when a later phase retries" $ withContext do
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

        it "retains the last completed earnings-rate page when a later page retries" $ withContext do
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

        it "persists a safe reason when an earnings-rate page repeats" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Repeated Earnings Page"
                owner <- createUserRecord "xero-repeated-page@example.com" "staff" True
                connection <- createReferenceSyncConnection venue owner "tenant-repeated-page"
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob (Just owner.id) connection
                now <- getCurrentTime
                let repeatedPage = replicate 100 sampleEarningsRate
                    source =
                        (emptyReferenceSource connection)
                            { fetchReferenceEarningsRatePage = \_ _ _ -> pure (Right repeatedPage) }

                result <- Exception.try (performXeroReferenceSyncJobWith (testRuntime now) source job) :: IO (Either Exception.SomeException ())

                result `shouldSatisfy` isLeft
                failedJob <- fetch job.id
                failedJob.progress `shouldBe` Aeson.object
                    [ "phase" Aeson..= ("pay_items" :: Text)
                    , "completedPayItemsPage" Aeson..= (1 :: Int)
                    , "failureCode" Aeson..= ("repeated_page" :: Text)
                    ]
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.errorMessage `shouldSatisfy` \case
                    Just message -> "repeated an earnings-rate page" `isInfixOf` message
                    Nothing -> False

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
                publications <- newIORef []

                result <- Exception.try (performXeroReferenceSyncJobWith (recordingRuntime now publications) source persistedJob) :: IO (Either Exception.SomeException ())

                result `shouldSatisfy` isLeft
                publishedTransitions <- readIORef publications
                publishedTransitions `shouldSatisfy` ("xero.reference_sync.failed" `elem`)
                publishedTransitions `shouldSatisfy` (not . ("xero.reference_sync.retry_wait" `elem`))
                query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount >>= (`shouldBe` 1)
                [syncRun] <- query @XeroSyncRun |> fetch
                syncRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed

advancingRuntime :: IORef UTCTime -> IORef [Int] -> XeroReferenceSyncRuntime
advancingRuntime clock delays =
    XeroReferenceSyncRuntime
        { currentReferenceSyncTime = readIORef clock
        , sleepForReferenceSyncMicros = \micros -> do
            modifyIORef' delays (<> [micros])
            modifyIORef' clock (addUTCTime (fromIntegral micros / 1000000))
        , referenceSyncJitterSeconds = pure 0
        , publishReferenceSyncTransition = \_ _ -> pure ()
        }

fixedReferenceSyncTime :: UTCTime
fixedReferenceSyncTime = UTCTime (fromGregorian 2026 8 7) (secondsToDiffTime 0)

testRuntime :: UTCTime -> XeroReferenceSyncRuntime
testRuntime now =
    XeroReferenceSyncRuntime
        { currentReferenceSyncTime = pure now
        , sleepForReferenceSyncMicros = const (pure ())
        , referenceSyncJitterSeconds = pure 0
        , publishReferenceSyncTransition = \_ _ -> pure ()
        }

recordingRuntime :: UTCTime -> IORef [Text] -> XeroReferenceSyncRuntime
recordingRuntime now publications =
    (testRuntime now)
        { publishReferenceSyncTransition = \label _ -> modifyIORef' publications (<> [label])
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
