{-# LANGUAGE TypeApplications #-}

module Test.DurableLiveInvalidationSpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Resource as AdminResource
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..), publishDurableInvalidation)
import Control.Concurrent.Async (concurrently)
import qualified Control.Exception as Exception
import qualified Data.Set as Set
import Data.UUID (UUID, nil)
import qualified Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple (Only (..))
import qualified Database.PostgreSQL.Simple.Notification as PGNotification
import IHP.ModelSupport (sqlQueryScalar, withTransaction)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import System.Environment (getEnv)
import System.Timeout (timeout)
import Test.Hspec
import Test.Support

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
                    eventCount `shouldBe` 0
                    resourceCount `shouldBe` 0
                    versionCount `shouldBe` 0
