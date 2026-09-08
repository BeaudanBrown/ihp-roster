{-# LANGUAGE TypeApplications #-}

module Test.DurableLiveInvalidationSpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import qualified Application.Helper.FrontendContract.Surface.Admin.Resource as AdminResource
import qualified Application.Helper.FrontendContract.Surface.Support.Resource as SupportResource
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   encodeDurableResource)
import Application.Helper.LiveUpdate.DurableListener (hydrateDurableStateFromConnection,
                                                      readDurableEventsAfter,
                                                      runDurableInvalidationListenerConnection,
                                                      startDurableInvalidationListener)
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..),
                                                       withDurableLiveMutationOutcomeTransaction)
import Application.Helper.LiveUpdate.DurableState (currentDurableCursor,
                                                   currentDurableDependencyWatermark,
                                                   fetchDurableDependencyWatermark,
                                                   replaceDurableResourceVersions)
import Application.Helper.LiveUpdate.OutboxPruning
import Application.Helper.LiveUpdate.Runtime (SurfaceSubscription (..),
                                              currentLiveUpdateVersionWithBus,
                                              newInMemoryLiveBus,
                                              registerSurfaceSubscriptionWithBus,
                                              surfaceScopeKey)
import Application.Helper.SurfaceResource (SurfaceResourceValue,
                                           liveMutationResult)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, concurrently, waitCatch,
                                 withAsync)
import Control.Concurrent.Chan (newChan, readChan, writeChan)
import Control.Monad (replicateM_)
import qualified Control.Exception as Exception
import qualified Data.ByteString as ByteString
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, diffUTCTime)
import Data.UUID (UUID, nil)
import Database.PostgreSQL.Simple (Only (..))
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Notification as PGNotification
import Database.PostgreSQL.Simple.Types (Query (..))
import IHP.ModelSupport (sqlExec, sqlExecDiscardResult, sqlQuery,
                         sqlQueryScalar)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import System.Environment (getEnv)
import System.Timeout (timeout)
import Test.Hspec
import Test.Support
import Application.Helper.LiveUpdate.BackgroundMutation (withDurableLiveMutationWithoutContext,
                                                        withDurableLiveMutationOutcomeWithoutContext)
import Web.SurfaceInvalidation (dispatchDurableInvalidationWithBus)

