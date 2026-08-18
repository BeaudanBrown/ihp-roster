{-# LANGUAGE TypeApplications #-}

module Test.DurableLiveInvalidationSpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import qualified Application.Helper.FrontendContract.Surface.Admin.Resource as AdminResource
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   encodeDurableResource)
import Application.Helper.LiveUpdate.DurableListener (readDurableEventsAfter)
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..),
                                                       publishDurableInvalidation)
import Application.Helper.LiveUpdate.DurableState (currentDurableDependencyWatermark,
                                                   fetchDurableDependencyWatermark,
                                                   replaceDurableResourceVersions)
import Application.Helper.LiveUpdate.Runtime (SurfaceSubscription (..),
                                              currentLiveUpdateVersionWithBus,
                                              newInMemoryLiveBus,
                                              registerSurfaceSubscriptionWithBus,
                                              surfaceScopeKey)
import Control.Concurrent.Async (concurrently)
import qualified Control.Exception as Exception
import qualified Data.Set as Set
import Data.UUID (UUID, nil)
import Database.PostgreSQL.Simple (Only (..))
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Notification as PGNotification
import IHP.ModelSupport (sqlExec, sqlQueryScalar, withTransaction)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import System.Environment (getEnv)
import System.Timeout (timeout)
import Test.Hspec
import Test.Support
import Web.SurfaceInvalidation (dispatchDurableInvalidationWithBus)

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
        describe "Durable live invalidation publication" do
            it "persists one event resource and current version for duplicate resources" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishDurableInvalidation "test.live" (Set.fromList [resource, resource])
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
                        (publishDurableInvalidation "test.concurrent.left" (Set.singleton resource))
                        (publishDurableInvalidation "test.concurrent.right" (Set.singleton resource))

                    latestSequence :: Int <- sqlQueryScalar "SELECT latest_event_sequence FROM live_resource_versions" ()
                    greatestEventSequence :: Int <- sqlQueryScalar "SELECT MAX(sequence_number) FROM live_invalidation_events" ()
                    latestSequence `shouldBe` greatestEventSequence

            it "delivers one committed event independently through two process-local hubs" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishDurableInvalidation "test.two-hubs" (Set.singleton resource)
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
                    publication <- publishDurableInvalidation "test.watermark" (Set.singleton resource)
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

            it "dispatches valid resources when one persisted event child fails decoding" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishDurableInvalidation "test.partial-decode" (Set.singleton resource)
                    _ <- sqlExec
                        "INSERT INTO live_invalidation_event_resources (event_id, resource_key, resource_payload) VALUES (?, 'invalid:{}', '{\"version\":1,\"resource\":\"unknown\",\"fields\":{}}'::jsonb)"
                        (Only publication.durablePublicationEventId)
                    databaseUrl <- getEnv "DATABASE_URL"
                    events <- Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close (\connection -> readDurableEventsAfter connection 0)
                    map (length . snd) events `shouldBe` [1]

            it "replays independently to two local listeners and ignores duplicate cursors after reconnect" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    publication <- publishDurableInvalidation "test.replay" (Set.singleton resource)
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
                        publication <- publishDurableInvalidation "test.notify" (Set.singleton resource)
                        notification <- timeout 1000000 (PGNotification.getNotification connection)
                        fmap (cs . PGNotification.notificationData) notification `shouldBe` Just (tshow publication.durablePublicationEventId)
                        _ <- Exception.try @Exception.SomeException (withTransaction do
                            _ <- publishDurableInvalidation "test.notify.rollback" (Set.singleton resource)
                            Exception.throwIO (userError "force rollback"))
                        rolledBackNotification <- timeout 100000 (PGNotification.getNotification connection)
                        rolledBackNotification `shouldBe` Nothing

            it "rolls back the event and resource version when its enclosing transaction fails" $ withContext do
                withCleanDb do
                    let resource = AdminResource.adminVenueSettingsResource nil
                    _ <- Exception.try @Exception.SomeException (withTransaction do
                        _ <- publishDurableInvalidation "test.rollback" (Set.singleton resource)
                        Exception.throwIO (userError "force rollback"))

                    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
                    resourceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources" ()
                    versionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
                    let scope = AdminLive.adminVenueConfigLiveScope nil
                    let subscription = SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = [AdminLive.adminVenueSettingsLiveFragment]
                            , subscriptionRenderedDependencyWatermark = 0
                            }
                    eventCount `shouldBe` 0
                    resourceCount `shouldBe` 0
                    versionCount `shouldBe` 0
                    currentDurableDependencyWatermark subscription `shouldReturn` 0
