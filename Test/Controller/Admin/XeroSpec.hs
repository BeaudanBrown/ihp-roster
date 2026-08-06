module Test.Controller.Admin.XeroSpec where

import Application.Async.Queue (EnqueueAppJobResult (EnqueuedAppJob))
import Application.Fixture.PayrollFixtures (createAndApproveEntry)
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes (XeroLocalEarningsBucket (..))
import Application.Helper.XeroTimesheetReadiness (readinessBlockerCodes,
                                                  validateXeroTimesheetReadiness)
import Application.PayAssignment
import Application.Xero.Keepalive (XeroKeepaliveSweepSummary (..),
                                   enqueueDueXeroMaintenanceJobsAt)
import Application.Xero.ReferenceSyncJob
import Application.Xero.ReferenceSyncRequest
import Config
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime,
                        getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Test.Support.XeroAdmin
import qualified Test.XeroMock as XeroMock
import qualified Test.XeroTimesheetPreviewSpec as Preview
import Web.Admin.Xero.Mutations (xeroConnectionTouchedResources,
                                 xeroPayItemsTouchedResources,
                                 xeroReferenceSyncTouchedResources,
                                 xeroTimesheetsTouchedResources)
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

withFastXeroReferenceSyncRuntime :: ActionWith () -> IO ()
withFastXeroReferenceSyncRuntime action =
    withXeroReferenceSyncRuntimeForTest
        XeroReferenceSyncRuntime
            { currentReferenceSyncTime = getCurrentTime
            , sleepForReferenceSyncMicros = const (pure ())
            , referenceSyncJitterSeconds = pure 0
            }
        (withInlineXeroReferenceSyncRequestsForTest (action ()))

