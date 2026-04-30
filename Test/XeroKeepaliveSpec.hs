module Test.XeroKeepaliveSpec where

import Application.Async.Queue
import Application.Helper.Xero
import Application.Xero.Keepalive
import Config
import qualified Data.Aeson as Aeson
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
tests = beforeAll testContext do
    describe "Xero keepalive jobs" do
        it "enqueues due active Xero connections and deduplicates active keepalive jobs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Keepalive Venue"
                freshVenue <- createVenueWithConfig "Xero Keepalive Fresh Venue"
                inactiveVenue <- createVenueWithConfig "Xero Keepalive Inactive Venue"
                owner <- createUserRecord "xero-keepalive-owner@example.com" "staff" True
                oldConnection <- createKeepaliveXeroConnection venue owner (Just (negate (8 * oneDay))) "tenant-old" "active"
                _freshConnection <- createKeepaliveXeroConnection freshVenue owner (Just (negate oneDay)) "tenant-fresh" "active"
                _inactiveConnection <- createKeepaliveXeroConnection inactiveVenue owner (Just (negate (8 * oneDay))) "tenant-inactive" "reauthorization_required"

                firstSummary <- enqueueDueXeroKeepaliveJobs
                firstSummary.dueConnectionCount `shouldBe` 1
                firstSummary.enqueuedJobCount `shouldBe` 1
                firstSummary.existingJobCount `shouldBe` 0

                secondSummary <- enqueueDueXeroKeepaliveJobs
                secondSummary.dueConnectionCount `shouldBe` 1
                secondSummary.enqueuedJobCount `shouldBe` 0
                secondSummary.existingJobCount `shouldBe` 1

                [job] <- query @AppJob |> filterWhere (#jobKind, xeroConnectionKeepaliveJobKind) |> fetch
                job.venueId `shouldBe` Just (unpackId venue.id)
                job.relatedTable `shouldBe` Just "xero_connections"
                job.relatedId `shouldBe` Just (unpackId oldConnection.id)
                job.dedupeKey `shouldBe` Just (xeroConnectionKeepaliveDedupeKey oldConnection)

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
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }
