module Test.WageSourceAlertSpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.EmailDelivery
import Application.WageSourceAlert.Job
import Application.WageSourceAlert.Types
import Application.WageSourcePolicy (dataVicMaximumAge, fwcMaximumAge)
import Config
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import Data.IORef
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.EmailDelivery
import Test.Support.Environment (withEnvironmentVariable)


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Wage-source health alerts" do
        it "rejects a health-check payload bound to the wrong source job kind" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                sourceJob <- newRecord @AppJob |> set #jobKind "unrelated_job" |> createRecord
                healthCheck <-
                    newRecord @AppJob
                        |> set #jobKind wageSourceHealthCheckJobKind
                        |> set #payloadSchemaVersion 1
                        |> set #payload (Aeson.object ["source" Aeson..= ("fwc_mapd" :: Text), "trigger" Aeson..= ("scheduled_freshness_check" :: Text), "sourceJobId" Aeson..= unpackId sourceJob.id, "enqueuedAt" Aeson..= now, "anchorSuccessAt" Aeson..= (Nothing :: Maybe UTCTime)])
                        |> set #relatedTable (Just "app_jobs")
                        |> set #relatedId (Just (unpackId sourceJob.id))
                        |> createRecord

                result <- Exception.try (performWageSourceHealthCheckJobAt now healthCheck) :: IO (Either Exception.SomeException ())
                case result of
                    Right () -> expectationFailure "Expected invalid wage-source health-check provenance"
                    Left exception -> tshow exception `shouldBe` "application.async.error.app-job/job-invalid-provenance: The stored job provenance is invalid."

        it "waits for the final refresh attempt and records manual/timer class without raw errors" $ withContext do
            withCleanDb do
                manualUser <- createUserRecord "source-manual@example.com" "staff" True
                sourceJob <-
                    createSourceJob "fwc_mapd_refresh" (Just (unpackId manualUser.id))
                        >>= updateRecord . set #attemptsCount (appJobMaxAttempts - 1)

                handleWageSourceRefreshFailureAfterFinalAttempt sourceJob `shouldReturn` []
                query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetchCount >>= (`shouldBe` 0)

                finalJob <- sourceJob |> set #attemptsCount appJobMaxAttempts |> updateRecord
                [_] <- handleWageSourceRefreshFailureAfterFinalAttempt finalJob
                [healthCheck] <- query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetch
                snapshots <- resultAlerts healthCheck
                map (.alertKind) snapshots `shouldMatchList` [RefreshFailedAlert, SourceMissingAlert]
                (find ((== RefreshFailedAlert) . (.alertKind)) snapshots >>= (.refreshTriggerClass))
                    `shouldBe` Just ManualRefresh
                tshow healthCheck.result `shouldSatisfy` not . contains "raw failure"

        it "dispatches final failures once per active super admin and excludes inactive accounts" $ withContext do
            withCleanDb do
                firstActive <- createUserRecordWithPlatformRole "source-active-one@example.com" "staff" (Just SuperAdmin) True
                secondActive <- createUserRecordWithPlatformRole "source-active-two@example.com" "staff" (Just SuperAdmin) True
                inactive <- createUserRecordWithPlatformRole "source-inactive@example.com" "staff" (Just SuperAdmin) True
                ordinary <- createUserRecord "source-ordinary@example.com" "staff" True
                now <- getCurrentTime
                _ <- inactive |> set #deactivatedAt (Just now) |> updateRecord
                sourceJob <- createSourceJob "fwc_mapd_refresh" Nothing >>= updateRecord . set #attemptsCount appJobMaxAttempts

                dispatchResult <- withEnvironmentVariable "FWC_MAPD_KEY" Nothing $
                    withFrameworkConfig config \frameworkConfig -> do
                        let ?context = frameworkConfig
                        Exception.try (dispatchAppJob sourceJob) :: IO (Either Exception.SomeException ())

                dispatchResult `shouldSatisfy` isLeft
                emailJobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                mapMaybe payloadRecipientAccountId emailJobs
                    `shouldMatchList`
                        [ unpackId firstActive.id
                        , unpackId firstActive.id
                        , unpackId secondActive.id
                        , unpackId secondActive.id
                        ]
                mapMaybe payloadRecipientAccountId emailJobs
                    `shouldSatisfy` all (`notElem` [unpackId inactive.id, unpackId ordinary.id])

        it "suppresses refresh alerts when a later publication step fails after persisted refresh success" $ withContext do
            withCleanDb do
                sourceJob <-
                    createSourceJob "fwc_mapd_refresh" Nothing
                        >>= updateRecord . set #attemptsCount appJobMaxAttempts . set #status JobStatusSucceeded

                handleWageSourceRefreshFailureAfterFinalAttempt sourceJob `shouldReturn` []
                query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetchCount >>= (`shouldBe` 0)

        it "permanently deduplicates repeated final failures against the same latest-valid basis" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "source-admin@example.com" "staff" (Just SuperAdmin) True
                firstSource <- createSourceJob "fwc_mapd_refresh" Nothing >>= updateRecord . set #attemptsCount appJobMaxAttempts
                secondSource <- createSourceJob "fwc_mapd_refresh" Nothing >>= updateRecord . set #attemptsCount appJobMaxAttempts

                _ <- handleWageSourceRefreshFailureAfterFinalAttempt firstSource
                _ <- handleWageSourceRefreshFailureAfterFinalAttempt secondSource

                firstCheck <- query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> orderByAsc #createdAt |> fetchOne
                firstSnapshots <- resultAlerts firstCheck
                (find ((== RefreshFailedAlert) . (.alertKind)) firstSnapshots >>= (.refreshTriggerClass))
                    `shouldBe` Just TimerRefresh
                emailJobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                length emailJobs `shouldBe` 2
                healthChecks <- query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetch
                length healthChecks `shouldBe` 2

        it "aggregates previous, current, and next DataVic missing years while keeping failure separate" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 8 20) 0
                sourceJob <- createSourceJob "public_holiday_refresh" Nothing
                healthCheck <- createHealthCheck DataVicWageSource FinalRefreshFailure sourceJob now Nothing

                performWageSourceHealthCheckJobAt now healthCheck

                completed <- fetch healthCheck.id
                snapshots <- resultAlerts completed
                map (.alertKind) snapshots `shouldMatchList` [RefreshFailedAlert, SourceMissingAlert]
                let Just missing = find ((== SourceMissingAlert) . (.alertKind)) snapshots
                missing.affectedYears `shouldBe` [2025, 2026, 2027]

        it "aggregates stale DataVic years into one alert" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 8 20) 0
                let staleAt = addUTCTime (negate (dataVicMaximumAge + 1)) now
                forM_ [2025, 2026, 2027] \year -> createStatewideHoliday year staleAt
                sourceJob <- createSourceJob "public_holiday_refresh" Nothing
                healthCheck <- createHealthCheck DataVicWageSource ScheduledFreshnessCheck sourceJob staleAt (Just staleAt)

                performWageSourceHealthCheckJobAt now healthCheck

                completed <- fetch healthCheck.id
                [snapshot] <- resultAlerts completed
                snapshot.alertKind `shouldBe` SourceStaleAlert
                snapshot.affectedYears `shouldBe` [2025, 2026, 2027]

        it "marks a delayed check superseded when every required year has newer authoritative data" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 8 20) 0
                let anchor = addUTCTime (negate (dataVicMaximumAge + 10)) now
                forM_ [2025, 2026, 2027] \year -> createStatewideHoliday year (addUTCTime 60 anchor)
                sourceJob <- createSourceJob "public_holiday_refresh" Nothing
                healthCheck <- createHealthCheck DataVicWageSource ScheduledFreshnessCheck sourceJob anchor (Just anchor)

                performWageSourceHealthCheckJobAt now healthCheck

                completed <- fetch healthCheck.id
                resultText "evaluationStatus" completed `shouldBe` Just "superseded"
                resultAlerts completed `shouldReturn` []

        it "uses the earliest active venue calendar for the annual FWC incident" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 7 7) 0
                let latestSuccess = UTCTime (fromGregorian 2026 6 30) 0
                mondayVenue <- createVenueWithConfig "Monday venue"
                wednesdayVenue <- createVenueWithConfig "Wednesday venue"
                setVenueWeekStart mondayVenue 1
                setVenueWeekStart wednesdayVenue 3
                createFwcSuccess latestSuccess
                sourceJob <- createSourceJob "fwc_mapd_refresh" Nothing
                healthCheck <- createHealthCheck FwcWageSource ScheduledFreshnessCheck sourceJob latestSuccess (Just latestSuccess)

                performWageSourceHealthCheckJobAt now healthCheck

                completed <- fetch healthCheck.id
                snapshots <- resultAlerts completed
                let Just annual = find ((== FwcAnnualRefreshMissingAlert) . (.alertKind)) snapshots
                annual.annualRequiredOnOrAfter `shouldBe` Just (fromGregorian 2026 7 1)
                annual.annualTriggerVenueId `shouldBe` Just (unpackId wednesdayVenue.id)

        it "defers only annual-calendar evaluation when there is no active venue" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 7 7) 0
                let freshAt = addUTCTime (negate (fwcMaximumAge - 60)) now
                createFwcSuccess freshAt
                sourceJob <- createSourceJob "fwc_mapd_refresh" Nothing
                healthCheck <- createHealthCheck FwcWageSource ScheduledFreshnessCheck sourceJob freshAt (Just freshAt)

                performWageSourceHealthCheckJobAt now healthCheck

                completed <- fetch healthCheck.id
                resultText "annualEvaluation" completed `shouldBe` Just "deferred_no_active_venue"
                resultAlerts completed `shouldReturn` []

        it "keeps a queued alert deliverable after source recovery and succeeds with zero current recipients" $ withContext do
            withCleanDb do
                let now = UTCTime (fromGregorian 2026 8 20) 0
                recipient <- createUserRecordWithPlatformRole "source-recovery@example.com" "staff" (Just SuperAdmin) True
                sourceJob <- createSourceJob "fwc_mapd_refresh" Nothing
                healthCheck <- createHealthCheck FwcWageSource FinalRefreshFailure sourceJob now Nothing
                performWageSourceHealthCheckJobAt now healthCheck
                emailJobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                let Just missingEmail = find ((== Just (alertMailKind FwcWageSource SourceMissingAlert)) . payloadMailKind) emailJobs
                createFwcSuccess now
                _ <- recipient |> set #deactivatedAt (Just now) |> set #platformRole Nothing |> updateRecord
                calls <- newIORef (0 :: Int)

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        (capturingEmailDeliveryRuntime (\_ -> modifyIORef' calls (+ 1)))
                        missingEmail

                readIORef calls `shouldReturn` 1
                delivered <- fetch missingEmail.id
                resultText "deliveryStatus" delivered `shouldBe` Just "sent"

                withCleanDb do
                    zeroRecipientSource <- createSourceJob "fwc_mapd_refresh" Nothing
                    zeroRecipientCheck <- createHealthCheck FwcWageSource FinalRefreshFailure zeroRecipientSource now Nothing
                    performWageSourceHealthCheckJobAt now zeroRecipientCheck
                    completed <- fetch zeroRecipientCheck.id
                    resultInt "recipientCount" completed `shouldBe` Just 0
                    query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 0)

createSourceJob :: (?modelContext :: ModelContext) => Text -> Maybe UUID -> IO AppJob
createSourceJob kind requestedByUserId =
    newRecord @AppJob
        |> set #jobKind kind
        |> set #requestedByUserId requestedByUserId
        |> createRecord

createHealthCheck ::
    (?modelContext :: ModelContext) =>
    WageSourceKind ->
    RefreshTrigger ->
    AppJob ->
    UTCTime ->
    Maybe UTCTime ->
    IO AppJob
createHealthCheck source trigger sourceJob enqueuedAt anchorSuccessAt =
    newRecord @AppJob
        |> set #jobKind wageSourceHealthCheckJobKind
        |> set #payloadSchemaVersion 1
        |> set #relatedTable (Just "app_jobs")
        |> set #relatedId (Just (unpackId sourceJob.id))
        |> set #payload
            ( Aeson.object
                [ "source" Aeson..= wageSourceText source
                , "trigger" Aeson..= refreshTriggerText trigger
                , "sourceJobId" Aeson..= unpackId sourceJob.id
                , "enqueuedAt" Aeson..= enqueuedAt
                , "anchorSuccessAt" Aeson..= anchorSuccessAt
                ]
            )
        |> createRecord

createFwcSuccess :: (?modelContext :: ModelContext) => UTCTime -> IO ()
createFwcSuccess completedAt =
    void $
        newRecord @FwcMapdSyncRun
            |> set #status "succeeded"
            |> set #requestedAwardFixedIds [9]
            |> set #syncedAwardFixedIds [9]
            |> set #startedAt completedAt
            |> set #finishedAt (Just completedAt)
            |> createRecord

createStatewideHoliday :: (?modelContext :: ModelContext) => Integer -> UTCTime -> IO ()
createStatewideHoliday year importedAt =
    void $
        newRecord @PublicHoliday
            |> set #jurisdiction "VIC"
            |> set #holidayDate (fromGregorian year 1 1)
            |> set #name "Statewide holiday"
            |> set #isRegional False
            |> set #importedAt (Just importedAt)
            |> createRecord

setVenueWeekStart :: (?modelContext :: ModelContext) => Venue -> Int -> IO ()
setVenueWeekStart venue weekday = do
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    void (venueConfig |> set #rosterWeekStartsOn weekday |> updateRecord)

resultAlerts :: AppJob -> IO [WageSourceAlertSnapshot]
resultAlerts appJob =
    case AesonTypes.parseEither (Aeson.withObject "health result" (\object -> object Aeson..:? "alerts" Aeson..!= [])) appJob.result of
        Left err     -> expectationFailure err >> pure []
        Right alerts -> pure alerts

resultText :: Text -> AppJob -> Maybe Text
resultText key appJob =
    AesonTypes.parseMaybe (Aeson.withObject "job result" (Aeson..: AesonKey.fromText key)) appJob.result

resultInt :: Text -> AppJob -> Maybe Int
resultInt key appJob =
    AesonTypes.parseMaybe (Aeson.withObject "job result" (Aeson..: AesonKey.fromText key)) appJob.result

payloadMailKind :: AppJob -> Maybe Text
payloadMailKind appJob =
    AesonTypes.parseMaybe (Aeson.withObject "email payload" (Aeson..: "mailKind")) appJob.payload

payloadRecipientAccountId :: AppJob -> Maybe UUID
payloadRecipientAccountId appJob =
    AesonTypes.parseMaybe (Aeson.withObject "email payload" (Aeson..: "recipientAccountId")) appJob.payload

contains :: Text -> Text -> Bool
contains = Text.isInfixOf