publishTestDurableInvalidation :: (?modelContext :: ModelContext) => Text -> Set.Set SurfaceResourceValue -> IO DurablePublication
publishTestDurableInvalidation source resources = do
    (_, maybePublication) <-
        withDurableLiveMutationOutcomeTransaction
            (const (Just (source, resources)))
            (pure ())
    maybe (error "test durable publication missing") pure maybePublication

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
        describe "Durable live invalidation publication" do
            it "atomically commits a business write with its event and resource version" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    _ <- withDurableLiveMutationWithoutContext "test.atomic.commit" do
                        user <- createUserRecord "atomic-live@example.com" "staff" True
                        pure (liveMutationResult user [resource])

                    userCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM users WHERE email = 'atomic-live@example.com'" ()
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE source = 'test.atomic.commit'" ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
                    userCount `shouldBe` 1
                    eventCount `shouldBe` 1
                    versionCount `shouldBe` 1

            it "commits an explicit non-publication outcome even when the value is Left" $ withContext do
                withCleanDb do
                    result <- withDurableLiveMutationOutcomeWithoutContext (const Nothing) do
                        _ <- createUserRecord "atomic-no-publication@example.com" "staff" True
                        pure (Left "retained outcome" :: Either Text ())
                    result `shouldBe` Left "retained outcome"
                    userCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM users WHERE email = 'atomic-no-publication@example.com'" ()
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
                    resourceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources" ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
                    (userCount, eventCount, resourceCount, versionCount) `shouldBe` (1, 0, 0, 0)

            it "rolls back the business write when durable publication fails" $ withContext do
                withCleanDb do
                    let invalidSource = Text.replicate 121 "x"
                    let resource = AdminResource.adminVenueSettingsResource nil
                    _ <- Exception.try @Exception.SomeException $
                        withDurableLiveMutationWithoutContext invalidSource do
                            user <- createUserRecord "atomic-live-rollback@example.com" "staff" True
                            pure (liveMutationResult user [resource])

                    userCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM users WHERE email = 'atomic-live-rollback@example.com'" ()
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
                    userCount `shouldBe` 0
                    eventCount `shouldBe` 0
                    versionCount `shouldBe` 0

            it "rolls back an attempted event when the business mutation fails" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    _ <- Exception.try @Exception.SomeException $
                        withDurableLiveMutationWithoutContext "test.atomic.business-failure" do
                            _ <- createUserRecord "atomic-business-rollback@example.com" "staff" True
                            Exception.throwIO (userError "force business rollback")
                            pure (liveMutationResult () [resource])

                    userCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM users WHERE email = 'atomic-business-rollback@example.com'" ()
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
                    userCount `shouldBe` 0
                    eventCount `shouldBe` 0

            it "rolls back the business mutation after durable publication is attempted" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    let installFailure = do
                            sqlExecDiscardResult "CREATE FUNCTION test_reject_live_event_resource() RETURNS trigger AS 'BEGIN RAISE EXCEPTION ''forced publication failure''; END' LANGUAGE plpgsql" ()
                            sqlExecDiscardResult "CREATE TRIGGER test_reject_live_event_resource BEFORE INSERT ON live_invalidation_event_resources FOR EACH ROW EXECUTE FUNCTION test_reject_live_event_resource()" ()
                    let removeFailure = do
                            sqlExecDiscardResult "DROP TRIGGER IF EXISTS test_reject_live_event_resource ON live_invalidation_event_resources" ()
                            sqlExecDiscardResult "DROP FUNCTION IF EXISTS test_reject_live_event_resource()" ()
                    Exception.bracket_ installFailure removeFailure do
                        _ <- Exception.try @Exception.SomeException $
                            withDurableLiveMutationWithoutContext "test.atomic.publication-failure" do
                                user <- createUserRecord "atomic-publication-rollback@example.com" "staff" True
                                pure (liveMutationResult user [resource])
                        pure ()

                    userCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM users WHERE email = 'atomic-publication-rollback@example.com'" ()
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
                    resourceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources" ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
                    userCount `shouldBe` 0
                    eventCount `shouldBe` 0
                    resourceCount `shouldBe` 0
                    versionCount `shouldBe` 0

            it "persists one event resource and current version for duplicate resources" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.live" (Set.fromList [resource, resource])
                    let eventId = publication.durablePublicationEventId

                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE id = ?" (Only eventId)
                    resourceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources WHERE event_id = ?" (Only eventId)
                    versionEventId :: UUID <- sqlQueryScalar "SELECT latest_event_id FROM live_resource_versions" ()
                    eventCount `shouldBe` 1
                    resourceCount `shouldBe` 1
                    versionEventId `shouldBe` eventId
                    publication.durablePublicationResourceCount `shouldBe` 1
                    publication.durablePublicationPayloadBytes `shouldSatisfy` (> 0)
                    publication.durablePublicationDurationMs `shouldSatisfy` (>= 0)

            it "keeps the greatest event sequence as the concurrent current version" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    _ <- concurrently
                        (publishTestDurableInvalidation "test.concurrent.left" (Set.singleton resource))
                        (publishTestDurableInvalidation "test.concurrent.right" (Set.singleton resource))

                    latestSequence :: Int <- sqlQueryScalar "SELECT latest_event_sequence FROM live_resource_versions" ()
                    greatestEventSequence :: Int <- sqlQueryScalar "SELECT MAX(sequence_number) FROM live_invalidation_events" ()
                    latestSequence `shouldBe` greatestEventSequence

            it "delivers one committed event independently through two process-local hubs" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.two-hubs" (Set.singleton resource)
                    let Right encoded = encodeDurableResource resource
                    let scope = AdminLive.adminVenueConfigLiveScope nil
                    let subscription = SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                            , subscriptionRenderedDependencyWatermark = 0
                            }
                    firstBus <- newInMemoryLiveBus
                    secondBus <- newInMemoryLiveBus
                    registerSurfaceSubscriptionWithBus firstBus nil subscription (error "closed test websocket")
                    registerSurfaceSubscriptionWithBus secondBus nil subscription (error "closed test websocket")
                    dispatchDurableInvalidationWithBus (Just firstBus) publication.durablePublicationEventSequence [encoded]
                    dispatchDurableInvalidationWithBus (Just secondBus) publication.durablePublicationEventSequence [encoded]
                    currentLiveUpdateVersionWithBus firstBus scope `shouldReturn` publication.durablePublicationEventSequence
                    currentLiveUpdateVersionWithBus secondBus scope `shouldReturn` publication.durablePublicationEventSequence

            it "advances durable freshness without subscribers so a stale rendered mount resyncs later" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.watermark" (Set.singleton resource)
                    let Right encoded = encodeDurableResource resource
                    let scope = AdminLive.adminVenueConfigLiveScope nil
                    let subscription = SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                            , subscriptionRenderedDependencyWatermark = 0
                            }
                    fetchDurableDependencyWatermark subscription `shouldReturn` publication.durablePublicationEventSequence
                    Exception.bracket_
                        (replaceDurableResourceVersions [(encoded.durableResourceKey, publication.durablePublicationEventSequence)] publication.durablePublicationEventSequence)
                        (replaceDurableResourceVersions [] 0)
                        (currentDurableDependencyWatermark subscription `shouldReturn` publication.durablePublicationEventSequence)

            it "retains malformed hydrated resource-key authority while quarantining its payload" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.hydrate-malformed" (Set.singleton resource)
                    let Right encoded = encodeDurableResource resource
                    _ <- sqlExec
                        "UPDATE live_resource_versions SET resource_payload = '{\"version\":1,\"resource\":\"unknown\",\"fields\":{}}'::jsonb WHERE resource_key = ?"
                        (Only encoded.durableResourceKey)
                    databaseUrl <- getEnv "DATABASE_URL"
                    Exception.finally
                        (do
                            Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \connection -> do
                                (cursor, resources) <- hydrateDurableStateFromConnection connection
                                cursor `shouldBe` publication.durablePublicationEventSequence
                                resources `shouldBe` []
                            let subscription = SurfaceSubscription
                                    { subscriptionScope = AdminLive.adminVenueConfigLiveScope nil
                                    , subscriptionScopeKey = surfaceScopeKey (AdminLive.adminVenueConfigLiveScope nil)
                                    , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                                    , subscriptionRenderedDependencyWatermark = 0
                                    }
                            currentDurableDependencyWatermark subscription `shouldReturn` publication.durablePublicationEventSequence
                        )
                        (replaceDurableResourceVersions [] 0)

            it "dispatches valid resources when one persisted event child fails decoding" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.partial-decode" (Set.singleton resource)
                    _ <- sqlExec
                        "INSERT INTO live_invalidation_event_resources (event_id, resource_key, resource_payload) VALUES (?, 'invalid:{}', '{\"version\":1,\"resource\":\"unknown\",\"fields\":{}}'::jsonb)"
                        (Only publication.durablePublicationEventId)
                    databaseUrl <- getEnv "DATABASE_URL"
                    events <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close (\connection -> readDurableEventsAfter connection 0)
                    map (length . snd) events `shouldBe` [1]

            it "keeps an ordered cursor event when every resource child is malformed" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.malformed-only" (Set.singleton resource)
                    _ <- sqlExec
                        "UPDATE live_invalidation_event_resources SET resource_payload = '{\"version\":1,\"resource\":\"unknown\",\"fields\":{}}'::jsonb WHERE event_id = ?"
                        (Only publication.durablePublicationEventId)
                    databaseUrl <- getEnv "DATABASE_URL"
                    events <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close (\connection -> readDurableEventsAfter connection 0)
                    events `shouldBe` [(publication.durablePublicationEventSequence, [])]

            it "replays independently to two local listeners and ignores duplicate cursors after reconnect" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishTestDurableInvalidation "test.replay" (Set.singleton resource)
                    databaseUrl <- getEnv "DATABASE_URL"
                    firstEvents <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \first -> do
                        events <- readDurableEventsAfter first 0
                        readDurableEventsAfter first publication.durablePublicationEventSequence `shouldReturn` []
                        pure events
                    secondEvents <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close (\second -> readDurableEventsAfter second 0)
                    map fst firstEvents `shouldBe` [publication.durablePublicationEventSequence]
                    map fst secondEvents `shouldBe` [publication.durablePublicationEventSequence]
                    Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \reconnected ->
                        readDurableEventsAfter reconnected 0 `shouldReturn` firstEvents

            it "notifies listeners with only the committed event ID and stays silent on rollback" $ withContext do
                withCleanDb do
                    listener <- getEnv "DATABASE_URL" >>= PG.connectPostgreSQL . cs
                    Exception.bracket (pure listener) PG.close \connection -> do
                        _ <- PG.execute_ connection "LISTEN live_invalidation_events"
                        let resource = AdminResource.adminVenueSettingsResource nil
                        publication <- publishTestDurableInvalidation "test.notify" (Set.singleton resource)
                        notification <- timeout 1000000 (PGNotification.getNotification connection)
                        fmap (cs . PGNotification.notificationData) notification `shouldBe` Just (tshow publication.durablePublicationEventId)
                        _ <- Exception.try @Exception.SomeException $
                            withDurableLiveMutationWithoutContext (Text.replicate 121 "x") do
                                pure (liveMutationResult () [resource])
                        rolledBackNotification <- timeout 100000 (PGNotification.getNotification connection)
                        rolledBackNotification `shouldBe` Nothing

        describe "Durable live invalidation outbox pruning" do
            it "prunes only events before the retention boundary, cascades children, and retains version authority" $ withContext do
                withCleanDb do
                    let now = pruningTestNow
                    let retentionSeconds = 7 * 24 * 60 * 60
                    let cutoff = addUTCTime (negate (fromIntegral retentionSeconds)) now
                    let expiredResource = AdminResource.adminVenueSettingsResource nil
                    expired <- publishTestDurableInvalidation "test.prune.expired" (Set.singleton expiredResource)
                    boundary <- publishTestDurableInvalidation "test.prune.boundary" (Set.singleton SupportResource.supportAwardRatesResource)
                    fresh <- publishTestDurableInvalidation "test.prune.fresh" (Set.singleton SupportResource.supportPublicHolidaysResource)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?" (addUTCTime (-1) cutoff, expired.durablePublicationEventId)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?" (cutoff, boundary.durablePublicationEventId)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?" (addUTCTime 1 cutoff, fresh.durablePublicationEventId)

                    summary <- pruneExpiredLiveInvalidationOutboxAt now defaultLiveInvalidationOutboxPruneConfig { batchSize = 1 }

                    remainingSources :: [Only Text] <- sqlQuery "SELECT source FROM live_invalidation_events ORDER BY sequence_number" ()
                    remainingSources `shouldBe` [Only "test.prune.boundary", Only "test.prune.fresh"]
                    expiredChildCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources WHERE event_id = ?" (Only expired.durablePublicationEventId)
                    expiredVersionEventId :: UUID <- sqlQueryScalar "SELECT latest_event_id FROM live_resource_versions WHERE latest_event_sequence = ?" (Only expired.durablePublicationEventSequence)
                    expiredChildCount `shouldBe` 0
                    expiredVersionEventId `shouldBe` expired.durablePublicationEventId
                    summary.deletedEventCount `shouldBe` 1
                    summary.completedBatchCount `shouldBe` 1
                    summary.remainingExpiredEventCount `shouldBe` 0
                    summary.eventCount `shouldBe` 2
                    summary.eventResourceCount `shouldBe` 2
                    summary.resourceVersionCount `shouldBe` 3
                    summary.oldestEventCreatedAt `shouldSatisfy` maybe False (\observed -> abs (diffUTCTime observed cutoff) < 0.000001)
                    summary.eventTableSizeBytes `shouldSatisfy` (> 0)
                    summary.eventResourceTableSizeBytes `shouldSatisfy` (> 0)
                    summary.resourceVersionTableSizeBytes `shouldSatisfy` (> 0)

                    let scope = AdminLive.adminVenueConfigLiveScope nil
                    let subscription = SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                            , subscriptionRenderedDependencyWatermark = 0
                            }
                    databaseUrl <- getEnv "DATABASE_URL"
                    Exception.bracket_
                        (pure ())
                        (replaceDurableResourceVersions [] 0)
                        (Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \connection -> do
                            replaceDurableResourceVersions [] 0
                            (hydratedCursor, hydratedResources) <- hydrateDurableStateFromConnection connection
                            hydratedCursor `shouldBe` fresh.durablePublicationEventSequence
                            map (.durableResourceValue) hydratedResources `shouldContain` [expiredResource]
                            currentDurableDependencyWatermark subscription `shouldReturn` expired.durablePublicationEventSequence
                            currentDurableCursor `shouldReturn` fresh.durablePublicationEventSequence)
                    fetchDurableDependencyWatermark subscription `shouldReturn` expired.durablePublicationEventSequence

            it "deletes large expired sets through multiple bounded batches" $ withContext do
                withCleanDb do
                    let now = pruningTestNow
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publications <- forM [1 .. 5 :: Int] \index ->
                        publishTestDurableInvalidation ("test.prune.batch." <> tshow index) (Set.singleton resource)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ?" (Only (addUTCTime (negate (8 * 24 * 60 * 60)) now))

                    summary <- pruneExpiredLiveInvalidationOutboxAt now defaultLiveInvalidationOutboxPruneConfig { batchSize = 2 }

                    summary.deletedEventCount `shouldBe` length publications
                    summary.completedBatchCount `shouldBe` 3
                    summary.remainingExpiredEventCount `shouldBe` 0
                    summary.eventCount `shouldBe` 0
                    summary.eventResourceCount `shouldBe` 0
                    summary.resourceVersionCount `shouldBe` 1

            it "applies foreign-key repair SQL without losing version authority" $ withContext do
                withCleanDb do
                    publication <- publishTestDurableInvalidation "test.prune.migration" (Set.singleton (AdminResource.adminVenueSettingsResource nil))
                    databaseUrl <- getEnv "DATABASE_URL"
                    migrationSql <- ByteString.readFile "Application/Migration/1788001100.sql"
                    Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \connection -> do
                        _ <- PG.execute_ connection "ALTER TABLE live_resource_versions ADD CONSTRAINT live_resource_versions_latest_event_id_fkey FOREIGN KEY (latest_event_id) REFERENCES live_invalidation_events (id) ON DELETE RESTRICT"
                        _ <- PG.execute_ connection (Query migrationSql)
                        _ <- PG.execute connection "DELETE FROM live_invalidation_events WHERE id = ?" (Only publication.durablePublicationEventId)
                        pure ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions WHERE latest_event_id = ?" (Only publication.durablePublicationEventId)
                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE id = ?" (Only publication.durablePublicationEventId)
                    versionCount `shouldBe` 1
                    eventCount `shouldBe` 0

            it "retains exactly one PostgreSQL listener across repeated initializer cancellation" $ withContext do
                withCleanDb do
                    databaseUrl <- getEnv "DATABASE_URL"
                    replicateM_ 3 do
                        listener <- async (startDurableInvalidationListener (\_ _ -> pure ()))
                        waitForDurableListenerCount databaseUrl 1
                        cancel listener
                        _ <- waitCatch listener
                        waitForDurableListenerCount databaseUrl 0

            it "dispatches current authority after reconnect when missed events were pruned" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    initial <- publishTestDurableInvalidation "test.prune.reconnect.initial" (Set.singleton resource)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?" (pruningTestNow, initial.durablePublicationEventId)
                    databaseUrl <- getEnv "DATABASE_URL"
                    Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close hydrateDurableStateFromConnection
                    let scope = AdminLive.adminVenueConfigLiveScope nil
                    let subscription = SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                            , subscriptionRenderedDependencyWatermark = initial.durablePublicationEventSequence
                            }
                    bus <- newInMemoryLiveBus
                    registerSurfaceSubscriptionWithBus bus nil subscription (error "closed test websocket")
                    firstDispatches <- newChan
                    let firstDispatch eventSequence _resources =
                            writeChan firstDispatches eventSequence

                    withAsync (runDurableInvalidationListenerConnection databaseUrl firstDispatch) \_ -> do
                        timeout 2000000 (readChan firstDispatches) `shouldReturn` Just initial.durablePublicationEventSequence

                    missed <- publishTestDurableInvalidation "test.prune.reconnect.missed" (Set.singleton resource)
                    sqlExec "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?" (addUTCTime (negate (8 * 24 * 60 * 60)) pruningTestNow, missed.durablePublicationEventId)
                    _ <- pruneExpiredLiveInvalidationOutboxAt pruningTestNow defaultLiveInvalidationOutboxPruneConfig

                    recoveredDispatches <- newChan
                    let recoveredDispatch eventSequence resources = do
                            dispatchDurableInvalidationWithBus (Just bus) eventSequence resources
                            writeChan recoveredDispatches eventSequence
                    withAsync (runDurableInvalidationListenerConnection databaseUrl recoveredDispatch) \_ -> do
                        timeout 2000000 (readChan recoveredDispatches) `shouldReturn` Just missed.durablePublicationEventSequence
                        currentLiveUpdateVersionWithBus bus scope `shouldReturn` missed.durablePublicationEventSequence
                        fetchDurableDependencyWatermark subscription `shouldReturn` missed.durablePublicationEventSequence

            it "dispatches hydrated authority before retained replay after partial pruning" $ withContext do
                withCleanDb do
                    _baseline <- publishTestDurableInvalidation "test.reconnect-order.baseline" (Set.singleton (AdminResource.adminVenueSettingsResource nil))
                    databaseUrl <- getEnv "DATABASE_URL"
                    Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close hydrateDurableStateFromConnection
                    expired <- publishTestDurableInvalidation "test.reconnect-order.expired" (Set.singleton SupportResource.supportAwardRatesResource)
                    fresh <- publishTestDurableInvalidation "test.reconnect-order.fresh" (Set.singleton SupportResource.supportPublicHolidaysResource)
                    sqlExec
                        "UPDATE live_invalidation_events SET created_at = ? WHERE id = ?"
                        (addUTCTime (negate (8 * 24 * 60 * 60)) pruningTestNow, expired.durablePublicationEventId)
                    _ <- pruneExpiredLiveInvalidationOutboxAt pruningTestNow defaultLiveInvalidationOutboxPruneConfig
                    dispatches <- newChan
                    let capture eventSequence resources = writeChan dispatches (eventSequence, map (.durableResourceValue) resources)
                    Exception.finally
                        (withAsync (runDurableInvalidationListenerConnection databaseUrl capture) \_ -> do
                            firstDispatch <- timeout 2000000 (readChan dispatches)
                            fmap fst firstDispatch `shouldBe` Just fresh.durablePublicationEventSequence
                            fmap snd firstDispatch `shouldSatisfy` maybe False (\resources ->
                                SupportResource.supportAwardRatesResource `elem` resources
                                    && SupportResource.supportPublicHolidaysResource `elem` resources)
                        )
                        (replaceDurableResourceVersions [] 0)

            it "rejects retention below seven days and batches above 1000" $ withContext do
                withCleanDb do
                    let unsafeRetention = defaultLiveInvalidationOutboxPruneConfig { retentionSeconds = 6 * 24 * 60 * 60 }
                    let unsafeBatch = defaultLiveInvalidationOutboxPruneConfig { batchSize = 1001 }
                    pruneExpiredLiveInvalidationOutboxAt pruningTestNow unsafeRetention `shouldThrow` anyException
                    pruneExpiredLiveInvalidationOutboxAt pruningTestNow unsafeBatch `shouldThrow` anyException

waitForDurableListenerCount :: String -> Int -> IO ()
waitForDurableListenerCount databaseUrl expected = go (40 :: Int)
  where
    go remaining = do
        actual <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \connection -> do
            [Only count] <- PG.query connection "SELECT COUNT(*)::INT FROM pg_stat_activity WHERE application_name = 'bepis-live-invalidation-listener'" ()
            pure count
        if actual == expected
            then pure ()
            else if remaining <= 0
                then expectationFailure (cs ("expected durable listener connection count " <> tshow expected <> ", got " <> tshow actual))
                else threadDelay 50000 >> go (remaining - 1)

pruningTestNow :: UTCTime
pruningTestNow = UTCTime (fromGregorian 2026 8 18) 0