tests :: Spec
tests = aroundAll withFastXeroReferenceSyncRuntime $ aroundAll withDatabaseTestContext do
    describe "AdminController Xero" do
        it "shows the Xero page as not connected" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Admin Venue"
                admin <- createUserRecord "xero-admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner

                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction

                adminResponse `responseStatusShouldBe` status200
                adminResponse `responseBodyShouldContain` "href=\"/Xero\""
                adminResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Xero"
                response `responseBodyShouldContain` "not connected"
                response `responseBodyShouldContain` "Connect Xero"
                response `responseBodyShouldContain` "id=\"admin-xero-fragment\""
                response `responseBodyShouldContain` "admin-xero"
                response `responseBodyShouldContain` "Connection status"
                response `responseBodyShouldNotContain` "Status:"
                response `responseBodyShouldNotContain` "app-accordion-section-header"
                response `responseBodyShouldNotContain` "Staff mappings"
                response `responseBodyShouldNotContain` "Draft timesheet submission"
                response `responseBodyShouldNotContain` "id=\"xero-timesheets-data\""

                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "id=\"admin-xero-fragment\""
                fragmentResponse `responseBodyShouldContain` "not connected"
                fragmentResponse `responseBodyShouldNotContain` "Staff mappings"
                fragmentResponse `responseBodyShouldNotContain` "Draft timesheet submission"
                fragmentResponse `responseBodyShouldNotContain` "id=\"xero-timesheets-data\""
                fragmentResponse `responseBodyShouldNotContain` "id=\"app\""

        it "loads the connected Xero shell without materializing disconnected panel data" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Shell Read Boundary Venue"
                owner <- createUserRecord "xero-shell-read-boundary@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createXeroConnectionRecord venue owner "xero-shell-read-boundary-tenant"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Upload timesheets"
                response `responseBodyShouldContain` "Import pay items"
                response `responseBodyShouldNotContain` "Sync Xero data"
                response `responseBodyShouldNotContain` "hx-post=\"/SyncXeroPayrollReferenceData\""
                response `responseBodyShouldNotContain` "data-bepis-surface-action=\"sync-xero-payroll-reference-data\""
                response `responseBodyShouldNotContain` "hx-trigger=\"load\""
                response `responseBodyShouldNotContain` "xero-staff-mappings-data"
                response `responseBodyShouldNotContain` "xero-pay-items-data"
                response `responseBodyShouldNotContain` "xero-timesheets-data"
                mappingCount <- query @XeroStaffMapping |> fetchCount
                payItemRequirementCount <- query @XeroPayItemRequirementRecord |> fetchCount
                mappingCount `shouldBe` 0
                payItemRequirementCount `shouldBe` 0

        it "rejects owner manual reference refresh requests" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Owner Refresh Block Venue"
                owner <- createUserRecord "xero-owner-refresh-block@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createSyncableXeroConnection venue owner

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                jobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                jobCount `shouldBe` 0

        it "shows sanitized reference-sync diagnostics and coalescing refresh only to founders" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Founder Diagnostics Venue"
                founder <- createUserRecordWithPlatformRole "xero-founder-diagnostics@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue founder >>= \record ->
                    record |> set #lastSyncAt (Just (addUTCTime (negate (2 * 24 * 60 * 60)) now)) |> updateRecord
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob Nothing connection
                _ <- job
                    |> set #status JobStatusFailed
                    |> set #progress (Aeson.object ["phase" Aeson..= ("accounts" :: Text), "completedPayItemsPage" Aeson..= (7 :: Int)])
                    |> set #lastError (Just "unsafe provider body token=secret")
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Reference sync diagnostics"
                response `responseBodyShouldContain` "Last successful reference sync"
                response `responseBodyShouldContain` "Stopped"
                response `responseBodyShouldContain` "Fetching Xero accounts"
                response `responseBodyShouldContain` "Completed earnings-rate page 7"
                response `responseBodyShouldContain` "Xero reference sync stopped after the accounts phase failed."
                response `responseBodyShouldNotContain` "token=secret"
                response `responseBodyShouldContain` "Sync Xero data"
                response `responseBodyShouldContain` "hx-post=\"/SyncXeroPayrollReferenceData\""

                withQueuedXeroReferenceSyncRequestsForTest do
                    firstRefresh <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction SyncXeroPayrollReferenceDataAction
                    secondRefresh <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction SyncXeroPayrollReferenceDataAction
                    firstRefresh `responseStatusShouldBe` status200
                    secondRefresh `responseStatusShouldBe` status200
                activeJobCount <-
                    query @AppJob
                        |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
                        |> filterWhereIn (#status, [JobStatusNotStarted, JobStatusRunning, JobStatusRetry])
                        |> fetchCount
                activeJobCount `shouldBe` 1

        it "opens pay-item import from a fresh local snapshot without calling Xero" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Trusted Import Venue"
                owner <- createUserRecord "xero-trusted-import@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record |> set #lastSyncAt (Just now) |> updateRecord
                rate <- createXeroEarningsRateRecord connection "Trusted Ordinary Hours" "trusted-rate"
                _ <- rate
                    |> set #rawPayload
                        ( Aeson.object
                            [ "EarningsRateID" Aeson..= ("trusted-rate" :: Text)
                            , "Name" Aeson..= ("Trusted Ordinary Hours" :: Text)
                            , "EarningsType" Aeson..= ("ORDINARYTIMEEARNINGS" :: Text)
                            , "RateType" Aeson..= ("RATEPERUNIT" :: Text)
                            , "AccountCode" Aeson..= ("477" :: Text)
                            , "TypeOfUnits" Aeson..= ("Hours" :: Text)
                            , "RatePerUnit" Aeson..= (30 :: Scientific)
                            , "IsActive" Aeson..= True
                            ]
                        )
                    |> updateRecord

                response <- withXeroConfigForTest (Left "Xero must not be called for a fresh snapshot") do
                    withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Trusted Ordinary Hours"
                response `responseBodyShouldNotContain` "Xero must not be called"
                appJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                appJobCount `shouldBe` 0

                importResponse <- withXeroConfigForTest (Left "Xero must not be called while importing a trusted local candidate") do
                    withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams ImportXeroPayItemsAction [("xeroEarningsRateId", "trusted-rate")]
                importResponse `responseBodyShouldContain` "Imported 1 Xero pay item"
                [importedItem] <- query @XeroImportedPayItem |> fetch
                importedItem.xeroEarningsRateId `shouldBe` "trusted-rate"

        it "rejects importing a provider-unavailable earnings rate from a stale form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Unavailable Import Venue"
                owner <- createUserRecord "xero-unavailable-import@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record |> set #lastSyncAt (Just now) |> updateRecord
                rate <- createXeroEarningsRateRecord connection "Removed Ordinary Hours" "removed-rate"
                _ <- rate
                    |> set #providerAvailable False
                    |> set #providerUnavailableAt (Just now)
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ImportXeroPayItemsAction [("xeroEarningsRateId", "removed-rate")]

                response `responseBodyShouldContain` "no longer available"
                importedCount <- query @XeroImportedPayItem |> fetchCount
                importedCount `shouldBe` 0

        it "queues stale pay-item import refresh, shows honest progress, and resumes from the snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Waiting Import Venue"
                owner <- createUserRecord "xero-waiting-import@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record |> set #lastSyncAt (Just (addUTCTime (negate (8 * 24 * 60 * 60)) now)) |> updateRecord

                waitingResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]

                waitingResponse `responseStatusShouldBe` status200
                waitingResponse `responseBodyShouldContain` "Refreshing Xero reference data"
                waitingResponse `responseBodyShouldContain` "Queued"
                waitingResponse `responseBodyShouldContain` "hx-trigger=\"load delay:1s\""
                [job] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                _ <- job
                    |> set #status JobStatusRunning
                    |> set #progress (Aeson.object ["phase" Aeson..= ("pay_items" :: Text), "completedPayItemsPage" Aeson..= (3 :: Int)])
                    |> updateRecord

                progressResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]
                progressResponse `responseBodyShouldContain` "Fetching Xero earnings rates"
                progressResponse `responseBodyShouldContain` "Completed page 3"
                joinedJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                joinedJobCount `shouldBe` 1

                trustedConnection <- connection |> set #lastSyncAt (Just now) |> updateRecord
                rate <- createXeroEarningsRateRecord trustedConnection "Resumed Ordinary Hours" "resumed-rate"
                _ <- rate
                    |> set #rawPayload
                        ( Aeson.object
                            [ "EarningsRateID" Aeson..= ("resumed-rate" :: Text)
                            , "Name" Aeson..= ("Resumed Ordinary Hours" :: Text)
                            , "EarningsType" Aeson..= ("ORDINARYTIMEEARNINGS" :: Text)
                            , "RateType" Aeson..= ("RATEPERUNIT" :: Text)
                            , "TypeOfUnits" Aeson..= ("Hours" :: Text)
                            , "RatePerUnit" Aeson..= (31 :: Scientific)
                            , "IsActive" Aeson..= True
                            ]
                        )
                    |> updateRecord
                resumedResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]
                resumedResponse `responseBodyShouldContain` "Resumed Ordinary Hours"

        it "keeps polling after the five-minute dialog transition" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Long Running Import Venue"
                owner <- createUserRecord "xero-long-running-import@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record |> set #lastSyncAt (Just (addUTCTime (negate (8 * 24 * 60 * 60)) now)) |> updateRecord
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob Nothing connection
                _ <- job |> set #status JobStatusRunning |> set #progress (Aeson.object ["phase" Aeson..= ("employees" :: Text)]) |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction
                            [ ("loadCandidates", "true")
                            , ("referenceWaitStartedAt", cs (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (addUTCTime (-301) now)))
                            ]

                response `responseBodyShouldContain` "Taking longer than usual"
                response `responseBodyShouldContain` "continues in the background"
                response `responseBodyShouldContain` "Fetching Xero employees"
                response `responseBodyShouldContain` "hx-trigger=\"load delay:1s\""

        it "blocks stale import and preparation after retry exhaustion with safe support guidance" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Exhausted Trust Venue"
                owner <- createUserRecord "xero-exhausted-trust@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record |> set #lastSyncAt (Just (addUTCTime (negate (8 * 24 * 60 * 60)) now)) |> updateRecord
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob Nothing connection
                _ <- job
                    |> set #status JobStatusFailed
                    |> set #lastError (Just "Xero payroll_settings sync failed: provider request returned status 503.")
                    |> updateRecord

                importResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]
                preparationResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction OpenXeroTimesheetPreparationAction

                importResponse `responseBodyShouldContain` "Contact support before importing pay items"
                preparationResponse `responseBodyShouldContain` "Contact support before preparing draft timesheets"
                importResponse `responseBodyShouldNotContain` "provider request returned"
                preparationResponse `responseBodyShouldNotContain` "provider request returned"

        it "prioritizes reconnect over stale support guidance" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Reconnect Trust Venue"
                owner <- createUserRecord "xero-reconnect-trust@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                now <- getCurrentTime
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record
                        |> set #lastSyncAt (Just (addUTCTime (negate (8 * 24 * 60 * 60)) now))
                        |> set #connectionStatus ("reauthorization_required" :: Text)
                        |> updateRecord
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob Nothing connection
                _ <- job |> set #status JobStatusFailed |> set #lastError (Just "safe terminal failure") |> updateRecord

                importResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroPayItemImportAction [("loadCandidates", "true")]
                preparationResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction OpenXeroTimesheetPreparationAction

                importResponse `responseBodyShouldContain` "Reconnect Xero before importing pay items"
                preparationResponse `responseBodyShouldContain` "Reconnect Xero before preparing draft timesheets"
                importResponse `responseBodyShouldNotContain` "Contact support"
                preparationResponse `responseBodyShouldNotContain` "Contact support"

        it "records touched resources for Xero connection mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Connection Touch Venue"

                Set.fromList (xeroConnectionTouchedResources venue.id)
                    `shouldBe` Set.fromList [xeroConnectionResource (unpackId venue.id)]

        it "records touched resources for Xero pay item mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Touched Venue"

                Set.fromList (xeroPayItemsTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [adminShiftTypesResource (unpackId venue.id)]

        it "does not invent an undeclared resource for Xero timesheet mutations" $ withContext do
            Set.fromList xeroTimesheetsTouchedResources `shouldBe` Set.empty

        it "records touched resources for Xero reference sync mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Reference Touch Venue"

                Set.fromList (xeroReferenceSyncTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [xeroConnectionResource (unpackId venue.id)]

        it "decodes Xero payroll calendar dates from API date wrappers" $ withContext do
            let decoded =
                    Aeson.eitherDecode
                        (LByteString.pack "{\"PayrollCalendarID\":\"calendar-1\",\"Name\":\"Weekly\",\"StartDate\":\"/Date(1760313600000+0000)/\",\"PaymentDate\":\"\"}") ::
                        Either String XeroPayrollCalendarRef
            fmap xeroPayrollCalendarStartDate decoded `shouldBe` Right (Just (fromGregorian 2025 10 13))
            fmap xeroPayrollCalendarPaymentDate decoded `shouldBe` Right Nothing

        it "keeps missing Xero config local to the connect action" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Missing Config Venue"
                admin <- createUserRecord "xero-missing-config@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner

                response <- withXeroConfigForTest (Left "Xero test config missing") do
                    withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction StartXeroConnectionAction

                response `responseStatusShouldBe` status302
                stateCount <- query @XeroOauthState |> fetchCount
                stateCount `shouldBe` 0

        it "starts Xero OAuth by storing venue-scoped state and redirecting to Xero" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Start Venue"
                admin <- createUserRecord "xero-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction StartXeroConnectionAction

                response `responseStatusShouldBe` status302
                [oauthState] <- query @XeroOauthState |> fetch
                oauthState.venueId `shouldBe` unpackId venue.id
                oauthState.userId `shouldBe` unpackId admin.id
                oauthState.requestedScopes `shouldBe` requiredXeroScopesText
                oauthState.redirectUri `shouldBe` testXeroConfig.redirectUri
                oauthState.consumedAt `shouldBe` Nothing
                responseHeaders response `shouldSatisfy` any (\(name, value) ->
                    let location = cs value :: String
                     in name == "Location" && "login.xero.com" `List.isInfixOf` location && "state=" `List.isInfixOf` location
                    )

        it "rejects invalid, expired, and consumed Xero OAuth states" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Invalid State Venue"
                admin <- createUserRecord "xero-invalid-state@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                expiredState <- createTestXeroOauthState venue admin "expired-state" (-60) Nothing
                consumedAt <- getCurrentTime
                consumedState <- createTestXeroOauthState venue admin "consumed-state" 600 (Just consumedAt)

                invalidResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams XeroOAuthCallbackAction [("state", "missing-state"), ("code", "code")]
                expiredResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams XeroOAuthCallbackAction [("state", cs expiredState.stateToken), ("code", "code")]
                consumedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams XeroOAuthCallbackAction [("state", cs consumedState.stateToken), ("code", "code")]

                invalidResponse `responseStatusShouldBe` status302
                expiredResponse `responseStatusShouldBe` status302
                consumedResponse `responseStatusShouldBe` status302
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 0

        it "handles Xero error callbacks without storing tokens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Error Venue"
                admin <- createUserRecord "xero-error@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                oauthState <- createTestXeroOauthState venue admin "xero-error-state" 600 Nothing

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams XeroOAuthCallbackAction
                        [ ("state", cs oauthState.stateToken)
                        , ("error", "access_denied")
                        ]

                response `responseStatusShouldBe` status302
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 0
                updatedState <- fetch oauthState.id
                updatedState.consumedAt `shouldSatisfy` isJust

        it "stores encrypted token material and tenant metadata on successful Xero callback" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Success Venue"
                admin <- createUserRecord "xero-success@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                oauthState <- createTestXeroOauthState venue admin "xero-success-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "raw-access-token" "raw-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-123" "tenant-123" (Just "Demo Company")

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callActionWithParams XeroOAuthCallbackAction
                                [ ("state", cs oauthState.stateToken)
                                , ("code", "auth-code")
                                ]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Xero"
                connection <- query @XeroConnection |> fetchOne
                connection.venueId `shouldBe` unpackId venue.id
                connection.tenantId `shouldBe` "tenant-123"
                connection.tenantName `shouldBe` Just "Demo Company"
                connection.xeroConnectionRemoteId `shouldBe` Just "connection-123"
                connection.connectionStatus `shouldBe` "active"
                connection.connectedByUserId `shouldBe` Just (unpackId admin.id)
                connection.encryptedRefreshToken `shouldNotBe` "raw-refresh-token"
                connection.encryptedAccessToken `shouldNotBe` Just "raw-access-token"
                decryptXeroToken testXeroConfig.tokenEncryptionKey connection.encryptedRefreshToken `shouldBe` Right "raw-refresh-token"
                fmap (decryptXeroToken testXeroConfig.tokenEncryptionKey) connection.encryptedAccessToken `shouldBe` Just (Right "raw-access-token")
                updatedState <- fetch oauthState.id
                updatedState.consumedAt `shouldSatisfy` isJust
                auditEvents <- query @AuditEvent |> filterWhere (#eventType, "xero_connection_completed" :: Text) |> fetch
                length auditEvents `shouldBe` 1
                [initialSyncJob] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                initialSyncJob.relatedId `shouldBe` Just (unpackId connection.id)
                initialSyncJob.requestedByUserId `shouldBe` Just (unpackId admin.id)
                initialSyncJob.status `shouldBe` JobStatusNotStarted
                sweepNow <- getCurrentTime
                sweepSummary <- enqueueDueXeroMaintenanceJobsAt sweepNow
                sweepSummary.referenceSyncDueConnectionCount `shouldBe` 1
                sweepSummary.referenceSyncEnqueuedJobCount `shouldBe` 0
                sweepSummary.referenceSyncExistingJobCount `shouldBe` 1

        it "completes Xero OAuth callback through the strict localhost Xero mock" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Mock Callback Venue"
                admin <- createUserRecord "xero-mock-callback@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                oauthState <- createTestXeroOauthState venue admin "xero-mock-callback-state" 600 Nothing

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withAdminStrictXeroMock \urls -> do
                        withXeroRequestBaseUrlsForTest urls do
                            withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                                callActionWithParams XeroOAuthCallbackAction
                                    [ ("state", cs oauthState.stateToken)
                                    , ("code", "auth-code")
                                    ]

                response `responseStatusShouldBe` status302
                connection <- query @XeroConnection |> fetchOne
                connection.tenantId `shouldBe` "tenant-id"
                connection.tenantName `shouldBe` Just "Demo Company"
                connection.xeroConnectionRemoteId `shouldBe` Just "connection-id"
                connection.connectionStatus `shouldBe` "active"
                decryptXeroToken testXeroConfig.tokenEncryptionKey connection.encryptedRefreshToken `shouldBe` Right "refresh-token"
                fmap (decryptXeroToken testXeroConfig.tokenEncryptionKey) connection.encryptedAccessToken `shouldBe` Just (Right "access-token")
                updatedState <- fetch oauthState.id
                updatedState.consumedAt `shouldSatisfy` isJust

        it "disconnects an active Xero connection without hard deleting history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Disconnect Venue"
                admin <- createUserRecord "xero-disconnect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                staleConnection <- createSyncableXeroConnection venue admin >>= \record ->
                    record
                        |> set #connectionStatus "reauthorization_required"
                        |> set #lastError (Just "Earlier expired refresh token")
                        |> updateRecord
                connection <- createSyncableXeroConnection venue admin
                let tokenResponse = XeroTokenResponse "disconnect-access-token" "disconnect-refresh-token" 1800 (Just requiredXeroScopesText)

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction DisconnectXeroConnectionAction

                response `responseStatusShouldBe` status302
                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "disconnected"
                updatedConnection.disconnectedByUserId `shouldBe` Just (unpackId admin.id)
                updatedConnection.disconnectedAt `shouldSatisfy` isJust
                updatedConnection.encryptedAccessToken `shouldBe` Nothing
                updatedConnection.xeroConnectionRemoteId `shouldBe` Just "connection-existing"
                updatedStaleConnection <- fetch staleConnection.id
                updatedStaleConnection.connectionStatus `shouldBe` "disconnected"
                updatedStaleConnection.lastError `shouldBe` Just "Superseded by local disconnect"
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 2
                currentConnectionCount <- query @XeroConnection |> filterWhereIn (#connectionStatus, ["active" :: Text, "reauthorization_required", "error"]) |> fetchCount
                currentConnectionCount `shouldBe` 0
                [auditEvent] <- query @AuditEvent |> filterWhere (#eventType, "xero_connection_disconnected" :: Text) |> fetch
                let remoteDisconnect = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "remoteDisconnect")) auditEvent.payload
                remoteDisconnect `shouldBe` Just ("succeeded" :: Text)

        it "disconnects locally when the Xero refresh token has expired" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Expired Disconnect Venue"
                owner <- createUserRecord "xero-expired-disconnect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record
                        |> set #xeroConnectionRemoteId Nothing
                        |> updateRecord

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (failingRefreshXeroClient "{\"error\":\"invalid_grant\",\"error_description\":\"Refresh token not found\"}") do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction DisconnectXeroConnectionAction

                response `responseStatusShouldBe` status302
                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "disconnected"
                updatedConnection.disconnectedByUserId `shouldBe` Just (unpackId owner.id)
                updatedConnection.disconnectedAt `shouldSatisfy` isJust
                updatedConnection.encryptedAccessToken `shouldBe` Nothing
                updatedConnection.xeroConnectionRemoteId `shouldBe` Nothing
                updatedConnection.lastError `shouldBe` Nothing
                [auditEvent] <- query @AuditEvent |> filterWhere (#eventType, "xero_connection_disconnected" :: Text) |> fetch
                let remoteDisconnect = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "remoteDisconnect")) auditEvent.payload
                remoteDisconnect `shouldBe` Just ("skipped_token_invalid" :: Text)

        it "rejects venue admins from Xero connection management actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Venue Admin Blocked Venue"
                admin <- createUserRecord "xero-venue-admin-blocked@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                oauthState <- createTestXeroOauthState venue admin "admin-state" 600 Nothing
                connection <- createActiveXeroConnection venue admin

                startResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction StartXeroConnectionAction
                callbackResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "code")]
                disconnectResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction DisconnectXeroConnectionAction

                startResponse `responseStatusShouldBe` status302
                callbackResponse `responseStatusShouldBe` status302
                disconnectResponse `responseStatusShouldBe` status302
                stateCount <- query @XeroOauthState |> fetchCount
                stateCount `shouldBe` 1
                retainedState <- fetch oauthState.id
                retainedState.consumedAt `shouldBe` Nothing
                retainedConnection <- fetch connection.id
                retainedConnection.connectionStatus `shouldBe` "active"

        it "syncs Xero payroll reference data for an active connection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Sync Venue"
                admin <- createUserRecordWithPlatformRole "xero-sync@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                connection <- createSyncableXeroConnection venue admin
                let tokenResponse = XeroTokenResponse "new-access-token" "new-refresh-token" 1800 (Just requiredXeroScopesText)
                let employees =
                        [ XeroEmployeeRef
                            "employee-1"
                            "Ada Lovelace"
                            (Just "ada@example.com")
                            (Just "ACTIVE")
                            (Aeson.object ["EmployeeID" Aeson..= ("employee-1" :: Text)])
                        ]
                let earningsRates =
                        [ XeroEarningsRateRef
                            "earnings-1"
                            "Ordinary Hours"
                            (Just "REGULAR")
                            (Just "RATEPERUNIT")
                            (Just "477")
                            (Just "Hours")
                            (Just 30)
                            True
                            (Aeson.object ["EarningsRateID" Aeson..= ("earnings-1" :: Text)])
                        ]
                let payrollCalendars =
                        [ XeroPayrollCalendarRef
                            "calendar-1"
                            "Weekly"
                            (Just "WEEKLY")
                            (Just (fromGregorian 2026 4 27))
                            (Just (fromGregorian 2026 5 1))
                            (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-1" :: Text)])
                        ]

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction XeroAction
                pageResponse `responseBodyShouldContain` "id=\"admin-xero-fragment\""
                pageResponse `responseBodyShouldContain` "admin-xero"
                pageResponse `responseBodyShouldNotContain` "admin-xero-timesheets"
                pageResponse `responseBodyShouldContain` "id=\"xero-connection-status-badge\""
                pageResponse `responseBodyShouldContain` "xero-connection-sync-label"
                pageResponse `responseBodyShouldNotContain` "id=\"xero-timesheets-data\""
                pageResponse `responseBodyShouldNotContain` "id=\"xero-timesheet-submission-indicator\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/OpenXeroTimesheetPreparation\""
                pageResponse `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                pageResponse `responseBodyShouldNotContain` "Working on Xero draft timesheets"
                pageResponse `responseBodyShouldNotContain` "Tenant ID"
                pageResponse `responseBodyShouldNotContain` "Connected</dt>"
                pageResponse `responseBodyShouldNotContain` "Last sync:"

                xeroVersionBefore <- currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                xeroVersionAfter <- currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                xeroVersionAfter `shouldBe` xeroVersionBefore
                employeeCount <- query @XeroEmployee |> fetchCount
                employeeCount `shouldBe` 1
                syncedEmployee <- query @XeroEmployee |> fetchOne
                syncedEmployee.rawPayload `shouldSatisfy` Preview.jsonContainsKey "EmployeeID"
                earningsRateCount <- query @XeroEarningsRate |> fetchCount
                earningsRateCount `shouldBe` 1
                payrollCalendarCount <- query @XeroPayrollCalendar |> fetchCount
                payrollCalendarCount `shouldBe` 1
                accountCodeSelection <- query @XeroPayItemAccountCodeSelection |> fetchOne
                accountCodeSelection.selectionStatus `shouldBe` XeroPayItemAccountCodeSelectionStatusEnumVerified
                accountCodeSelection.accountCode `shouldBe` Just "477"
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` Succeeded
                syncRun.employeesCount `shouldBe` 1
                syncRun.earningsRatesCount `shouldBe` 1
                syncRun.payrollCalendarsCount `shouldBe` 1
                updatedConnection <- fetch connection.id
                updatedConnection.lastSyncAt `shouldSatisfy` isJust
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "new-refresh-token"

        it "atomically reconciles provider availability while preserving archival and locked pay history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Availability Reconciliation Venue"
                owner <- createUserRecordWithPlatformRole "xero-availability@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner
                let tokenResponse = XeroTokenResponse "availability-access-token" "availability-refresh-token" 1800 (Just requiredXeroScopesText)
                    employee = XeroEmployeeRef "employee-availability" "Available Worker" (Just "worker@example.com") (Just "ACTIVE") (Aeson.object ["EmployeeID" Aeson..= ("employee-availability" :: Text)])
                    rate = XeroEarningsRateRef "rate-availability" "Venue ordinary" (Just "ORDINARYTIMEEARNINGS") (Just "RATEPERUNIT") (Just "477") (Just "Hours") (Just 30) True (Aeson.object ["EarningsRateID" Aeson..= ("rate-availability" :: Text)])
                    calendar = XeroPayrollCalendarRef "calendar-availability" "Weekly" (Just "WEEKLY") (Just (fromGregorian 2026 4 27)) (Just (fromGregorian 2026 5 1)) (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-availability" :: Text)])
                    runSync client = withXeroConfigForTest (Right testXeroConfig) do
                        withXeroClientForTest client do
                            withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                                callAction SyncXeroPayrollReferenceDataAction

                initialResponse <- runSync (referenceSyncXeroClient tokenResponse [employee] [rate] [calendar])
                initialResponse `responseStatusShouldBe` status302
                syncedEmployee <- query @XeroEmployee |> fetchOne
                syncedRate <- query @XeroEarningsRate |> fetchOne
                syncedAccount <- query @XeroAccount |> fetchOne
                syncedCalendar <- query @XeroPayrollCalendar |> fetchOne
                now <- getCurrentTime
                importedItem <-
                    newRecord @XeroImportedPayItem
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #xeroEarningsRateId rate.xeroEarningsRateId
                        |> set #name rate.xeroEarningsRateName
                        |> set #accountCode rate.xeroEarningsRateAccountCode
                        |> set #earningsType "ORDINARYTIMEEARNINGS"
                        |> set #rateType "RATEPERUNIT"
                        |> set #typeOfUnits "Hours"
                        |> set #ratePerUnit 30
                        |> set #rawPayload rate.xeroEarningsRateRaw
                        |> set #importedByUserId (unpackId owner.id)
                        |> createRecord
                staff <- createStaffRecord venue Nothing "Pinned" "Worker"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedItem.id)
                lockedVersion <-
                    newRecord @StaffPayVersion
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #payAssignmentMode XeroRate
                        |> set #importedXeroPayItemId (Just importedItem.id)
                        |> set #employmentBasis Permanent
                        |> set #effectiveFrom (fromGregorian 2026 4 27)
                        |> set #createdByUserId (unpackId owner.id)
                        |> set #lockedAt (Just now)
                        |> set #lockedByUserId (Just (unpackId owner.id))
                        |> createRecord
                _ <-
                    newRecord @XeroStaffMapping
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #xeroEmployeeId (Just employee.xeroEmployeeId)
                        |> set #mappingStatus XeroStaffMappingStatusEnumVerified
                        |> set #lastVerifiedAt (Just now)
                        |> createRecord
                _ <-
                    newRecord @XeroEarningsRateMapping
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #localBucketKey "availability-bucket"
                        |> set #localBucketLabel "Availability bucket"
                        |> set #xeroEarningsRateId (Just rate.xeroEarningsRateId)
                        |> set #mappingStatus XeroEarningsRateMappingStatusEnumVerified
                        |> set #lastVerifiedAt (Just now)
                        |> createRecord
                _ <-
                    newRecord @XeroPayItemRequirementRecord
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #requirementKey "availability-requirement"
                        |> set #displayName "Availability requirement"
                        |> set #earningsType "ORDINARYTIMEEARNINGS"
                        |> set #rateType "RATEPERUNIT"
                        |> set #sourceDescription "availability test"
                        |> set #requirementStatus Matched
                        |> set #xeroEarningsRateId (Just rate.xeroEarningsRateId)
                        |> set #lastVerifiedAt (Just now)
                        |> createRecord

                let incompleteError = XeroHttpResponseError 400 Nothing "incomplete earnings-rate pull"
                    failedClient = (referenceSyncXeroClient tokenResponse [] [] [])
                        { fetchEarningsRates = \_ _ -> pure (Left incompleteError)
                        , fetchEarningsRatesPage = \_ _ _ -> pure (Left incompleteError)
                        }
                failedResponse <- runSync failedClient
                failedResponse `responseStatusShouldBe` status302
                fetch syncedEmployee.id >>= (\record -> record.providerAvailable `shouldBe` True)
                fetch syncedRate.id >>= (\record -> record.providerAvailable `shouldBe` True)
                fetch syncedAccount.id >>= (\record -> record.providerAvailable `shouldBe` True)
                fetch syncedCalendar.id >>= (\record -> record.providerAvailable `shouldBe` True)
                failedSyncMapping <- query @XeroStaffMapping |> fetchOne
                failedSyncMapping.referenceRefreshedAt `shouldBe` Nothing

                let inactiveEmployee = employee { xeroEmployeeStatus = Just "INACTIVE" }
                    inactiveRate = rate { xeroEarningsRateIsActive = False }
                    unavailableClient = (referenceSyncXeroClient tokenResponse [inactiveEmployee] [inactiveRate] [])
                        { fetchAccounts = \_ _ -> pure (Right [])
                        , fetchPayrollSettingsAccounts = \_ _ -> pure (Right [])
                        }
                unavailableResponse <- runSync unavailableClient
                unavailableResponse `responseStatusShouldBe` status302

                unavailableEmployee <- fetch syncedEmployee.id
                unavailableRate <- fetch syncedRate.id
                unavailableAccount <- fetch syncedAccount.id
                unavailableCalendar <- fetch syncedCalendar.id
                unavailableImport <- fetch importedItem.id
                unavailableEmployee.providerAvailable `shouldBe` False
                unavailableRate.providerAvailable `shouldBe` False
                unavailableAccount.providerAvailable `shouldBe` False
                unavailableCalendar.providerAvailable `shouldBe` False
                unavailableImport.providerAvailable `shouldBe` False
                map (.providerUnavailableAt) [unavailableEmployee] `shouldSatisfy` all isJust
                unavailableImport.providerUnavailableAt `shouldSatisfy` isJust
                unavailableImport.archivedAt `shouldBe` Nothing
                unavailableImport.archivedByUserId `shouldBe` Nothing
                fetch lockedVersion.id >>= (\version -> version.importedXeroPayItemId `shouldBe` Just importedItem.id)
                staffMapping <- query @XeroStaffMapping |> fetchOne
                staffMapping.mappingStatus `shouldBe` XeroStaffMappingStatusEnumStale
                staffMapping.referenceRefreshedAt `shouldSatisfy` isJust
                earningsMapping <- query @XeroEarningsRateMapping |> fetchOne
                earningsMapping.mappingStatus `shouldBe` XeroEarningsRateMappingStatusEnumStale
                managedRequirement <- query @XeroPayItemRequirementRecord |> fetchOne
                managedRequirement.requirementStatus `shouldBe` XeroPayItemRequirementStatusEnumStale
                managedRequirement.lastVerifiedAt `shouldBe` Nothing
                staffEditResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]
                staffEditResponse `responseBodyShouldContain` "Pay configuration required"
                staffEditResponse `responseBodyShouldNotContain` "Venue ordinary"
                staffPayAssignmentRequiresRemediation [] [] (StaffPayAssignment XeroRate Nothing (Just importedItem.id)) `shouldBe` True
                staffPayAssignmentRequiresRemediation [] [] (StaffPayAssignment RosterOnly Nothing Nothing) `shouldBe` False
                shiftPayAssignmentRequiresRemediation [] [] (ShiftPayAssignment StaffDefault Nothing Nothing) `shouldBe` False

                reappearedResponse <- runSync (referenceSyncXeroClient tokenResponse [employee] [rate] [calendar])
                reappearedResponse `responseStatusShouldBe` status302
                reappearedEmployee <- fetch syncedEmployee.id
                reappearedRate <- fetch syncedRate.id
                reappearedAccount <- fetch syncedAccount.id
                reappearedCalendar <- fetch syncedCalendar.id
                reappearedImport <- fetch importedItem.id
                map (.providerAvailable) [reappearedEmployee] `shouldBe` [True]
                reappearedRate.providerAvailable `shouldBe` True
                reappearedAccount.providerAvailable `shouldBe` True
                reappearedCalendar.providerAvailable `shouldBe` True
                reappearedImport.providerAvailable `shouldBe` True
                reappearedImport.providerUnavailableAt `shouldBe` Nothing
                reappearedImport.archivedAt `shouldBe` Nothing

        it "syncs Xero payroll reference data over HTMX with actor-local shell invalidation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero HTMX Sync Venue"
                admin <- createUserRecordWithPlatformRole "xero-htmx-sync@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                _connection <- createSyncableXeroConnection venue admin
                let tokenResponse = XeroTokenResponse "htmx-access-token" "htmx-refresh-token" 1800 (Just requiredXeroScopesText)

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                response `responseBodyShouldNotContain` "id=\"xero-pay-items-data\""
                response `responseBodyShouldContain` "Synced Xero payroll reference data"
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin-xero-shell")
                triggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-xero-fragment")
                triggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "/ShowadminXeroShellLiveFragment")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf ("admin-xero:" <> tshow (unpackId venue.id)))

        it "preselects the Xero wages expense account while retaining ambiguous payroll calendars" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Multiple Defaults Venue"
                admin <- createUserRecordWithPlatformRole "xero-multiple-defaults@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                connection <- createSyncableXeroConnection venue admin
                let tokenResponse = XeroTokenResponse "new-access-token" "new-refresh-token" 1800 (Just requiredXeroScopesText)
                let employees = []
                let earningsRates =
                        [ XeroEarningsRateRef
                            "earnings-1"
                            "Ordinary Hours"
                            (Just "REGULAR")
                            (Just "RATEPERUNIT")
                            (Just "477")
                            (Just "Hours")
                            (Just 30)
                            True
                            (Aeson.object ["EarningsRateID" Aeson..= ("earnings-1" :: Text)])
                        , XeroEarningsRateRef
                            "earnings-2"
                            "Saturday Hours"
                            (Just "REGULAR")
                            (Just "RATEPERUNIT")
                            (Just "478")
                            (Just "Hours")
                            (Just 35)
                            True
                            (Aeson.object ["EarningsRateID" Aeson..= ("earnings-2" :: Text)])
                        ]
                let payrollCalendars =
                        [ XeroPayrollCalendarRef
                            "calendar-1"
                            "Weekly"
                            (Just "WEEKLY")
                            (Just (fromGregorian 2026 4 27))
                            (Just (fromGregorian 2026 5 1))
                            (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-1" :: Text)])
                        , XeroPayrollCalendarRef
                            "calendar-2"
                            "Fortnightly"
                            (Just "FORTNIGHTLY")
                            (Just (fromGregorian 2026 4 27))
                            (Just (fromGregorian 2026 5 8))
                            (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-2" :: Text)])
                        ]

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                accountCodeSelection <- query @XeroPayItemAccountCodeSelection |> fetchOne
                accountCodeSelection.selectionStatus `shouldBe` XeroPayItemAccountCodeSelectionStatusEnumVerified
                accountCodeSelection.accountCode `shouldBe` Just "477"
                payrollCalendarCount <- query @XeroPayrollCalendar |> fetchCount
                payrollCalendarCount `shouldBe` 2

        it "syncs Xero payroll reference data through the strict localhost Xero mock" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Mock Sync Venue"
                admin <- createUserRecordWithPlatformRole "xero-mock-sync@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                connection <- createSyncableXeroConnection venue admin

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withAdminStrictXeroMock \urls -> do
                        withXeroRequestBaseUrlsForTest urls do
                            withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                                callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                employeeCount <- query @XeroEmployee |> fetchCount
                employeeCount `shouldBe` 1
                earningsRateCount <- query @XeroEarningsRate |> fetchCount
                earningsRateCount `shouldBe` 1
                payrollCalendarCount <- query @XeroPayrollCalendar |> fetchCount
                payrollCalendarCount `shouldBe` 1
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` Succeeded
                syncRun.employeesCount `shouldBe` 1
                syncRun.earningsRatesCount `shouldBe` 1
                syncRun.payrollCalendarsCount `shouldBe` 1
                updatedConnection <- fetch connection.id
                updatedConnection.lastSyncAt `shouldSatisfy` isJust
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "refresh-token"

        it "shows synced Xero payroll-calendar periods that contain approved local entries without requiring a pay run" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                payRun <- query @XeroPayRun |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetchOne
                _ <-
                    payRun
                        |> set #payPeriodStart (addDays 7 fixture.periodStart)
                        |> set #payPeriodEnd (addDays 7 fixture.periodEnd)
                        |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldContain` "Upload timesheets"
                response `responseBodyShouldNotContain` "DRAFT"
                response `responseBodyShouldNotContain` "submitted already"

        it "marks Xero pay periods that already have a local submitted run" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                _ <- createSubmissionRunForFixture fixture XeroSubmissionRunStatusEnumSubmitted

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` "submitted already"

        it "uses the latest local Xero submission run status for a pay period" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                older <- createSubmissionRunForFixture fixture XeroSubmissionRunStatusEnumFailed
                newer <- createSubmissionRunForFixture fixture XeroSubmissionRunStatusEnumSubmitted
                now <- getCurrentTime
                _ <- older |> set #updatedAt (addUTCTime (-60) now) |> updateRecord
                _ <- newer |> set #updatedAt now |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "submitted already"
                response `responseBodyShouldNotContain` "failed previously"

        it "does not mark other Xero pay periods from local submission history" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                _ <-
                    newRecord @XeroSubmissionRun
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #submittedByUserId (unpackId fixture.owner.id)
                        |> set #payPeriodStart (addDays 7 fixture.periodStart)
                        |> set #payPeriodEnd (addDays 7 fixture.periodEnd)
                        |> set #selectedPayrollCalendarId (Just ("calendar-preview" :: Text))
                        |> set #selectedPayrollCalendarName (Just ("Preview Calendar" :: Text))
                        |> set #selectedPeriodKey (Just ("calendar-preview:" <> tshow (addDays 7 fixture.periodStart) <> ":" <> tshow (addDays 7 fixture.periodEnd) :: Text))
                        |> set #status XeroSubmissionRunStatusEnumSubmitted
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` "submitted already"

        it "only offers payroll-calendar periods that match the approved employees' Xero calendars" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                _ <- createXeroPayrollCalendarRecord fixture.connection "Other Weekly Calendar" "calendar-other"
                employees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ employees \employee ->
                    employee
                        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employee.xeroEmployeeId, "PayrollCalendarID" Aeson..= ("calendar-other" :: Text)])
                        |> updateRecord
                        >>= const (pure ())
                let otherPeriodKey = "calendar-other:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` ("value=\"" <> fixturePeriodKey fixture <> "\"")

        it "does not show Xero pay periods that only have unapproved local entries" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                forM_ fixture.entries \entry ->
                    entry
                        |> set #isApproved False
                        |> set #activePayCalculationId Nothing
                        |> set #legacyPayBackfillPending False
                        |> set #approvedAt Nothing
                        |> set #approvedByUserId Nothing
                        |> set #staffPayVersionId Nothing
                        |> set #shiftTypePayVersionId Nothing
                        |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` ("value=\"" <> fixturePeriodKey fixture <> "\"")

        it "does not show posted Xero pay-run periods in the draft-timesheet dropdown" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                payRun <- query @XeroPayRun |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetchOne
                _ <- payRun |> set #payRunStatus (Just ("POSTED" :: Text)) |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` ("value=\"" <> fixturePeriodKey fixture <> "\"")

        it "shows historical unposted Xero periods when they contain approved local entries" $ withContext do
            withCleanDb do
                let historicalStart = fromGregorian 2025 1 6
                fixture <- Preview.createPreviewFixtureAtPeriod "weekly" historicalStart [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                _ <- createXeroPayRunForFixture fixture "DRAFT"

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` "DRAFT"

        it "queues missing-mapping refresh only for approval-pinned payroll-eligible work" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                entry <- maybe (error "Expected fixture entry") pure (listToMaybe fixture.entries)
                _ <- entry |> set #approvedAt (Just (addUTCTime 1 now)) |> updateRecord
                _ <- fixture.staffA
                    |> set #payAssignmentMode RosterOnly
                    |> set #defaultAwardLevelId Nothing
                    |> set #importedXeroPayItemId Nothing
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroTimesheetPreparationAction [("referenceDemand", "snapshot")]

                response `responseBodyShouldContain` "Refreshing Xero reference data"
                jobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                jobCount `shouldBe` 1

        it "does not request missing-mapping refresh for effective roster-only work" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                entry <- maybe (error "Expected fixture entry") pure (listToMaybe fixture.entries)
                _ <- entry
                    |> set #isApproved False
                    |> set #activePayCalculationId Nothing
                    |> set #legacyPayBackfillPending False
                    |> set #staffPayVersionId Nothing
                    |> set #shiftTypePayVersionId Nothing
                    |> set #approvedAt Nothing
                    |> set #approvedByUserId Nothing
                    |> updateRecord
                _ <- fixture.staffA
                    |> set #payAssignmentMode RosterOnly
                    |> set #defaultAwardLevelId Nothing
                    |> set #importedXeroPayItemId Nothing
                    |> updateRecord
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just (addUTCTime (-1) now)) |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA

                response <- withXeroConfigForTest (Left "Roster-only work must not call Xero") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction OpenXeroTimesheetPreparationAction

                response `responseBodyShouldNotContain` "Refreshing Xero reference data"
                response `responseBodyShouldNotContain` "Roster-only work must not call Xero"
                jobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                jobCount `shouldBe` 0

        it "opens preparation from a fresh snapshot without requesting Xero" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord

                response <- withXeroConfigForTest (Left "Xero must not be called for fresh preparation") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction OpenXeroTimesheetPreparationAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepare Xero draft timesheets"
                response `responseBodyShouldNotContain` "Xero must not be called"
                appJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                appJobCount `shouldBe` 0

        it "does not resync a missing staff mapping after a successful fresh snapshot" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                awardLevel <- query @AwardLevel |> fetchOne
                unmappedStaff <- Preview.createMappedStaff fixture.venue awardLevel "Fresh" "Unmapped"
                approvedAt <- getCurrentTime
                _ <- createAndApproveEntry fixture.venue unmappedStaff fixture.periodStart () fixture.owner approvedAt []
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord

                response <- withXeroConfigForTest (Left "Xero must not be called after a successful fresh snapshot") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction OpenXeroTimesheetPreparationAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepare Xero draft timesheets"
                response `responseBodyShouldNotContain` "Refreshing Xero reference data"
                appJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                appJobCount `shouldBe` 0

        it "does not resync an unresolved placeholder created after a successful snapshot" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                placeholder <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetchOne
                _ <- placeholder |> set #updatedAt (addUTCTime 1 now) |> updateRecord

                response <- withXeroConfigForTest (Left "Xero must not be called for a placeholder already covered by the snapshot") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction OpenXeroTimesheetPreparationAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepare Xero draft timesheets"
                response `responseBodyShouldNotContain` "Refreshing Xero reference data"
                appJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                appJobCount `shouldBe` 0

        it "uses a fresh snapshot when actual missing-staff demand has an active retry" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                entry <- maybe (error "Expected fixture entry") pure (listToMaybe fixture.entries)
                _ <- entry |> set #approvedAt (Just (addUTCTime 1 now)) |> updateRecord
                EnqueuedAppJob retryJob <- enqueueXeroReferenceSyncJob (Just fixture.owner.id) fixture.connection
                _ <- retryJob
                    |> set #runAt (addUTCTime 3600 now)
                    |> set #payload (Aeson.object ["requestedAt" Aeson..= now, "retryNumber" Aeson..= (1 :: Int)])
                    |> updateRecord

                response <- withXeroConfigForTest (Left "Xero must not be called while using a fresh snapshot") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams OpenXeroTimesheetPreparationAction [("referenceDemand", "missing_payroll_staff")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepare Xero draft timesheets"
                response `responseBodyShouldNotContain` "Refreshing Xero reference data"
                appJobCount <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetchCount
                appJobCount `shouldBe` 1

        it "waits for stale preparation references and resumes after the durable sync" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just (addUTCTime (negate (8 * 24 * 60 * 60)) now)) |> updateRecord

                waitingResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction OpenXeroTimesheetPreparationAction
                waitingResponse `responseBodyShouldContain` "Refreshing Xero reference data"
                waitingResponse `responseBodyShouldContain` "Queued"
                waitingResponse `responseBodyShouldContain` "hx-trigger=\"load delay:1s\""
                [job] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                _ <- job
                    |> set #status JobStatusRunning
                    |> set #progress (Aeson.object ["phase" Aeson..= ("payroll_calendars" :: Text), "completedPayItemsPage" Aeson..= (4 :: Int)])
                    |> updateRecord

                progressResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction RunXeroTimesheetPreparationAction
                progressResponse `responseBodyShouldContain` "Fetching Xero payroll calendars"
                progressResponse `responseBodyShouldContain` "Completed page 4"

                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord
                resumedResponse <- withXeroConfigForTest (Left "Xero must not be called after preparation resumes") do
                    withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction RunXeroTimesheetPreparationAction
                resumedResponse `responseBodyShouldContain` "Prepare Xero draft timesheets"
                resumedResponse `responseBodyShouldNotContain` "Xero must not be called"

        it "opens the guided Xero preparation modal for a selected pay period" $ withContext do
            withCleanDb do
                fixture <-
                    Preview.createPreviewFixture
                        "weekly"
                        [ Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                        , Preview.EntrySpec 1 Preview.fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                        ]
                firstEntry <- maybe (error "Expected a fixture timesheet entry") pure (listToMaybe fixture.entries)
                _ <- firstEntry |> set #endsAt (addUTCTime 30 firstEntry.endsAt) |> updateRecord
                markOtherFixtureStaffNotPaid fixture
                employeeB <-
                    query @XeroEmployee
                        |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                        |> filterWhere (#xeroEmployeeId, "employee-b" :: Text)
                        |> fetchOne
                _ <-
                    employeeB
                        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeB.xeroEmployeeId])
                        |> updateRecord
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord

                xeroClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams OpenXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Step 2 of 4"
                response `responseBodyShouldContain` "Choose the Xero payroll period"
                response `responseBodyShouldContain` "name=\"periodKey\""
                response `responseBodyShouldContain` ("value=\"" <> fixturePeriodKey fixture <> "\"")
                response `responseBodyShouldNotContain` "Step 1 of 3"
                response `responseBodyShouldNotContain` "Staff mappings"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne

                summaryResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction preparationRun.id)
                                    [("periodKey", fixturePeriodKey fixture)]

                summaryResponse `responseStatusShouldBe` status200
                summaryResponse `responseBodyShouldContain` "Pay period:"
                summaryResponse `responseBodyShouldContain` "Step 3 of 3"
                summaryResponse `responseBodyShouldContain` "Timesheet summary"
                summaryResponse `responseBodyShouldContain` "Approved shifts"
                summaryResponse `responseBodyShouldContain` "4.01"
                summaryResponse `responseBodyShouldContain` "Ada Lovelace"
                summaryResponse `responseBodyShouldNotContain` "Grace Hopper"
                summaryResponse `responseBodyShouldContain` "Submit draft timesheets to Xero"
                summaryResponse `responseBodyShouldNotContain` "Readiness validation"
                summaryResponse `responseBodyShouldNotContain` "· payment"
                summaryResponse `responseBodyShouldNotContain` "Setup"
                summaryResponse `responseBodyShouldNotContain` "Sync reference data"
                summaryResponse `responseBodyShouldNotContain` "Earnings-rate mappings"
                summaryResponse `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                preparationRun <- fetch preparationRun.id
                matchedResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ShowXeroTimesheetPreparationStaffMappingsFragmentAction preparationRun.id)
                            [("showMatched", "true")]
                matchedResponse `responseStatusShouldBe` status200
                matchedResponse `responseBodyShouldNotContain` "Ada Lovelace"
                matchedResponse `responseBodyShouldNotContain` "Show matched"
                matchedResponse `responseBodyShouldNotContain` "app-toggle-button btn-success"
                preparationRun.status `shouldBe` ReadyForPreview
                preparationRun.payPeriodStart `shouldBe` Just fixture.periodStart
                preparationRun.payPeriodEnd `shouldBe` Just fixture.periodEnd
                (AesonTypes.parseMaybe AesonTypes.parseJSON preparationRun.eventsJson :: Maybe [Aeson.Value]) `shouldSatisfy` maybe False (not . null)

        it "shows suggested staff matches as approve-only rows until edited in guided preparation" $ withContext do
            withCleanDb do
                fixture <-
                    Preview.createPreviewFixture
                        "weekly"
                        [ Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                        , Preview.EntrySpec 1 Preview.fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                        ]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                resetXeroStaffMappingForPreparation fixture.staffB
                mappingRefreshCompletedAt <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just mappingRefreshCompletedAt) |> updateRecord
                refreshedMappings <- query @XeroStaffMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ refreshedMappings \mapping -> do
                    _ <- mapping |> set #referenceRefreshedAt (Just mappingRefreshCompletedAt) |> updateRecord
                    pure ()

                xeroClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff mappings"
                response `responseBodyShouldNotContain` "Show matched"
                response `responseBodyShouldContain` "data-bepis-surface-action=\"show-xero-timesheet-preparation-staff-mappings\""
                response `responseBodyShouldContain` "Xero employee"
                response `responseBodyShouldContain` "Suggested match — click Approve to confirm"
                response `responseBodyShouldContain` "Ada Lovelace"
                response `responseBodyShouldContain` "Edit"
                pendingStaffDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, StaffAutoMatch) |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending) |> fetchCount
                pendingStaffDecisions `shouldBe` 2
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` NeedsApproval

                matchedResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ShowXeroTimesheetPreparationStaffMappingsFragmentAction preparationRun.id)
                            [("showMatched", "true")]

                matchedResponse `responseStatusShouldBe` status200
                matchedResponse `responseBodyShouldNotContain` "Show matched"
                matchedResponse `responseBodyShouldNotContain` ">Approve</button>"
                matchedResponse `responseBodyShouldNotContain` "Skip this time"
                matchedResponse `responseBodyShouldNotContain` "Manual employee"
                matchedResponse `responseBodyShouldNotContain` "name=\"xeroEmployeeId\""
                matchedResponse `responseBodyShouldNotContain` "value=\"approve_suggestion\""
                matchedResponse `responseBodyShouldNotContain` "value=\"manual\""

                continueResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ContinueXeroTimesheetPreparationStaffStepAction preparationRun.id)
                continueResponse `responseStatusShouldBe` status200
                appliedStaffDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, StaffAutoMatch) |> filterWhere (#decisionStatus, Applied) |> fetchCount
                appliedStaffDecisions `shouldBe` 2
                staffStepApprovals <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, StaffStepApproved) |> filterWhere (#decisionStatus, Applied) |> fetchCount
                staffStepApprovals `shouldBe` 1

        it "applies the selected suggested employee through the unified preparation dropdown" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                mappingRefreshCompletedAt <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just mappingRefreshCompletedAt) |> updateRecord
                refreshedMappings <- query @XeroStaffMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ refreshedMappings \mapping -> do
                    _ <- mapping |> set #referenceRefreshedAt (Just mappingRefreshCompletedAt) |> updateRecord
                    pure ()
                xeroClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]
                run <- query @XeroTimesheetPreparationRun |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ApplyXeroTimesheetPreparationStaffDecisionAction run.id)
                            [ ("staffId", idToParam fixture.staffA.id)
                            , ("decision", "select_employee")
                            , ("xeroEmployeeSelection", "employee-a")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Confirm match"
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetchOne
                mapping.mappingStatus `shouldBe` XeroStaffMappingStatusEnumVerified
                mapping.xeroEmployeeId `shouldBe` Just "employee-a"
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, StaffAutoMatch) |> fetchOne
                decision.decisionStatus `shouldBe` Applied
                decision.xeroEmployeeId `shouldBe` Just "employee-a"

        it "shows proposed managed pay item creation instead of manual earnings-rate mapping in the preparation modal" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                existingRates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ existingRates \rate ->
                    rate
                        |> set #isActive False
                        |> updateRecord
                        >>= const (pure ())
                _ <- createXeroEarningsRateRecord fixture.connection "Ordinary Hours" "earnings-account-code"

                xeroClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Step 2 of 4"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                payItemResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction preparationRun.id)
                                    [("periodKey", fixturePeriodKey fixture)]
                payItemResponse `responseStatusShouldBe` status200
                payItemResponse `responseBodyShouldContain` "Step 2 of 3"
                payItemResponse `responseBodyShouldContain` "Managed pay items"
                payItemResponse `responseBodyShouldNotContain` "will be created on submit"
                payItemResponse `responseBodyShouldNotContain` "1 will be created on submit"
                payItemResponse `responseBodyShouldContain` "Ordinary - "
                payItemResponse `responseBodyShouldContain` " - PERM - Bepis - 6-January-2020"
                payItemResponse `responseBodyShouldNotContain` "Approve creation"
                payItemResponse `responseBodyShouldNotContain` "Earnings-rate mappings"
                payItemResponse `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                pendingPayItemDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, PayItemCreate) |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending) |> fetchCount
                pendingPayItemDecisions `shouldSatisfy` (> 0)
                refreshedPreparationRun <- fetch preparationRun.id
                refreshedPreparationRun.status `shouldBe` ReadyForPreview

        it "creates proposed managed Xero pay items automatically when submitting from preparation" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #tenantId ("tenant-id" :: Text)
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                existingRates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ existingRates \rate ->
                    rate
                        |> set #isActive False
                        |> updateRecord
                        >>= const (pure ())
                _ <- createXeroEarningsRateRecord fixture.connection "Ordinary Hours" "earnings-account-code"
                requestsRef <- liftIO $ IORef.newIORef []
                let tokenResponse = XeroTokenResponse "submit-access-token" "submit-refresh-token" 1800 (Just requiredXeroScopesText)
                baseClient <- referenceSyncXeroClientForFixture tokenResponse fixture.connection
                let xeroClient = (payItemCreateXeroClient tokenResponse requestsRef)
                        { fetchPayrollEmployees = fetchPayrollEmployees baseClient
                        , fetchPayrollCalendars = fetchPayrollCalendars baseClient
                        , fetchAccounts = fetchAccounts baseClient
                        , fetchPayrollSettingsAccounts = fetchPayrollSettingsAccounts baseClient
                        }
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]
                run <- query @XeroTimesheetPreparationRun |> fetchOne
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction run.id)
                                    [("periodKey", fixturePeriodKey fixture)]

                payItemDecisions <-
                    query @XeroTimesheetPreparationDecision
                        |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
                        |> filterWhere (#decisionKind, PayItemCreate)
                        |> fetch
                forM_ payItemDecisions \decision ->
                    decision
                        |> set #decisionStatus Dismissed
                        |> updateRecord
                        >>= const (pure ())

                approvalResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (ApproveXeroTimesheetPreparationPayItemsAction run.id)
                                    [("accountCode", "477")]

                approvalResponse `responseStatusShouldBe` status200
                approvalResponse `responseBodyShouldContain` "Step 3 of 3"
                approvalResponse `responseBodyShouldContain` "Review the draft timesheets Bepis will submit to Xero."
                approvalResponse `responseBodyShouldContain` "Approved shifts"
                approvalResponse `responseBodyShouldContain` "Estimated wages"
                approvalResponse `responseBodyShouldContain` "4.00"
                approvalResponse `responseBodyShouldContain` "$"
                approvalResponse `responseBodyShouldNotContain` "Managed Xero pay item requirements must be matched or created before timesheet readiness."
                approvalResponse `responseBodyShouldNotContain` "Employee-level preview rows will be finalized"
                approvalRequests <- liftIO $ IORef.readIORef requestsRef
                approvalRequests `shouldBe` []
                pendingAfterApproval <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, PayItemCreate) |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending) |> fetchCount
                pendingAfterApproval `shouldBe` 0
                appliedAfterApproval <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, PayItemCreate) |> filterWhere (#decisionStatus, Applied) |> fetchCount
                appliedAfterApproval `shouldSatisfy` (> 0)

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SubmitXeroTimesheetPreparationAction run.id)
                                    [("accountCode", "477")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Submitted Xero draft timesheets."
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                createRequests <- liftIO $ IORef.readIORef requestsRef
                length createRequests `shouldSatisfy` (> 0)
                refreshedRun <- fetch run.id
                refreshedRun.status `shouldBe` XeroTimesheetPreparationRunStatusEnumSubmitted
                submissionRun <- query @XeroSubmissionRun |> filterWhere (#status, XeroSubmissionRunStatusEnumSubmitted) |> fetchOne
                submissionRun.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                pendingPayItemDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, PayItemCreate) |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending) |> fetchCount
                pendingPayItemDecisions `shouldBe` 0

        it "reports unverified managed pay item creation during preparation submit" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #tenantId ("tenant-id" :: Text)
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                existingRates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ existingRates \rate ->
                    rate
                        |> set #isActive False
                        |> updateRecord
                        >>= const (pure ())
                _ <- createXeroEarningsRateRecord fixture.connection "Ordinary Hours" "earnings-account-code"
                requestsRef <- liftIO $ IORef.newIORef []
                let tokenResponse = XeroTokenResponse "submit-access-token" "submit-refresh-token" 1800 (Just requiredXeroScopesText)
                baseClient <- referenceSyncXeroClientForFixture tokenResponse fixture.connection
                let xeroClient = (payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef (Just 0))
                        { fetchPayrollEmployees = fetchPayrollEmployees baseClient
                        , fetchPayrollCalendars = fetchPayrollCalendars baseClient
                        , fetchAccounts = fetchAccounts baseClient
                        , fetchPayrollSettingsAccounts = fetchPayrollSettingsAccounts baseClient
                        }
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]
                run <- query @XeroTimesheetPreparationRun |> fetchOne
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction run.id)
                                    [("periodKey", fixturePeriodKey fixture)]
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (ApproveXeroTimesheetPreparationPayItemsAction run.id)
                                    [("accountCode", "477")]

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SubmitXeroTimesheetPreparationAction run.id)
                                    [("accountCode", "477")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Submitted 1 Xero pay item creates and verified 0 after pulling Xero pay items."
                response `responseBodyShouldContain` "Still missing:"
                response `responseBodyShouldNotContain` "Managed Xero pay item requirements must be matched or created before timesheet readiness."
                createRequests <- liftIO $ IORef.readIORef requestsRef
                length createRequests `shouldBe` 1
                refreshedRun <- fetch run.id
                refreshedRun.status `shouldNotBe` XeroTimesheetPreparationRunStatusEnumSubmitted

        it "uses the preparation period without a global payroll-calendar selection" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction XeroAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldNotContain` "Draft timesheet submission"
                pageResponse `responseBodyShouldNotContain` "name=\"periodKey\""
                pageResponse `responseBodyShouldContain` "Upload timesheets"

                xeroClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction RunXeroTimesheetPreparationAction
                preparationRunBeforeSelect <- query @XeroTimesheetPreparationRun |> fetchOne
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest xeroClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction preparationRunBeforeSelect.id)
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Setup"
                response `responseBodyShouldNotContain` "name=\"xeroPayrollCalendarSelection\""
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                preparationRun.status `shouldBe` ReadyForPreview

        it "hard-blocks guided Xero preparation when the selected Xero pay run is posted" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                let postedPayRun =
                        XeroPayRunRef
                            { xeroPayRunId = "payrun-posted"
                            , xeroPayRunCalendarId = "calendar-preview"
                            , xeroPayRunPeriodStart = fixture.periodStart
                            , xeroPayRunPeriodEnd = fixture.periodEnd
                            , xeroPayRunPaymentDate = Nothing
                            , xeroPayRunStatus = Just "POSTED"
                            , xeroPayRunRaw = Aeson.object []
                            }
                baseClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                let client =
                        baseClient
                            { fetchPayRuns = \_ _ _ -> pure (Right [postedPayRun])
                            }

                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction RunXeroTimesheetPreparationAction
                preparationRunBeforeSelect <- query @XeroTimesheetPreparationRun |> fetchOne
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction preparationRunBeforeSelect.id)
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Readiness validation"
                response `responseBodyShouldContain` "posted"
                response `responseBodyShouldContain` "Draft timesheet creation is blocked"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` XeroTimesheetPreparationRunStatusEnumBlocked
                preparationRun.xeroPayRunId `shouldBe` Just "payrun-posted"
                preparationRun.remotePayRunsJson `shouldSatisfy` Preview.jsonContainsKey "remotePayRuns"

        it "blocks guided Xero preparation when a remote timesheet already exists for the included employee and period" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                markOtherFixtureStaffNotPaid fixture
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                let remoteTimesheet =
                        XeroTimesheetRef
                            { xeroTimesheetId = Just "ts-existing"
                            , xeroTimesheetEmployeeId = "employee-a"
                            , xeroTimesheetStartDate = fixture.periodStart
                            , xeroTimesheetEndDate = fixture.periodEnd
                            , xeroTimesheetStatus = Just "APPROVED"
                            , xeroTimesheetHours = Nothing
                            , xeroTimesheetLines = []
                            , xeroTimesheetRaw = Aeson.object []
                            }
                baseClient <- referenceSyncXeroClientForFixture (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) fixture.connection
                let client =
                        baseClient
                            { fetchTimesheets = \_ _ _ -> pure (Right [remoteTimesheet])
                            }

                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction RunXeroTimesheetPreparationAction
                preparationRunBeforeSelect <- query @XeroTimesheetPreparationRun |> fetchOne
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams (SelectXeroTimesheetPreparationPeriodAction preparationRunBeforeSelect.id)
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Readiness validation"
                response `responseBodyShouldContain` "Xero already has a non-draft timesheet for this employee and period"
                response `responseBodyShouldContain` "Update or delete it in Xero before continuing"
                response `responseBodyShouldNotContain` "Submit draft timesheets to Xero"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` XeroTimesheetPreparationRunStatusEnumBlocked
                preparationRun.remoteTimesheetsJson `shouldSatisfy` Preview.jsonContainsKey "remoteTimesheets"
                preparationRun.readinessSnapshotJson `shouldSatisfy` Preview.jsonContainsKey "blockers"

        it "rejects missing, malformed, and repeated nominal preparation payloads without mutation" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                run <- createPreparationRunForFixture fixture NeedsApproval
                accountSelectionBefore <-
                    query @XeroPayItemAccountCodeSelection
                        |> filterWhere (#venueId, unpackId fixture.venue.id)
                        |> fetchOneOrNothing
                let callWith params action =
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams action params

                missingPeriod <- callWith [] (SelectXeroTimesheetPreparationPeriodAction run.id)
                malformedStaff <-
                    callWith
                        [ ("staffId", "not-a-uuid")
                        , ("decision", "select_employee")
                        , ("xeroEmployeeSelection", "employee-1")
                        ]
                        (ApplyXeroTimesheetPreparationStaffDecisionAction run.id)
                missingStaff <-
                    callWith
                        [ ("decision", "select_employee")
                        , ("xeroEmployeeSelection", "employee-1")
                        ]
                        (ApplyXeroTimesheetPreparationStaffDecisionAction run.id)
                malformedReferenceWait <-
                    callWith
                        [ ("referenceWaitStartedAt", "not-a-timestamp")
                        , ("referenceDemand", "detect")
                        ]
                        RunXeroTimesheetPreparationAction
                repeatedAccountCode <-
                    callWith
                        [("accountCode", "200"), ("accountCode", "477")]
                        (ApproveXeroTimesheetPreparationPayItemsAction run.id)

                missingPeriod `responseStatusShouldBe` status200
                missingPeriod `responseBodyShouldContain` "periodKey is required by the Surface request contract"
                malformedStaff `responseStatusShouldBe` status200
                malformedStaff `responseBodyShouldContain` "staffId must be a UUID"
                missingStaff `responseStatusShouldBe` status200
                missingStaff `responseBodyShouldContain` "staffId is required by the Surface request contract"
                malformedReferenceWait `responseStatusShouldBe` status200
                malformedReferenceWait `responseBodyShouldContain` "referenceWaitStartedAt must be a UTC timestamp"
                repeatedAccountCode `responseStatusShouldBe` status200
                repeatedAccountCode `responseBodyShouldContain` "accountCode must be submitted once"
                refreshedRun <- fetch run.id
                refreshedRun.selectedPeriodKey `shouldBe` run.selectedPeriodKey
                refreshedRun.status `shouldBe` run.status
                refreshedRun.updatedAt `shouldBe` run.updatedAt
                accountSelectionAfter <-
                    query @XeroPayItemAccountCodeSelection
                        |> filterWhere (#venueId, unpackId fixture.venue.id)
                        |> fetchOneOrNothing
                accountSelectionAfter `shouldBe` accountSelectionBefore
                query @XeroTimesheetPreparationDecision |> fetchCount `shouldReturn` 0

        it "persists not-paid decisions from the guided preparation modal" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                mappings <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetch
                forM_ mappings \mapping ->
                    mapping
                        |> set #mappingStatus XeroStaffMappingStatusEnumStale
                        |> updateRecord
                        >>= const (pure ())
                run <- createPreparationRunForFixture fixture NeedsApproval

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ApplyXeroTimesheetPreparationStaffDecisionAction run.id)
                            [ ("staffId", idToParam fixture.staffA.id)
                            , ("decision", "select_employee")
                            , ("xeroEmployeeSelection", "not_applicable")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Persistently marked as not paid through Xero."
                matchedResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ShowXeroTimesheetPreparationStaffMappingsFragmentAction run.id)
                            [ ("showMatched", "true")
                            , ("editStaffId", idToParam fixture.staffA.id)
                            ]
                matchedResponse `responseStatusShouldBe` status200
                matchedResponse `responseBodyShouldContain` "Not paid through Xero"
                matchedResponse `responseBodyShouldContain` "value=\"not_applicable\" selected"
                matchedResponse `responseBodyShouldNotContain` "value=\"\""
                matchedResponse `responseBodyShouldNotContain` "Choose Xero employee"
                matchedResponse `responseBodyShouldNotContain` "Edit"
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetchOne
                mapping.mappingStatus `shouldBe` NotApplicable
                mapping.xeroEmployeeId `shouldBe` Nothing
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, StaffNotPaid) |> fetchOne
                decision.decisionStatus `shouldBe` Applied
                decision.decidedByUserId `shouldBe` Just (unpackId fixture.owner.id)

        it "blocks non-owner venue roles from Xero preparation page and actions" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                manager <- createUserRecord "xero-timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord fixture.venue manager Manager

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callAction XeroAction
                openPreparationResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callActionWithParams OpenXeroTimesheetPreparationAction
                        [("periodKey", fixturePeriodKey fixture)]
                runPreparationResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callActionWithParams RunXeroTimesheetPreparationAction
                        [("periodKey", fixturePeriodKey fixture)]

                pageResponse `responseStatusShouldBe` status302
                openPreparationResponse `responseStatusShouldBe` status302
                runPreparationResponse `responseStatusShouldBe` status302
                runCount <- query @XeroSubmissionRun |> fetchCount
                runCount `shouldBe` 0
                preparationRunCount <- query @XeroTimesheetPreparationRun |> fetchCount
                preparationRunCount `shouldBe` 0

        it "records Xero payroll reference sync failures without storing stale rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Sync Failure Venue"
                admin <- createUserRecordWithPlatformRole "xero-sync-failure@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                connection <- createSyncableXeroConnection venue admin

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (failingRefreshXeroClient "refresh denied") do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                employeeCount <- query @XeroEmployee |> fetchCount
                employeeCount `shouldBe` 0
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed
                syncRun.errorMessage `shouldBe` Just "Xero refresh_access sync failed: provider request could not be completed."
                updatedConnection <- fetch connection.id
                updatedConnection.lastError `shouldBe` Just "Xero refresh_access sync failed: provider request could not be completed."

        it "marks Xero connections as reconnect required when refresh tokens expire" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Expired Refresh Venue"
                owner <- createUserRecordWithPlatformRole "xero-expired-refresh@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (failingRefreshXeroClient "{\"error\":\"invalid_grant\",\"error_description\":\"Refresh token has expired\"}") do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "reauthorization_required"
                updatedConnection.encryptedAccessToken `shouldBe` Nothing
                updatedConnection.lastError `shouldSatisfy` maybe False ("refresh token expired" `Text.isInfixOf`)
                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction
                pageResponse `responseBodyShouldContain` "reconnect required"
                pageResponse `responseBodyShouldContain` "Xero needs to be reconnected before sync can continue."
                pageResponse `responseBodyShouldNotContain` "Draft timesheet submission"
                pageResponse `responseBodyShouldNotContain` "id=\"xero-timesheets-data\""

        it "sends HTMX sync requests into the reconnect flow when the refresh token is expired" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero HTMX Expired Refresh Venue"
                owner <- createUserRecordWithPlatformRole "xero-htmx-expired-refresh@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (failingRefreshXeroClient "{\"error\":\"invalid_grant\",\"error_description\":\"Refresh token has expired\"}") do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status200
                responseHeaders response `shouldSatisfy` any (\(name, value) ->
                    let redirectTarget = cs value :: String
                     in name == "HX-Redirect" && "login.xero.com" `List.isInfixOf` redirectTarget && "state=" `List.isInfixOf` redirectTarget
                    )
                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "reauthorization_required"
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` XeroSyncStatusEnumFailed
                [referenceJob] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                referenceJob.status `shouldBe` JobStatusFailed
                stateCount <- query @XeroOauthState |> fetchCount
                stateCount `shouldBe` 1

        it "queues reference sync from OAuth without requiring a follow-up browser request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Auto Sync After Connect Venue"
                owner <- createUserRecord "xero-auto-sync-after-connect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                oauthState <- createTestXeroOauthState venue owner "auto-sync-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "auto-sync-access-token" "auto-sync-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-auto-sync" "tenant-auto-sync" (Just "Auto Sync Demo Company")

                callbackResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "auto-sync-code")]

                callbackResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders callbackResponse) `shouldBe` Just "http://localhost/Xero"
                [initialSyncJob] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                initialSyncJob.status `shouldBe` JobStatusNotStarted
                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams XeroAction [("syncAfterConnect", "true")]
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldNotContain` "id=\"xero-auto-reference-sync\""
                pageResponse `responseBodyShouldNotContain` "hx-trigger=\"load\""

        it "rejects reconnect callbacks when Xero returns a different tenant" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Wrong Tenant Reconnect Venue"
                owner <- createUserRecord "xero-wrong-tenant-reconnect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner >>= \record ->
                    record
                        |> set #connectionStatus "reauthorization_required"
                        |> set #lastError (Just "Expired refresh token")
                        |> updateRecord
                oauthState <- createTestXeroOauthState venue owner "wrong-tenant-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "wrong-tenant-access-token" "wrong-tenant-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-other" "tenant-other" (Just "Other Demo Company")

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "wrong-tenant-code")]

                response `responseStatusShouldBe` status302
                retainedConnection <- fetch connection.id
                retainedConnection.connectionStatus `shouldBe` "reauthorization_required"
                retainedConnection.tenantId `shouldBe` "tenant-existing"
                retainedConnection.tenantName `shouldBe` Just "Existing Demo Company"
                retainedConnection.lastError `shouldBe` Just "Expired refresh token"
                decryptXeroToken testXeroConfig.tokenEncryptionKey retainedConnection.encryptedRefreshToken `shouldBe` Right "existing-refresh-token"
                updatedState <- fetch oauthState.id
                updatedState.consumedAt `shouldSatisfy` isJust
                [auditEvent] <- query @AuditEvent |> filterWhere (#eventType, "xero_connection_failed" :: Text) |> fetch
                let failure = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "failure")) auditEvent.payload
                failure `shouldSatisfy` maybe False ("Reconnect must authorize Existing Demo Company" `Text.isInfixOf`)

        it "repairs an existing same-tenant Xero connection during reconnect" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Reconnect Repair Venue"
                owner <- createUserRecord "xero-reconnect-repair@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                connection <- createSyncableXeroConnection venue owner
                staleConnection <-
                    connection
                        |> set #connectionStatus "reauthorization_required"
                        |> set #lastError (Just "Expired refresh token")
                        |> updateRecord
                staff <- createStaffRecord venue (Just owner) "Mapped" "Worker"
                _ <- newRecord @XeroStaffMapping
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId staff.id)
                    |> set #xeroConnectionId (unpackId staleConnection.id)
                    |> set #xeroEmployeeId (Just "employee-existing")
                    |> set #mappingStatus XeroStaffMappingStatusEnumVerified
                    |> createRecord
                oauthState <- createTestXeroOauthState venue owner "repair-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "repair-access-token" "repair-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-repaired" "tenant-existing" (Just "Existing Demo Company")

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "repair-code")]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Xero"
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 1
                repaired <- fetch staleConnection.id
                repaired.connectionStatus `shouldBe` "active"
                repaired.xeroConnectionRemoteId `shouldBe` Just "connection-repaired"
                repaired.lastError `shouldBe` Nothing
                [repairSyncJob] <- query @AppJob |> filterWhere (#jobKind, xeroReferenceSyncJobKind) |> fetch
                repairSyncJob.relatedId `shouldBe` Just (unpackId repaired.id)
                repairSyncJob.dedupeKey `shouldBe` Just (xeroReferenceSyncDedupeKey repaired)
                mapping <- query @XeroStaffMapping |> fetchOne
                mapping.xeroConnectionId `shouldBe` unpackId staleConnection.id

        it "rejects non-admin Xero connection actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Non Admin Venue"
                manager <- createUserRecord "xero-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                oauthState <- createTestXeroOauthState venue manager "manager-state" 600 Nothing
                connection <- createActiveXeroConnection venue manager

                startResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction StartXeroConnectionAction
                callbackResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "code")]
                disconnectResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction DisconnectXeroConnectionAction

                startResponse `responseStatusShouldBe` status302
                callbackResponse `responseStatusShouldBe` status302
                disconnectResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders startResponse) `shouldBe` Just "http://localhost/RosterWeeks"
                lookup "Location" (responseHeaders callbackResponse) `shouldBe` Just "http://localhost/RosterWeeks"
                lookup "Location" (responseHeaders disconnectResponse) `shouldBe` Just "http://localhost/RosterWeeks"
                retainedConnection <- fetch connection.id
                retainedConnection.connectionStatus `shouldBe` "active"


