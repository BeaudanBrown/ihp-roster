module Test.Controller.Admin.XeroSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
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

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "AdminController Xero" do
        it "shows the Xero page as not connected" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Admin Venue"
                admin <- createUserRecord "xero-admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"

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
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createXeroConnectionRecord venue owner "xero-shell-read-boundary-tenant"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Upload timesheets"
                response `responseBodyShouldContain` "Import pay items"
                response `responseBodyShouldContain` "Sync Xero data"
                response `responseBodyShouldContain` "hx-post=\"/SyncXeroPayrollReferenceData\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"sync-xero-payroll-reference-data\""
                response `responseBodyShouldContain` "hx-swap=\"none\""
                response `responseBodyShouldNotContain` "hx-trigger=\"load\""
                response `responseBodyShouldNotContain` "xero-staff-mappings-data"
                response `responseBodyShouldNotContain` "xero-pay-items-data"
                response `responseBodyShouldNotContain` "xero-timesheets-data"
                mappingCount <- query @XeroStaffMapping |> fetchCount
                payItemRequirementCount <- query @XeroPayItemRequirementRecord |> fetchCount
                mappingCount `shouldBe` 0
                payItemRequirementCount `shouldBe` 0

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
                _ <- createVenueMembershipRecord venue admin "venue_owner"

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
                _ <- createVenueMembershipRecord venue admin "venue_owner"

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
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Xero?syncAfterConnect=true"
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

        it "completes Xero OAuth callback through the strict localhost Xero mock" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Mock Callback Venue"
                admin <- createUserRecord "xero-mock-callback@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                _ <- createVenueMembershipRecord venue owner "venue_owner"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                admin <- createUserRecord "xero-sync@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                accountCodeSelection.selectionStatus `shouldBe` "verified"
                accountCodeSelection.accountCode `shouldBe` Just "477"
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` "succeeded"
                syncRun.employeesCount `shouldBe` 1
                syncRun.earningsRatesCount `shouldBe` 1
                syncRun.payrollCalendarsCount `shouldBe` 1
                updatedConnection <- fetch connection.id
                updatedConnection.lastSyncAt `shouldSatisfy` isJust
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "new-refresh-token"

        it "syncs Xero payroll reference data over HTMX with actor-local shell invalidation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero HTMX Sync Venue"
                admin <- createUserRecord "xero-htmx-sync@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                admin <- createUserRecord "xero-multiple-defaults@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                accountCodeSelection.selectionStatus `shouldBe` "verified"
                accountCodeSelection.accountCode `shouldBe` Just "477"
                payrollCalendarCount <- query @XeroPayrollCalendar |> fetchCount
                payrollCalendarCount `shouldBe` 2

        it "syncs Xero payroll reference data through the strict localhost Xero mock" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Mock Sync Venue"
                admin <- createUserRecord "xero-mock-sync@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
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
                syncRun.syncStatus `shouldBe` "succeeded"
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
                _ <- createSubmissionRunForFixture fixture "submitted"

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowadminXeroShellLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"periodKey\""
                response `responseBodyShouldNotContain` "submitted already"

        it "uses the latest local Xero submission run status for a pay period" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                older <- createSubmissionRunForFixture fixture "failed"
                newer <- createSubmissionRunForFixture fixture "submitted"
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
                        |> set #status ("submitted" :: Text)
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
                preparationRun.status `shouldBe` "ready_for_preview"
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
                pendingStaffDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_auto_match" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
                pendingStaffDecisions `shouldBe` 2
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "needs_approval"

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
                appliedStaffDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_auto_match" :: Text) |> filterWhere (#decisionStatus, "applied" :: Text) |> fetchCount
                appliedStaffDecisions `shouldBe` 2
                staffStepApprovals <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_step_approved" :: Text) |> filterWhere (#decisionStatus, "applied" :: Text) |> fetchCount
                staffStepApprovals `shouldBe` 0

        it "applies the selected suggested employee through the unified preparation dropdown" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
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
                mapping.mappingStatus `shouldBe` "verified"
                mapping.xeroEmployeeId `shouldBe` Just "employee-a"
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_auto_match" :: Text) |> fetchOne
                decision.decisionStatus `shouldBe` "applied"
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
                payItemResponse `responseBodyShouldContain` " - PERM - Bepis - Undated"
                payItemResponse `responseBodyShouldNotContain` "Approve creation"
                payItemResponse `responseBodyShouldNotContain` "Earnings-rate mappings"
                payItemResponse `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                pendingPayItemDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "pay_item_create" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
                pendingPayItemDecisions `shouldSatisfy` (> 0)
                refreshedPreparationRun <- fetch preparationRun.id
                refreshedPreparationRun.status `shouldBe` "ready_for_preview"

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
                pendingAfterApproval <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "pay_item_create" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
                pendingAfterApproval `shouldBe` 0

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
                refreshedRun.status `shouldBe` "submitted"
                submissionRun <- query @XeroSubmissionRun |> filterWhere (#status, "submitted" :: Text) |> fetchOne
                submissionRun.status `shouldBe` "submitted"
                pendingPayItemDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "pay_item_create" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
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
                refreshedRun.status `shouldNotBe` "submitted"

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
                preparationRun.status `shouldBe` "ready_for_preview"

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
                preparationRun.status `shouldBe` "blocked"
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
                preparationRun.status `shouldBe` "blocked"
                preparationRun.remoteTimesheetsJson `shouldSatisfy` Preview.jsonContainsKey "remoteTimesheets"
                preparationRun.readinessSnapshotJson `shouldSatisfy` Preview.jsonContainsKey "blockers"

        it "persists not-paid decisions from the guided preparation modal" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                mappings <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetch
                forM_ mappings \mapping ->
                    mapping
                        |> set #mappingStatus ("stale" :: Text)
                        |> updateRecord
                        >>= const (pure ())
                run <- createPreparationRunForFixture fixture "needs_approval"

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
                mapping.mappingStatus `shouldBe` "not_applicable"
                mapping.xeroEmployeeId `shouldBe` Nothing
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_not_paid" :: Text) |> fetchOne
                decision.decisionStatus `shouldBe` "applied"
                decision.decidedByUserId `shouldBe` Just (unpackId fixture.owner.id)

        it "blocks non-owner venue roles from Xero preparation page and actions" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                manager <- createUserRecord "xero-timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord fixture.venue manager "manager"

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
                admin <- createUserRecord "xero-sync-failure@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createSyncableXeroConnection venue admin

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (failingRefreshXeroClient "refresh denied") do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                employeeCount <- query @XeroEmployee |> fetchCount
                employeeCount `shouldBe` 0
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` "failed"
                syncRun.errorMessage `shouldBe` Just "Xero token refresh failed: refresh denied"
                updatedConnection <- fetch connection.id
                updatedConnection.lastError `shouldBe` Just "Xero token refresh failed: refresh denied"

        it "marks Xero connections as reconnect required when refresh tokens expire" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Expired Refresh Venue"
                owner <- createUserRecord "xero-expired-refresh@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
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
                owner <- createUserRecord "xero-htmx-expired-refresh@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
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
                syncRun.syncStatus `shouldBe` "failed"
                stateCount <- query @XeroOauthState |> fetchCount
                stateCount `shouldBe` 1

        it "returns from successful Xero OAuth with an automatic reference sync trigger" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Auto Sync After Connect Venue"
                owner <- createUserRecord "xero-auto-sync-after-connect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                oauthState <- createTestXeroOauthState venue owner "auto-sync-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "auto-sync-access-token" "auto-sync-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-auto-sync" "tenant-auto-sync" (Just "Auto Sync Demo Company")

                callbackResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "auto-sync-code")]

                callbackResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders callbackResponse) `shouldSatisfy` maybe False (Text.isInfixOf "/Xero?syncAfterConnect=true" . cs)
                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams XeroAction [("syncAfterConnect", "true")]
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "id=\"xero-auto-reference-sync\""
                pageResponse `responseBodyShouldContain` "hx-trigger=\"load\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/SyncXeroPayrollReferenceData\""
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-xero-fragment\""
                pageResponse `responseBodyShouldContain` "hx-push-url=\"/Xero\""
                pageResponse `responseBodyShouldContain` "hx-indicator=\"#xero-connection-status-badge\""

        it "rejects reconnect callbacks when Xero returns a different tenant" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Wrong Tenant Reconnect Venue"
                owner <- createUserRecord "xero-wrong-tenant-reconnect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
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
                _ <- createVenueMembershipRecord venue owner "venue_owner"
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
                    |> set #mappingStatus "verified"
                    |> createRecord
                oauthState <- createTestXeroOauthState venue owner "repair-state" 600 Nothing
                let tokenResponse = XeroTokenResponse "repair-access-token" "repair-refresh-token" 1800 (Just requiredXeroScopesText)
                let tenant = XeroTenant "connection-repaired" "tenant-existing" (Just "Existing Demo Company")

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callActionWithParams XeroOAuthCallbackAction [("state", cs oauthState.stateToken), ("code", "repair-code")]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Xero?syncAfterConnect=true"
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 1
                repaired <- fetch staleConnection.id
                repaired.connectionStatus `shouldBe` "active"
                repaired.xeroConnectionRemoteId `shouldBe` Just "connection-repaired"
                repaired.lastError `shouldBe` Nothing
                mapping <- query @XeroStaffMapping |> fetchOne
                mapping.xeroConnectionId `shouldBe` unpackId staleConnection.id

        it "rejects non-admin Xero connection actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Non Admin Venue"
                manager <- createUserRecord "xero-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
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


