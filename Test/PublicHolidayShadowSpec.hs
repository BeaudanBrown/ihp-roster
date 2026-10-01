module Test.PublicHolidayShadowSpec where

import Application.Async.Queue
import Application.Async.Registry (dispatchAppJob)
import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.LiveUpdate.DurableCodec (decodeDurableResource,
                                                   encodeDurableResource)
import Application.PublicHolidays.Client
import Application.PublicHolidays.Job (publicHolidayRefreshJobKind)
import qualified Application.PublicHolidays.Policy as Policy
import Application.PublicHolidays.Shadow
import Application.WageSourceAlert.Job (wageSourceHealthCheckJobKind)
import Config (config)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.IORef
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Test.Mocking
import Test.Hspec
import qualified Test.PublicHolidayOverrideSpec as Override
import Test.Support
import Web.FrontController ()

-- Protected dates and imported timestamps must survive success and every error.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "DataVic shadow persistence" do
        it "succeeds with informational differences without holiday, override or freshness writes" $ withContext do
            withCleanDb do
                mapM_ createRecord Override.calendar
                _ <- createRecord Override.overrideFixture
                before <- query @PublicHoliday |> orderByAsc #id |> fetch
                overrides <- query @PublicHolidayOverride |> fetch
                legacy <- newRecord @AppJob |> set #jobKind publicHolidayRefreshJobKind |> set #status JobStatusSucceeded |> createRecord
                EnqueuedAppJob job <- enqueuePublicHolidayShadowJob Nothing
                performPublicHolidayShadowJobWith (\years -> pure (Right [(year, [candidate year]) | year <- years])) job
                query @PublicHoliday |> orderByAsc #id |> fetch >>= (`shouldBe` before)
                query @PublicHolidayOverride |> fetch >>= (`shouldBe` overrides)
                fetch legacy.id >>= (`shouldBe` legacy)
                query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetchCount >>= (`shouldBe` 0)
                completed <- fetch job.id
                completed.status `shouldBe` JobStatusSucceeded
                case Aeson.fromJSON @ShadowResult completed.result of
                    Aeson.Error err -> expectationFailure err
                    Aeson.Success result -> do
                        result.failure `shouldBe` Nothing
                        result.targetYears `shouldBe` Policy.targetPublicHolidayYears (utctDay result.attemptedAt)
                        length result.years `shouldBe` 3
                        map (.fetchedCount) result.years `shouldBe` [1,1,1]
                        map (.providerOnlyCount) result.years `shouldBe` [1,1,1]
                [event] <- query @LiveInvalidationEvent |> filterWhere (#source, "support.public_holidays.shadow" :: Text) |> fetch
                resources <- query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId event.id) |> fetch
                map (\resource -> decodeDurableResource resource.resourceKey resource.resourcePayload) resources
                    `shouldBe` [encodeDurableResource supportPublicHolidaysResource]

        it "persists safe failure evidence, preserves the cache and leaves retries to IHP" $ withContext do
            withCleanDb do
                mapM_ createRecord Override.calendar
                _ <- createRecord Override.overrideFixture
                before <- query @PublicHoliday |> orderByAsc #id |> fetch
                overrides <- query @PublicHolidayOverride |> fetch
                forM_ [DataVicMissingKey, DataVicHttpStatus 401, DataVicHttpStatus 429, DataVicTransportUnavailable, DataVicMalformedResponse] \err -> do
                    job <- newShadowJob
                    result <- Exception.try @Exception.SomeException (performPublicHolidayShadowJobWith (\_ -> pure (Left err)) job)
                    result `shouldSatisfy` isLeft
                    after <- fetch job.id
                    after.status `shouldBe` job.status
                    after.attemptsCount `shouldBe` job.attemptsCount
                    case Aeson.fromJSON @ShadowResult after.result of
                        Aeson.Error message -> expectationFailure message
                        Aeson.Success summary -> do
                            summary.failure `shouldSatisfy` isJust
                            summary.years `shouldBe` []
                query @PublicHoliday |> orderByAsc #id |> fetch >>= (`shouldBe` before)
                query @PublicHolidayOverride |> fetch >>= (`shouldBe` overrides)
                query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetchCount >>= (`shouldBe` 0)

        it "discards unexpected exception details before persisting or throwing" $ withContext do
            withCleanDb do
                job <- newShadowJob
                result <- Exception.try @Exception.SomeException (performPublicHolidayShadowJobWith (\_ -> Exception.throwIO (userError "secret-request-key")) job)
                case result of
                    Right () -> expectationFailure "Expected safe failure"
                    Left err -> tshow err `shouldBe` "application.async.error.app-job/job-unexpected-synchronous-failure: The job could not be completed."
                after <- fetch job.id
                case Aeson.fromJSON @ShadowResult after.result of
                    Aeson.Success summary -> summary.failure `shouldBe` Just "JobUnexpectedSynchronousFailure"
                    Aeson.Error err -> expectationFailure err

        it "rejects invalid persisted provenance before any HTTP request" $ withContext do
            withCleanDb do
                base <- newShadowJob
                let cases = [base |> set #payloadSchemaVersion 99, base |> set #relatedTable Nothing,
                        base |> set #payload (Aeson.object ["jurisdiction" Aeson..= ("NSW" :: Text)]),
                        base |> set #payload Aeson.Null, base |> set #jobKind "other"]
                called <- newIORef False
                forM_ cases \job -> do
                    result <- Exception.try @Exception.SomeException (performPublicHolidayShadowJobWith (\_ -> writeIORef called True >> pure (Left DataVicMissingKey)) job)
                    result `shouldSatisfy` isLeft
                readIORef called `shouldReturn` False

        it "deduplicates shadow runs independently of legacy jobs" $ withContext do
            withCleanDb do
                EnqueuedAppJob first <- enqueuePublicHolidayShadowJob Nothing
                ExistingActiveAppJob second <- enqueuePublicHolidayShadowJob Nothing
                first.id `shouldBe` second.id
                first.jobKind `shouldBe` publicHolidayShadowJobKind

        it "blocks already queued anonymous jobs at worker dispatch without touching dates or freshness" $ withContext do
            withCleanDb do
                mapM_ createRecord Override.calendar
                before <- query @PublicHoliday |> orderByAsc #id |> fetch
                job <- newRecord @AppJob |> set #jobKind publicHolidayRefreshJobKind |> createRecord
                result <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    Exception.try @Exception.SomeException (dispatchAppJob job)
                result `shouldSatisfy` isLeft
                query @PublicHoliday |> orderByAsc #id |> fetch >>= (`shouldBe` before)
                query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetchCount >>= (`shouldBe` 0)

candidate :: Integer -> DataVicDate
candidate year = DataVicDate (fromGregorian year 3 28) "Provider holiday" Nothing Nothing "https://example.invalid/public-calendar"

newShadowJob :: (?modelContext :: ModelContext) => IO AppJob
newShadowJob = newRecord @AppJob
    |> set #jobKind publicHolidayShadowJobKind
    |> set #relatedTable (Just "public_holidays")
    |> set #payload (Aeson.object ["jurisdiction" Aeson..= ("VIC" :: Text)])
    |> createRecord
