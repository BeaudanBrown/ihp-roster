module Test.XeroKeepaliveSpec where

import Application.Async.Queue
import Application.Helper.Xero
import Application.Xero.Keepalive
import Application.Xero.ReferenceSyncJob
import Config
import qualified Data.Aeson as Aeson
import qualified Data.IORef as IORef
import Data.Time.Clock (NominalDiffTime, addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Xero keepalive jobs" do
        it "independently enqueues six-day reference sync and seven-day token keepalive work" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                bothVenue <- createVenueWithConfig "Xero Both Maintenance Venue"
                referenceVenue <- createVenueWithConfig "Xero Reference Maintenance Venue"
                keepaliveVenue <- createVenueWithConfig "Xero Token Maintenance Venue"
                freshVenue <- createVenueWithConfig "Xero Fresh Maintenance Venue"
                inactiveVenue <- createVenueWithConfig "Xero Inactive Maintenance Venue"
                owner <- createUserRecord "xero-maintenance-owner@example.com" "staff" True
                bothConnection <- createKeepaliveXeroConnection bothVenue owner (Just (negate (8 * oneDay))) "tenant-both" "active" >>= setLastSyncAge now (Just (negate (7 * oneDay)))
                _referenceConnection <- createKeepaliveXeroConnection referenceVenue owner (Just (negate oneDay)) "tenant-reference" "active" >>= setLastSyncAge now (Just (negate (7 * oneDay)))
                _keepaliveConnection <- createKeepaliveXeroConnection keepaliveVenue owner (Just (negate (8 * oneDay))) "tenant-keepalive" "active" >>= setLastSyncAge now (Just (negate oneDay))
                _freshConnection <- createKeepaliveXeroConnection freshVenue owner (Just (negate oneDay)) "tenant-fresh" "active" >>= setLastSyncAge now (Just (negate oneDay))
                _inactiveConnection <- createKeepaliveXeroConnection inactiveVenue owner (Just (negate (8 * oneDay))) "tenant-inactive" "reauthorization_required" >>= setLastSyncAge now Nothing

                firstSummary <- enqueueDueXeroMaintenanceJobsAt now
                firstSummary.dueConnectionCount `shouldBe` 2
                firstSummary.enqueuedJobCount `shouldBe` 2
                firstSummary.existingJobCount `shouldBe` 0
                firstSummary.referenceSyncDueConnectionCount `shouldBe` 2
                firstSummary.referenceSyncEnqueuedJobCount `shouldBe` 2
                firstSummary.referenceSyncExistingJobCount `shouldBe` 0

                secondSummary <- enqueueDueXeroMaintenanceJobsAt now
                secondSummary.enqueuedJobCount `shouldBe` 0
                secondSummary.existingJobCount `shouldBe` 2
                secondSummary.referenceSyncEnqueuedJobCount `shouldBe` 0
                secondSummary.referenceSyncExistingJobCount `shouldBe` 2

                keepaliveJobs <- query @AppJob |> filterWhere (#jobKind, xeroConnectionKeepaliveJobKind) |> fetch
                referenceJobs <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                length keepaliveJobs `shouldBe` 2
                length referenceJobs `shouldBe` 2
                keepaliveJobs `shouldSatisfy` any (\job -> job.relatedId == Just (unpackId bothConnection.id) && job.dedupeKey == Just (xeroConnectionKeepaliveDedupeKey bothConnection))
                referenceJobs `shouldSatisfy` any (\job -> job.relatedId == Just (unpackId bothConnection.id) && job.dedupeKey == Just (xeroReferenceSyncDedupeKey bothConnection))

        it "serializes token keepalive behind the shared tenant lease" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Shared Lease Venue"
                owner <- createUserRecord "xero-shared-lease-owner@example.com" "staff" True
                connection <- createKeepaliveXeroConnection venue owner (Just (negate (8 * oneDay))) "tenant-shared-lease" "active"
                EnqueuedAppJob keepaliveJob <- enqueueAppJob (keepaliveJobRequest connection)
                EnqueuedAppJob referenceJob <- enqueueXeroReferenceSyncJob Nothing connection
                now <- getCurrentTime
                acquireXeroReferenceSyncLease now referenceJob connection.tenantId `shouldReturn` True
                refreshCalls <- IORef.newIORef (0 :: Int)
                let tokenResponse = XeroTokenResponse "lease-access-token" "lease-refresh-token" 1800 (Just requiredXeroScopesText)
                    client =
                        (keepaliveXeroClient (Right tokenResponse))
                            { refreshXeroToken = \_ _ -> do
                                IORef.modifyIORef' refreshCalls (+ 1)
                                pure (Right tokenResponse)
                            }

                withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        performXeroConnectionKeepaliveJob keepaliveJob `shouldThrow` anyException
                IORef.readIORef refreshCalls `shouldReturn` 0

                releaseXeroReferenceSyncLease referenceJob connection.tenantId
                withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        performXeroConnectionKeepaliveJob keepaliveJob
                IORef.readIORef refreshCalls `shouldReturn` 1
                updatedJob <- fetch keepaliveJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "refreshes and stores rotated Xero tokens from a keepalive job" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Keepalive Refresh Venue"
                owner <- createUserRecord "xero-keepalive-refresh-owner@example.com" "staff" True
                connection <- createKeepaliveXeroConnection venue owner (Just (negate (8 * oneDay))) "tenant-refresh" "active"
                EnqueuedAppJob job <- enqueueAppJob (keepaliveJobRequest connection)
                let tokenResponse = XeroTokenResponse "keepalive-access-token" "keepalive-refresh-token" 1800 (Just requiredXeroScopesText)

                withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (keepaliveXeroClient (Right tokenResponse)) do
                        performXeroConnectionKeepaliveJob job

                updatedConnection <- fetch connection.id
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "keepalive-refresh-token"
                fmap (decryptXeroToken testXeroConfig.tokenEncryptionKey) updatedConnection.encryptedAccessToken `shouldBe` Just (Right "keepalive-access-token")
                updatedConnection.connectionStatus `shouldBe` "active"
                updatedConnection.lastError `shouldBe` Nothing
                updatedConnection.lastRefreshedAt `shouldSatisfy` isJust
                updatedJob <- fetch job.id
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "marks expired Xero refresh tokens as requiring reauthorization without retrying forever" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Keepalive Expired Venue"
                owner <- createUserRecord "xero-keepalive-expired-owner@example.com" "staff" True
                connection <- createKeepaliveXeroConnection venue owner (Just (negate (8 * oneDay))) "tenant-expired" "active"
                EnqueuedAppJob job <- enqueueAppJob (keepaliveJobRequest connection)

                withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (keepaliveXeroClient (Left (XeroHttpError "{\"error\":\"invalid_grant\",\"error_description\":\"Refresh token has expired\"}"))) do
                        performXeroConnectionKeepaliveJob job

                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "reauthorization_required"
                updatedConnection.encryptedAccessToken `shouldBe` Nothing
                updatedConnection.lastError `shouldSatisfy` isJust
                updatedJob <- fetch job.id
                updatedJob.status `shouldBe` JobStatusSucceeded

oneDay :: NominalDiffTime
oneDay = 24 * 60 * 60

testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "test-client-id"
        , clientSecret = "test-client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "12345678901234567890123456789012"
        }

createKeepaliveXeroConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    Maybe NominalDiffTime ->
    Text ->
    Text ->
    IO XeroConnection
createKeepaliveXeroConnection venue owner maybeRefreshAge tenantId status = do
    now <- getCurrentTime
    encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey ("refresh-token-" <> tenantId)
    encryptedAccessToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey ("access-token-" <> tenantId)
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId tenantId
        |> set #tenantName (Just ("Tenant " <> tenantId))
        |> set #xeroConnectionRemoteId (Just ("connection-" <> tenantId))
        |> set #connectionStatus status
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #encryptedAccessToken (Just encryptedAccessToken)
        |> set #accessTokenExpiresAt (Just (addUTCTime 1800 now))
        |> set #lastRefreshedAt (addUTCTime <$> maybeRefreshAge <*> pure now)
        |> set #connectedByUserId (Just (unpackId owner.id))
        |> createRecord

setLastSyncAge ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    Maybe NominalDiffTime ->
    XeroConnection ->
    IO XeroConnection
setLastSyncAge now maybeSyncAge connection =
    connection
        |> set #lastSyncAt (addUTCTime <$> maybeSyncAge <*> pure now)
        |> updateRecord

keepaliveJobRequest :: XeroConnection -> AppJobRequest
keepaliveJobRequest connection =
    AppJobRequest
        { jobKind = xeroConnectionKeepaliveJobKind
        , payload = Aeson.object []
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing
        , venueId = Just connection.venueId
        , relatedTable = Just "xero_connections"
        , relatedId = Just (unpackId connection.id)
        , dedupeKey = Just (xeroConnectionKeepaliveDedupeKey connection)
        , runAt = Nothing
        }

keepaliveXeroClient :: Either XeroClientError XeroTokenResponse -> XeroClient
keepaliveXeroClient refreshResult =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure refreshResult
        , fetchConnectedTenants = \_ -> pure (Right [])
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure refreshResult
        , fetchPayrollEmployees = \_ _ -> pure (Right [])
        , fetchEarningsRates = \_ _ -> pure (Right [])
        , fetchEarningsRatesPage = \_ _ _ -> pure (Right [])
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        , fetchAccounts = \_ _ -> pure (Right [])
        , fetchPayrollSettingsAccounts = \_ _ -> pure (Right [])
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheetsForPeriod = \_ _ _ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }
