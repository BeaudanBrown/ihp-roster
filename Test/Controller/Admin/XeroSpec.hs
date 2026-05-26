module Test.Controller.Admin.XeroSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
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
import qualified Data.Set as Set
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
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
import qualified Test.XeroMock as XeroMock
import qualified Test.XeroTimesheetPreviewSpec as Preview
import Web.Admin.Xero.Mutations (xeroConnectionTouchedResources,
                                 xeroMappingsTouchedResources,
                                 xeroPayItemsTouchedResources,
                                 xeroReferenceSyncTouchedResources,
                                 xeroTimesheetsTouchedResources)
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "AdminController" do
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
                response `responseBodyShouldContain` "admin_xero"
                response `responseBodyShouldContain` "Connection status"
                response `responseBodyShouldNotContain` "Status:"
                response `responseBodyShouldNotContain` "app-accordion-section-header"
                response `responseBodyShouldNotContain` "Staff mappings"

                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "id=\"admin-xero-fragment\""
                fragmentResponse `responseBodyShouldContain` "not connected"
                fragmentResponse `responseBodyShouldNotContain` "Staff mappings"
                fragmentResponse `responseBodyShouldNotContain` "id=\"app\""

        it "records touched resources for Xero connection mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Connection Touch Venue"

                Set.fromList (xeroConnectionTouchedResources venue.id)
                    `shouldBe` Set.fromList [XeroConnectionResource (unpackId venue.id)]

        it "records touched resources for Xero mapping mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Mapping Touch Venue"

                Set.fromList (xeroMappingsTouchedResources venue.id)
                    `shouldBe` Set.fromList [XeroMappingsResource (unpackId venue.id)]

        it "records touched resources for Xero pay item mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Touched Venue"

                Set.fromList (xeroPayItemsTouchedResources venue.id)
                    `shouldBe` Set.fromList [XeroPayItemsResource (unpackId venue.id)]

        it "records touched resources for Xero timesheet mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Timesheet Touch Venue"

                Set.fromList (xeroTimesheetsTouchedResources venue.id)
                    `shouldBe` Set.fromList [XeroTimesheetsResource (unpackId venue.id)]

        it "records touched resources for Xero reference sync mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Reference Touch Venue"

                Set.fromList (xeroReferenceSyncTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [ XeroConnectionResource (unpackId venue.id)
                        , XeroMappingsResource (unpackId venue.id)
                        ]

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
                            (Just "calendar-1")
                            (Aeson.object ["EmployeeID" Aeson..= ("employee-1" :: Text)])
                        ]
                let earningsRates =
                        [ XeroEarningsRateRef
                            "earnings-1"
                            "Ordinary Hours"
                            (Just "REGULAR")
                            (Just "RATEPERUNIT")
                            (Just "477")
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
                pageResponse `responseBodyShouldContain` "admin_xero"
                pageResponse `responseBodyShouldContain` "admin_xero_timesheets"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-xero-fragment\""
                pageResponse `responseBodyShouldContain` "hx-indicator=\"#xero-reference-sync-indicator\""
                pageResponse `responseBodyShouldContain` "id=\"xero-reference-sync-indicator\""
                pageResponse `responseBodyShouldContain` "id=\"xero-timesheets-data\""
                pageResponse `responseBodyShouldContain` "id=\"xero-timesheet-submission-indicator\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/OpenXeroTimesheetPreparation\""
                pageResponse `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                pageResponse `responseBodyShouldContain` "hx-indicator=\"#xero-timesheet-submission-indicator\""
                pageResponse `responseBodyShouldNotContain` "Tenant ID"
                pageResponse `responseBodyShouldNotContain` "Connected</dt>"
                pageResponse `responseBodyShouldNotContain` "Last sync:"

                xeroVersionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callAction SyncXeroPayrollReferenceDataAction

                response `responseStatusShouldBe` status302
                xeroVersionAfter <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                xeroVersionAfter `shouldBe` (xeroVersionBefore + 2)
                employeeCount <- query @XeroEmployee |> fetchCount
                employeeCount `shouldBe` 1
                syncedEmployee <- query @XeroEmployee |> fetchOne
                syncedEmployee.payrollCalendarId `shouldBe` Just "calendar-1"
                earningsRateCount <- query @XeroEarningsRate |> fetchCount
                earningsRateCount `shouldBe` 1
                payrollCalendarCount <- query @XeroPayrollCalendar |> fetchCount
                payrollCalendarCount `shouldBe` 1
                accountCodeSelection <- query @XeroPayItemAccountCodeSelection |> fetchOne
                accountCodeSelection.selectionStatus `shouldBe` "verified"
                accountCodeSelection.accountCode `shouldBe` Just "477"
                calendarSelection <- query @XeroPayrollCalendarSelection |> fetchOne
                calendarSelection.calendarStatus `shouldBe` "verified"
                calendarSelection.xeroPayrollCalendarId `shouldBe` Just "calendar-1"
                calendarSelection.xeroPayrollCalendarName `shouldBe` Just "Weekly"
                syncRun <- query @XeroSyncRun |> fetchOne
                syncRun.syncStatus `shouldBe` "succeeded"
                syncRun.employeesCount `shouldBe` 1
                syncRun.earningsRatesCount `shouldBe` 1
                syncRun.payrollCalendarsCount `shouldBe` 1
                updatedConnection <- fetch connection.id
                updatedConnection.lastSyncAt `shouldSatisfy` isJust
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "new-refresh-token"

        it "does not auto-select Xero setup defaults when sync returns multiple options" $ withContext do
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
                            True
                            (Aeson.object ["EarningsRateID" Aeson..= ("earnings-1" :: Text)])
                        , XeroEarningsRateRef
                            "earnings-2"
                            "Saturday Hours"
                            (Just "REGULAR")
                            (Just "RATEPERUNIT")
                            (Just "478")
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
                accountCodeSelectionCount <- query @XeroPayItemAccountCodeSelection |> fetchCount
                accountCodeSelectionCount `shouldBe` 0
                calendarSelectionCount <- query @XeroPayrollCalendarSelection |> fetchCount
                calendarSelectionCount `shouldBe` 0

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

        it "shows Xero staff mapping only after employees have synced" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Staff Mapping Visibility Venue"
                admin <- createUserRecord "xero-staff-mapping-visibility@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                _ <- createStaffRecord venue Nothing "Local" "Worker"

                unsyncedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                unsyncedResponse `responseStatusShouldBe` status200
                unsyncedResponse `responseBodyShouldContain` "Staff mappings"
                unsyncedResponse `responseBodyShouldContain` "Sync payroll reference data before mapping staff to Xero employees."
                unsyncedResponse `responseBodyShouldNotContain` "name=\"xeroEmployeeSelection\""

                _ <- createXeroEmployeeRecord connection "Local Worker" (Just "local@example.com") "employee-local"
                syncedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                syncedResponse `responseStatusShouldBe` status200
                syncedResponse `responseBodyShouldContain` "Staff mappings"
                syncedResponse `responseBodyShouldContain` "Local Worker - local@example.com"
                syncedResponse `responseBodyShouldNotContain` "Possible Xero match: Local Worker"
                syncedResponse `responseBodyShouldContain` "name=\"xeroEmployeeSelection\""
                syncedResponse `responseBodyShouldContain` "Show matched"
                syncedResponse `responseBodyShouldContain` "xero-staff-mapping-show-matched-toggle"
                syncedResponse `responseBodyShouldContain` "id=\"xero-staff-mappings\""
                syncedResponse `responseBodyShouldContain` "id=\"xero-staff-mappings-data\""
                syncedResponse `responseBodyShouldContain` ">Match</button>"
                syncedResponse `responseBodyShouldContain` "hx-target=\"#admin-xero-fragment\""
                syncedResponse `responseBodyShouldContain` "hx-trigger=\"change\""
                syncedResponse `responseBodyShouldContain` "hx-swap=\"none\""
                syncedResponse `responseBodyShouldContain` "id=\"xero-staff-mapping-counts\""
                syncedResponse `responseBodyShouldNotContain` "id=\"xero-staff-mapping-counts\" class=\"d-flex flex-wrap gap-2\" hx-swap-oob="
                syncedResponse `responseBodyShouldNotContain` "data-preserve-window-scroll=\"true\""
                syncedResponse `responseBodyShouldNotContain` "<th>Status</th>"
                syncedResponse `responseBodyShouldNotContain` "<th class=\"text-end\">Current</th>"
                syncedResponse `responseBodyShouldNotContain` ">Save</button>"
                syncedResponse `responseBodyShouldContain` "2 not paid through Xero"
                syncedResponse `responseBodyShouldContain` "1 possible matches"

        it "saves Xero staff mappings and not-paid-through-Xero states from the admin fragment" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Staff Mapping Venue"
                admin <- createUserRecord "xero-staff-mapping@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                staff <- createStaffRecord venue Nothing "Ada" "Lovelace"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                employee <- createXeroEmployeeRecord connection "Ada Lovelace" (Just "ada@example.com") "employee-ada"

                versionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams SaveXeroStaffMappingAction
                            [ ("staffId", idToParam staff.id)
                            , ("xeroEmployeeSelection", "employee-ada")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                response `responseBodyShouldNotContain` "id=\"xero-staff-mappings\""
                response `responseBodyShouldNotContain` "id=\"xero-staff-mappings-data\""
                response `responseBodyShouldNotContain` "xero-staff-mapping-show-matched-toggle"
                response `responseBodyShouldContain` "Saved Xero employee mapping for Ada Lovelace."
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "app-live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin_xero_staff_mappings")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "xero-staff-mappings-data")
                triggerHeader `shouldSatisfy` maybe True (not . Text.isInfixOf "\"targetId\":\"xero-staff-mappings\"")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "/ShowAdminXeroStaffMappingsFragment")
                versionAfter <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` (versionBefore + 1)
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId staff.id) |> fetchOne
                mapping.mappingStatus `shouldBe` "verified"
                mapping.xeroEmployeeId `shouldBe` Just employee.xeroEmployeeId
                mapping.xeroEmployeeName `shouldBe` Just employee.displayName
                mapping.lastVerifiedAt `shouldSatisfy` isJust
                mappingResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroStaffMappingsFragmentAction
                mappingResponse `responseStatusShouldBe` status200
                mappingResponse `responseBodyShouldContain` "id=\"xero-staff-mappings-data\""
                mappingResponse `responseBodyShouldNotContain` "id=\"xero-staff-mappings\""
                mappingResponse `responseBodyShouldNotContain` "xero-staff-mapping-show-matched-toggle"
                mappingResponse `responseBodyShouldContain` "id=\"xero-staff-mapping-counts\""
                mappingResponse `responseBodyShouldContain` "xero-staff-mapping-row-matched"
                mappingResponse `responseBodyShouldContain` ("id=\"xero-staff-mapping-control-" <> tshow staff.id <> "\"")
                mappingResponse `responseBodyShouldContain` ("id=\"xero-staff-mapping-control-" <> tshow trialStaff.id <> "\"")
                mappingResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                mappingBody <- responseBody mappingResponse
                let mappingText = cs mappingBody
                let beforeMatchedAdaInMutation = fst (Text.breakOn "Ada Lovelace" mappingText)
                beforeMatchedAdaInMutation `shouldSatisfy` Text.isInfixOf "Trial Worker"
                fullFragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                fullFragmentResponse `responseBodyShouldContain` "xero-staff-mapping-row-matched"
                fullFragmentBody <- responseBody fullFragmentResponse
                let fullFragmentText = cs fullFragmentBody
                let beforeMatchedAda = fst (Text.breakOn "Ada Lovelace" fullFragmentText)
                beforeMatchedAda `shouldSatisfy` Text.isInfixOf "Trial Worker"

                duplicateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams SaveXeroStaffMappingAction
                            [ ("staffId", idToParam trialStaff.id)
                            , ("xeroEmployeeSelection", "employee-ada")
                            ]

                duplicateResponse `responseStatusShouldBe` status200
                duplicateResponse `responseBodyShouldContain` "That Xero employee is already mapped to another staff member."
                duplicateCount <-
                    query @XeroStaffMapping
                        |> filterWhere (#xeroEmployeeId, Just employee.xeroEmployeeId)
                        |> filterWhere (#mappingStatus, "verified")
                        |> fetchCount
                duplicateCount `shouldBe` 1

                notApplicableResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams SaveXeroStaffMappingAction
                            [ ("staffId", idToParam trialStaff.id)
                            , ("xeroEmployeeSelection", "not_applicable")
                            ]

                notApplicableResponse `responseStatusShouldBe` status200
                trialMapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId trialStaff.id) |> fetchOne
                trialMapping.mappingStatus `shouldBe` "not_applicable"
                trialMapping.xeroEmployeeId `shouldBe` Nothing

        it "suggests the closest available Xero employee for a staff member" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Staff Suggestion Venue"
                admin <- createUserRecord "xero-staff-suggestion@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                staff <- createStaffRecord venue Nothing "Ada" "Lovelace"
                _ <- createXeroEmployeeRecord connection "Ava Lovelace" Nothing "employee-ava"
                employee <- createXeroEmployeeRecord connection "Ada Lovelace" Nothing "employee-ada"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (SuggestXeroStaffMappingAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Saved Xero employee mapping for Ada Lovelace."
                response `responseBodyShouldNotContain` "id=\"xero-staff-mappings\""
                response `responseBodyShouldNotContain` "id=\"xero-staff-mappings-data\""
                response `responseBodyShouldNotContain` "xero-staff-mapping-show-matched-toggle"
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "app-live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin_xero_staff_mappings")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "xero-staff-mappings-data")
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId staff.id) |> fetchOne
                mapping.mappingStatus `shouldBe` "verified"
                mapping.xeroEmployeeId `shouldBe` Just employee.xeroEmployeeId

        it "rejects weak or ambiguous Xero employee suggestions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Staff Weak Suggestion Venue"
                admin <- createUserRecord "xero-staff-weak-suggestion@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                weakStaff <- createStaffRecord venue Nothing "Ada" "Lovelace"
                ambiguousStaff <- createStaffRecord venue Nothing "John" "Smith"
                _ <- createXeroEmployeeRecord connection "Zoe Campbell" Nothing "employee-zoe"
                _ <- createXeroEmployeeRecord connection "Jon Smith" Nothing "employee-jon"
                _ <- createXeroEmployeeRecord connection "John Smyth" Nothing "employee-smyth"

                weakResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (SuggestXeroStaffMappingAction weakStaff.id)

                weakResponse `responseStatusShouldBe` status200
                weakResponse `responseBodyShouldContain` "No close Xero employee match found for Ada Lovelace."
                weakMapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId weakStaff.id) |> fetchOne
                weakMapping.mappingStatus `shouldBe` "not_applicable"

                ambiguousResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (SuggestXeroStaffMappingAction ambiguousStaff.id)

                ambiguousResponse `responseStatusShouldBe` status200
                ambiguousResponse `responseBodyShouldContain` "Xero employee match for John Smith is ambiguous"
                ambiguousMapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId ambiguousStaff.id) |> fetchOne
                ambiguousMapping.mappingStatus `shouldBe` "not_applicable"

        it "shows managed Xero pay items and saves setup selections from the admin fragment" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Earnings Mapping Venue"
                admin <- createUserRecord "xero-earnings-mapping@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                owner <- createUserRecord "xero-earnings-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                connection <- createActiveXeroConnection venue admin
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "Bepis - HIGA - PERM - Undated - Level 2 - Ordinary" "earnings-ordinary"
                _ <- createXeroEarningsRateRecord connection "Bepis - HIGA - PERM - Undated - Level 2 - Saturday Penalty" "earnings-saturday"
                payrollCalendar <- createXeroPayrollCalendarRecord connection "Weekly" "calendar-weekly"

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Pay item requirements"
                pageResponse `responseBodyShouldContain` "id=\"xero-pay-items-data\""
                pageResponse `responseBodyShouldContain` "admin_xero_pay_items"
                pageResponse `responseBodyShouldContain` "HIGA - PERM - Undated - Level 2 - Saturday Penalty"
                pageResponse `responseBodyShouldContain` "$39.3750/hr"
                pageResponse `responseBodyShouldContain` "Evening After 7pm Loading"
                pageResponse `responseBodyShouldContain` "$3.1500/hr"
                pageResponse `responseBodyShouldContain` "M-F Delayed Meal Break"
                pageResponse `responseBodyShouldContain` "$47.2500/hr"
                pageResponse `responseBodyShouldContain` "Saturday Delayed Meal Break"
                pageResponse `responseBodyShouldContain` "$55.1250/hr"
                pageResponse `responseBodyShouldContain` "matched"
                pageResponse `responseBodyShouldContain` "proposed"
                pageResponse `responseBodyShouldContain` "HIGA - PERM - Undated - Level 2 - Ordinary"
                pageResponse `responseBodyShouldNotContain` "Earnings-rate mappings"
                pageResponse `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                pageResponse `responseBodyShouldContain` "Pay item account code"
                pageResponse `responseBodyShouldContain` "name=\"xeroPayItemAccountCodeSelection\""
                pageResponse `responseBodyShouldNotContain` "xeroPayItemAccountCodeManual"
                pageResponse `responseBodyShouldContain` "Payroll calendar"
                pageResponse `responseBodyShouldContain` "Weekly - WEEKLY"
                pageResponse `responseBodyShouldContain` "name=\"xeroPayrollCalendarSelection\""
                pageResponse `responseBodyShouldContain` "Ready to submit checklist"
                payItemsFragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroPayItemsFragmentAction
                payItemsFragmentResponse `responseStatusShouldBe` status200
                payItemsFragmentResponse `responseBodyShouldContain` "id=\"xero-pay-items-data\""
                payItemsFragmentResponse `responseBodyShouldContain` "Create 6 missing pay items in Xero"
                payItemsFragmentResponse `responseBodyShouldContain` "hx-target=\"#xero-pay-items-data\""
                payItemsFragmentResponse `responseBodyShouldContain` "hx-indicator=\"#xero-pay-items-sync-indicator\""
                payItemsFragmentResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                saturdayRequirement <- query @XeroPayItemRequirementRecord |> filterWhere (#displayName, "Bepis - HIGA - PERM - Undated - Level 2 - Saturday Penalty") |> fetchOne
                saturdayRequirement.requirementStatus `shouldBe` "matched"
                saturdayRequirement.xeroEarningsRateName `shouldBe` Just "Bepis - HIGA - PERM - Undated - Level 2 - Saturday Penalty"
                saturdayRequirement.ratePerUnit `shouldBe` Just 39.375
                eveningRequirement <- query @XeroPayItemRequirementRecord |> filterWhere (#displayName, "Bepis - HIGA - PERM - Undated - Level 2 - Evening After 7pm Loading") |> fetchOne
                eveningRequirement.requirementStatus `shouldBe` "proposed"
                eveningRequirement.ratePerUnit `shouldBe` Just 3.15
                delayedRequirement <- query @XeroPayItemRequirementRecord |> filterWhere (#displayName, "Bepis - HIGA - PERM - Undated - Level 2 - M-F Delayed Meal Break") |> fetchOne
                delayedRequirement.requirementStatus `shouldBe` "proposed"
                delayedRequirement.ratePerUnit `shouldBe` Just 47.25

                versionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                accountCodeResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams SaveXeroPayItemAccountCodeSelectionAction
                            [("xeroPayItemAccountCodeSelection", "477")]

                accountCodeResponse `responseStatusShouldBe` status200
                accountCodeResponse `responseBodyShouldContain` "Saved Xero pay item account code 477."
                versionAfterAccountCode <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                versionAfterAccountCode `shouldBe` (versionBefore + 1)
                accountCodeSelection <- query @XeroPayItemAccountCodeSelection |> fetchOne
                accountCodeSelection.selectionStatus `shouldBe` "verified"
                accountCodeSelection.accountCode `shouldBe` Just "477"

                calendarResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams SaveXeroPayrollCalendarSelectionAction
                            [("xeroPayrollCalendarSelection", "calendar-weekly")]

                calendarResponse `responseStatusShouldBe` status200
                calendarResponse `responseBodyShouldContain` "Saved Xero payroll calendar selection."
                versionAfterCalendar <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                versionAfterCalendar `shouldBe` (versionAfterAccountCode + 1)
                selection <- query @XeroPayrollCalendarSelection |> fetchOne
                selection.calendarStatus `shouldBe` "verified"
                selection.xeroPayrollCalendarId `shouldBe` Just payrollCalendar.xeroPayrollCalendarId
                selection.xeroPayrollCalendarName `shouldBe` Just payrollCalendar.name

        it "creates missing managed Xero pay items and maps the created earnings rates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Create Venue"
                owner <- createUserRecord "xero-pay-item-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                connection <- createSyncableXeroConnection venue owner
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "Ordinary Hours" "earnings-existing"
                _ <- createXeroPayItemAccountCodeSelectionRecord connection "477"
                requestsRef <- IORef.newIORef []
                let tokenResponse = XeroTokenResponse "pay-item-access-token" "pay-item-refresh-token" 1800 (Just requiredXeroScopesText)

                versionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (payItemCreateXeroClient tokenResponse requestsRef) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction CreateMissingXeroPayItemsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Created and verified 8 missing Xero pay items."
                response `responseBodyShouldContain` "id=\"xero-pay-items-data\""
                response `responseBodyShouldContain` "id=\"xero-pay-items-sync-indicator\""
                response `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                requests <- IORef.readIORef requestsRef
                length requests `shouldBe` 8
                let ordinaryName = "Bepis - HIGA - PERM - Undated - Level 2 - Ordinary"
                let ordinaryKey = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId <> ":basis:permanent:effective:undated:ordinary"
                map fst requests `shouldSatisfy` all (Text.isPrefixOf "bepis-pay-item-")
                map fst requests `shouldSatisfy` \keys -> length (List.nub keys) == length keys
                map snd requests `shouldSatisfy` any (xeroPayItemRequestHas ordinaryName 31.50)
                map snd requests `shouldSatisfy` all xeroPayItemRequestOnlyTouchesEarningsRates
                createdRate <- query @XeroEarningsRate
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#name, ordinaryName)
                    |> fetchOne
                createdRate.xeroEarningsRateId `shouldBe` "created-Bepis - HIGA - PERM - Undated - Level 2 - Ordinary"
                createdRate.accountCode `shouldBe` Just "477"
                mapping <- query @XeroEarningsRateMapping
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#localBucketKey, ordinaryKey)
                    |> fetchOne
                mapping.mappingStatus `shouldBe` "verified"
                mapping.xeroEarningsRateId `shouldBe` Just createdRate.xeroEarningsRateId
                requirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, ordinaryKey)
                    |> fetchOne
                requirement.requirementStatus `shouldBe` "created"
                requirement.xeroEarningsRateId `shouldBe` Just createdRate.xeroEarningsRateId
                syncRun <- query @XeroSyncRun |> filterWhere (#syncKind, "pay_item_create" :: Text) |> fetchOne
                syncRun.syncStatus `shouldBe` "succeeded"
                syncRun.earningsRatesCount `shouldBe` 8
                versionAfter <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` (versionBefore + 2)

        it "reports pay item creates that are not present after the Xero verification pull" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Partial Verification Venue"
                owner <- createUserRecord "xero-pay-item-partial-verification@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                connection <- createSyncableXeroConnection venue owner
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "Ordinary Hours" "earnings-existing"
                _ <- createXeroPayItemAccountCodeSelectionRecord connection "477"
                requestsRef <- IORef.newIORef []
                let tokenResponse = XeroTokenResponse "pay-item-access-token" "pay-item-refresh-token" 1800 (Just requiredXeroScopesText)

                versionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef (Just 1)) do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction CreateMissingXeroPayItemsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Submitted 8 Xero pay item creates and verified 1 after pulling Xero pay items."
                response `responseBodyShouldContain` "id=\"xero-pay-items-data\""
                response `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                requests <- IORef.readIORef requestsRef
                length requests `shouldBe` 8
                createdRequirements <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementStatus, "created" :: Text)
                    |> fetch
                length createdRequirements `shouldBe` 1
                proposedRequirements <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementStatus, "proposed" :: Text)
                    |> fetch
                length proposedRequirements `shouldBe` 7
                verifiedMappings <- query @XeroEarningsRateMapping
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#mappingStatus, "verified" :: Text)
                    |> fetch
                length verifiedMappings `shouldBe` 1
                syncRun <- query @XeroSyncRun |> filterWhere (#syncKind, "pay_item_create" :: Text) |> fetchOne
                syncRun.syncStatus `shouldBe` "failed"
                syncRun.earningsRatesCount `shouldBe` 1
                versionAfter <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` (versionBefore + 2)

        it "continues creating pay items after Xero rejects one and reports the rejected item" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Create Error Venue"
                owner <- createUserRecord "xero-pay-item-create-error@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                connection <- createSyncableXeroConnection venue owner
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "Ordinary Hours" "earnings-existing"
                _ <- createXeroPayItemAccountCodeSelectionRecord connection "477"
                requestsRef <- IORef.newIORef []
                let tokenResponse = XeroTokenResponse "pay-item-access-token" "pay-item-refresh-token" 1800 (Just requiredXeroScopesText)

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (payItemCreateXeroClientFailingRequest tokenResponse requestsRef 2 "Xero validation failed: AccountCode is invalid for this earnings rate") do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction CreateMissingXeroPayItemsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Xero rejected 1 pay item creates."
                response `responseBodyShouldContain` "Xero validation failed: AccountCode is invalid for this earnings rate"
                requests <- IORef.readIORef requestsRef
                length requests `shouldBe` 8
                createdRequirements <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementStatus, "created" :: Text)
                    |> fetch
                length createdRequirements `shouldBe` 7

        it "shows current Xero pay item requirements first and keeps expired rates in the archive" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Archive Venue"
                admin <- createUserRecord "xero-pay-item-archive@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                _ <- createActiveXeroConnection venue admin
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                baseRate <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                    |> filterWhere (#employmentBasis, Permanent)
                    |> fetchOne
                _ <- baseRate
                    |> set #operativeFrom (Just (fromGregorian 2024 7 1))
                    |> set #operativeTo (Just (fromGregorian 2025 6 30))
                    |> updateRecord
                _ <- newRecord @AwardLevelBaseRate
                    |> set #awardLevelId (unpackId awardLevel.id)
                    |> set #employmentBasis Permanent
                    |> set #fwcMapdPayRateId baseRate.fwcMapdPayRateId
                    |> set #hourlyRate 32.00
                    |> set #rateLabel ("Current Permanent Hourly" :: Text)
                    |> set #operativeFrom (Just (fromGregorian 2025 7 1))
                    |> createRecord

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Create 6 missing pay items in Xero"
                pageResponse `responseBodyShouldContain` "Bepis - HIGA - PERM - 1-July-2025 - Level 2 - Ordinary"
                pageResponse `responseBodyShouldContain` "Archived pay item requirements (2)"
                pageResponse `responseBodyShouldContain` "Bepis - HIGA - PERM - 1-July-2024 - Level 2 - Ordinary"
                pageResponse `responseBodyShouldContain` "Bepis - HIGA - PERM - 1-July-2024 - Level 2 - M-F Delayed Meal Break"

        it "keeps Xero pay item requirement keys unique across employment bases" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Fallback Venue"
                admin <- createUserRecord "xero-pay-item-fallback@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                addCasualBaseAndSaturdayPenalty awardLevel 40.00 60.00
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createStaffUsingAwardLevel venue "Casual" "Worker" awardLevel Casual

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "HIGA - PERM - Undated - Level 2 - Saturday Penalty"
                pageResponse `responseBodyShouldContain` "HIGA - CAS - Undated - Level 2 - Saturday Penalty"

                let permanentKey = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId <> ":basis:permanent:effective:undated:penalty:saturday_penalty"
                let casualKey = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId <> ":basis:casual:effective:undated:penalty:saturday_penalty"
                permanentRequirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, permanentKey)
                    |> fetchOne
                casualRequirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, casualKey)
                    |> fetchOne
                permanentRequirement.ratePerUnit `shouldBe` Just 39.375
                casualRequirement.ratePerUnit `shouldBe` Just 60.00

        it "does not auto-match unrelated Xero earnings rates without the managed prefix" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Namespace Venue"
                admin <- createUserRecord "xero-pay-item-namespace@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "HIGA - PERM - Undated - Level 2 - Ordinary" "earnings-unmanaged-ordinary"

                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction

                let ordinaryKey = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId <> ":basis:permanent:effective:undated:ordinary"
                ordinaryRequirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, ordinaryKey)
                    |> fetchOne
                ordinaryRequirement.displayName `shouldBe` "Bepis - HIGA - PERM - Undated - Level 2 - Ordinary"
                ordinaryRequirement.requirementStatus `shouldBe` "proposed"
                ordinaryRequirement.xeroEarningsRateId `shouldBe` Nothing

        it "limits Xero pay item requirements to award levels and bases used by venue staff and shift types" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Used Scope Venue"
                admin <- createUserRecord "xero-pay-item-used-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                floorLevel <- createPayLevelRecordWithRates venue "Floor Level" 31.50 3.15 6.30 1 1.25 1.50
                kitchenLevel <- createPayLevelRecordWithRates venue "Kitchen Level" 40.00 4.00 8.00 1 1.25 1.50
                unusedLevel <- createPayLevelRecordWithRates venue "Unused Level" 50.00 5.00 10.00 1 1.25 1.50
                addCasualBaseAndSaturdayPenalty floorLevel 35.00 52.50
                addCasualBaseAndSaturdayPenalty kitchenLevel 45.00 67.50
                _ <- createStaffUsingAwardLevel venue "Floor" "Permanent" floorLevel Permanent
                _ <- createStaffUsingAwardLevel venue "Floor" "Casual" floorLevel Casual
                _ <- createShiftTypeRecord venue kitchenLevel "Kitchen"

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "HIGA - PERM - Undated - Floor Level - Ordinary"
                pageResponse `responseBodyShouldContain` "HIGA - CAS - Undated - Floor Level - Ordinary"
                pageResponse `responseBodyShouldContain` "HIGA - PERM - Undated - Kitchen Level - Ordinary"
                pageResponse `responseBodyShouldContain` "HIGA - CAS - Undated - Kitchen Level - Ordinary"
                pageResponse `responseBodyShouldNotContain` "Unused Level"

                let unusedKey = "xero:pay-item:classification:" <> tshow unusedLevel.classificationFixedId <> ":basis:permanent:effective:undated:ordinary"
                unusedCount <-
                    query @XeroPayItemRequirementRecord
                        |> filterWhere (#xeroConnectionId, unpackId connection.id)
                        |> filterWhere (#requirementKey, unusedKey)
                        |> fetchCount
                unusedCount `shouldBe` 0
                today <- utctDay <$> getCurrentTime
                buckets <- Preview.currentVenueBuckets venue today
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
                let bucketKeys = Set.fromList (map (\bucket -> bucket.localBucketKey) buckets)
                let requirementKeys = Set.fromList (map (\requirement -> requirement.requirementKey) requirements)
                bucketKeys `Set.isSubsetOf` requirementKeys `shouldBe` True

        it "flags matched Xero pay item requirements when the expected FWC rate changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Pay Item Rate Change Venue"
                admin <- createUserRecord "xero-pay-item-rate-change@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin
                awardLevel <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createStaffUsingAwardLevel venue "Permanent" "Worker" awardLevel Permanent
                _ <- createXeroEarningsRateRecord connection "Bepis - HIGA - PERM - Undated - Level 2 - Saturday Penalty" "earnings-saturday"

                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction
                let saturdayKey = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId <> ":basis:permanent:effective:undated:penalty:saturday_penalty"
                saturdayRequirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, saturdayKey)
                    |> fetchOne
                saturdayRequirement.requirementStatus `shouldBe` "matched"
                saturdayRequirement.ratePerUnit `shouldBe` Just 39.375

                saturdayRate <- query @AwardLevelPenaltyRate
                    |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                    |> filterWhere (#employmentBasis, Permanent)
                    |> filterWhere (#penaltyKind, SaturdayPenalty)
                    |> fetchOne
                _ <- saturdayRate
                    |> set #hourlyRate 41.00
                    |> updateRecord

                rateChangedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminXeroFragmentAction

                rateChangedResponse `responseStatusShouldBe` status200
                rateChangedResponse `responseBodyShouldContain` "rate changed"
                updatedRequirement <- query @XeroPayItemRequirementRecord
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#requirementKey, saturdayKey)
                    |> fetchOne
                updatedRequirement.requirementStatus `shouldBe` "rate_changed"
                updatedRequirement.ratePerUnit `shouldBe` Just 41.00

        it "rejects Xero staff mappings across venue boundaries" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Xero Staff Mapping Venue A"
                venueB <- createVenueWithConfig "Xero Staff Mapping Venue B"
                admin <- createUserRecord "xero-staff-mapping-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_owner"
                _ <- createVenueMembershipRecord venueB admin "venue_owner"
                connectionA <- createActiveXeroConnection venueA admin
                connectionB <- createActiveXeroConnection venueB admin
                staffA <- createStaffRecord venueA Nothing "Venue" "A"
                staffB <- createStaffRecord venueB Nothing "Venue" "B"
                _ <- createXeroEmployeeRecord connectionA "Venue A" Nothing "employee-a"
                _ <- createXeroEmployeeRecord connectionB "Venue B" Nothing "employee-b"

                foreignStaffResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams SaveXeroStaffMappingAction
                        [ ("staffId", idToParam staffB.id)
                        , ("xeroEmployeeSelection", "employee-a")
                        ]
                foreignStaffResponse `responseStatusShouldBe` status302

                foreignEmployeeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams SaveXeroStaffMappingAction
                        [ ("staffId", idToParam staffA.id)
                        , ("xeroEmployeeSelection", "employee-b")
                        ]
                foreignEmployeeResponse `responseStatusShouldBe` status302

                mappingCount <- query @XeroStaffMapping |> fetchCount
                mappingCount `shouldBe` 0

        it "shows the Xero draft-timesheet panel to venue owners" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Draft timesheets"
                response `responseBodyShouldContain` "Prepare"
                response `responseBodyShouldContain` "name=\"periodKey\""
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                response `responseBodyShouldContain` "id=\"xero-timesheets-data\""
                response `responseBodyShouldContain` "id=\"xero-timesheet-submission-indicator\""
                response `responseBodyShouldContain` "hx-post=\"/OpenXeroTimesheetPreparation\""
                response `responseBodyShouldContain` "hx-indicator=\"#xero-timesheet-submission-indicator\""
                response `responseBodyShouldContain` "Selected Xero payroll period"

        it "opens the guided Xero preparation modal for a selected pay period" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord

                loadingResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams OpenXeroTimesheetPreparationAction
                            [("periodKey", fixturePeriodKey fixture)]

                loadingResponse `responseStatusShouldBe` status200
                loadingResponse `responseBodyShouldContain` "Preparing Xero draft timesheets..."
                loadingResponse `responseBodyShouldContain` "hx-post=\"/RunXeroTimesheetPreparation\""
                loadingResponse `responseBodyShouldContain` "data-xero-timesheet-preparation-loading=\"true\""
                initialPreparationRunCount <- query @XeroTimesheetPreparationRun |> fetchCount
                initialPreparationRunCount `shouldBe` 0

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepare Xero draft timesheets"
                response `responseBodyShouldContain` "Setup"
                response `responseBodyShouldContain` "Sync reference data"
                response `responseBodyShouldContain` "Readiness validation"
                response `responseBodyShouldContain` "Preview"
                response `responseBodyShouldNotContain` "Earnings-rate mappings"
                response `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "ready_for_preview"
                preparationRun.payPeriodStart `shouldBe` fixture.periodStart
                preparationRun.payPeriodEnd `shouldBe` fixture.periodEnd
                (AesonTypes.parseMaybe AesonTypes.parseJSON preparationRun.eventsJson :: Maybe [Aeson.Value]) `shouldSatisfy` maybe False (not . null)

        it "uses a single staff employee dropdown with the suggested match preselected in guided preparation" $ withContext do
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

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff mapping decisions"
                response `responseBodyShouldContain` "Xero employee"
                response `responseBodyShouldContain` "name=\"xeroEmployeeSelection\""
                response `responseBodyShouldContain` "value=\"not_applicable\""
                response `responseBodyShouldContain` "Not paid through Xero"
                response `responseBodyShouldContain` ">Approve</button>"
                response `responseBodyShouldContain` "Skip this time"
                response `responseBodyShouldNotContain` "Suggested match"
                response `responseBodyShouldNotContain` "Manual employee"
                response `responseBodyShouldNotContain` "name=\"xeroEmployeeId\""
                response `responseBodyShouldNotContain` "value=\"approve_suggestion\""
                response `responseBodyShouldNotContain` "value=\"manual\""
                body <- responseBody response
                let bodyText = cs body
                Text.count "value=\"employee-a\"" bodyText `shouldBe` 1
                Text.count "value=\"employee-b\"" bodyText `shouldBe` 1
                bodyText `shouldSatisfy` Text.isInfixOf "value=\"employee-a\" selected"
                pendingStaffDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_auto_match" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
                pendingStaffDecisions `shouldBe` 2
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "needs_approval"

        it "applies the selected suggested employee through the unified preparation dropdown" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                resetXeroStaffMappingForPreparation fixture.staffA
                _ <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
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
                response `responseBodyShouldContain` "Mapped to Xero employee"
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetchOne
                mapping.mappingStatus `shouldBe` "verified"
                mapping.xeroEmployeeId `shouldBe` Just "employee-a"
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_auto_match" :: Text) |> fetchOne
                decision.decisionStatus `shouldBe` "applied"
                decision.xeroEmployeeId `shouldBe` Just "employee-a"

        it "shows proposed managed pay item creation instead of manual earnings-rate mapping in the preparation modal" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
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

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Managed pay items"
                response `responseBodyShouldContain` "pending creation"
                response `responseBodyShouldContain` "Approve creation"
                response `responseBodyShouldContain` "Bepis - HIGA - PERM - Undated - Level 2 - Ordinary"
                response `responseBodyShouldNotContain` "Earnings-rate mappings"
                response `responseBodyShouldNotContain` "name=\"xeroEarningsRateSelection\""
                pendingPayItemDecisions <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "pay_item_create" :: Text) |> filterWhere (#decisionStatus, "pending" :: Text) |> fetchCount
                pendingPayItemDecisions `shouldSatisfy` (> 0)
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "needs_approval"

        it "keeps stale Xero payroll calendar selections out of the guided preparation path" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                existingSelection <- query @XeroPayrollCalendarSelection |> fetchOne
                _ <-
                    existingSelection
                        |> set #calendarStatus ("stale" :: Text)
                        |> updateRecord
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction XeroAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Draft timesheet submission"
                pageResponse `responseBodyShouldContain` "Preview Calendar"
                pageResponse `responseBodyShouldContain` "Prepare"

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Setup"
                response `responseBodyShouldContain` "Payroll calendar"
                response `responseBodyShouldContain` "name=\"xeroPayrollCalendarSelection\""
                response `responseBodyShouldContain` "Preview Calendar"
                calendarSelection <- query @XeroPayrollCalendarSelection |> fetchOne
                calendarSelection.calendarStatus `shouldBe` "stale"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.selectedPayrollCalendarId `shouldBe` "calendar-preview"
                preparationRun.status `shouldBe` "ready_for_preview"

        it "hard-blocks guided Xero preparation when the selected Xero pay run is posted" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
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
                    client =
                        (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] [])
                            { fetchPayRuns = \_ _ _ -> pure (Right [postedPayRun])
                            }

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "posted"
                response `responseBodyShouldContain` "Draft timesheet creation is blocked"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "blocked"
                preparationRun.xeroPayRunId `shouldBe` Just "payrun-posted"
                preparationRun.remotePayRunsJson `shouldSatisfy` Preview.jsonContainsKey "remotePayRuns"

        it "blocks guided Xero preparation when a remote timesheet already exists for the included employee and period" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
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
                    client =
                        (referenceSyncXeroClient (XeroTokenResponse "prepare-access-token" "prepare-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] [])
                            { fetchTimesheets = \_ _ _ -> pure (Right [remoteTimesheet])
                            }

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams RunXeroTimesheetPreparationAction
                                    [("periodKey", fixturePeriodKey fixture)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Xero already has a timesheet for this employee and period"
                response `responseBodyShouldContain` "Create is blocked until update support exists"
                preparationRun <- query @XeroTimesheetPreparationRun |> fetchOne
                preparationRun.status `shouldBe` "blocked"
                preparationRun.remoteTimesheetsJson `shouldSatisfy` Preview.jsonContainsKey "remoteTimesheets"
                preparationRun.readinessSnapshotJson `shouldSatisfy` Preview.jsonContainsKey "blockers"

        it "rejects run-scoped skip for staff already mapped to Xero" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                run <- createPreparationRunForFixture fixture "needs_approval"

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ApplyXeroTimesheetPreparationStaffDecisionAction run.id)
                            [ ("staffId", idToParam fixture.staffA.id)
                            , ("decision", "skip")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Skip is only available for staff who are not already mapped to Xero."
                skipCount <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_skip" :: Text) |> fetchCount
                skipCount `shouldBe` 0

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
                response `responseBodyShouldContain` "Persistently marked as not paid through Xero."
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId fixture.staffA.id) |> fetchOne
                mapping.mappingStatus `shouldBe` "not_applicable"
                mapping.xeroEmployeeId `shouldBe` Nothing
                decision <- query @XeroTimesheetPreparationDecision |> filterWhere (#decisionKind, "staff_not_paid" :: Text) |> fetchOne
                decision.decisionStatus `shouldBe` "applied"
                decision.decidedByUserId `shouldBe` Just (unpackId fixture.owner.id)

        it "blocks non-owner venue roles from Xero draft-timesheet page and actions" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                manager <- createUserRecord "xero-timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord fixture.venue manager "manager"

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callAction XeroAction
                previewResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callAction PreviewXeroDraftTimesheetsAction
                submitResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callAction SubmitXeroDraftTimesheetsAction
                openPreparationResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callActionWithParams OpenXeroTimesheetPreparationAction
                        [("periodKey", fixturePeriodKey fixture)]
                runPreparationResponse <- withPasskeyVerifiedUserAndCurrentVenue manager fixture.venue.id do
                    callActionWithParams RunXeroTimesheetPreparationAction
                        [("periodKey", fixturePeriodKey fixture)]

                pageResponse `responseStatusShouldBe` status302
                previewResponse `responseStatusShouldBe` status302
                submitResponse `responseStatusShouldBe` status302
                openPreparationResponse `responseStatusShouldBe` status302
                runPreparationResponse `responseStatusShouldBe` status302
                runCount <- query @XeroSubmissionRun |> fetchCount
                runCount `shouldBe` 0
                preparationRunCount <- query @XeroTimesheetPreparationRun |> fetchCount
                preparationRunCount `shouldBe` 0

        it "persists a latest Xero draft-timesheet preview and renders one row per employee" $ withContext do
            withCleanDb do
                fixture <-
                    Preview.createPreviewFixture
                        "weekly"
                        [ Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                        , Preview.EntrySpec 1 Preview.fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                        ]
                readiness <- validateXeroTimesheetReadiness fixture.request
                readinessBlockerCodes readiness `shouldBe` []

                response <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction PreviewXeroDraftTimesheetsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Prepared Xero draft-timesheet preview."
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "app-live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin_xero_timesheets")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "xero-timesheets-data")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "/ShowAdminXeroTimesheetsFragment")
                run <- query @XeroSubmissionRun |> fetchOne
                run.status `shouldBe` "previewed"
                run.previewPayloadJson `shouldSatisfy` Preview.jsonContainsKey "timesheets"
                run.readinessSnapshotJson `shouldSatisfy` Preview.jsonContainsKey "blockers"
                run.xeroDuplicateCheckJson `shouldSatisfy` Preview.jsonContainsKey "remoteTimesheets"
                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowAdminXeroTimesheetsFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "employee-a"
                fragmentResponse `responseBodyShouldContain` "employee-b"
                fragmentResponse `responseBodyShouldNotContain` "Historical runs"

        it "submits Xero draft timesheets through the existing service and renders latest submission status" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #tenantId ("tenant-id" :: Text)
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient (XeroTokenResponse "submit-access-token" "submit-refresh-token" 1800 (Just requiredXeroScopesText)) [] [] []) do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction SubmitXeroDraftTimesheetsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Submitted Xero draft timesheets."
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "app-live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin_xero_timesheets")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "xero-timesheets-data")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "/ShowAdminXeroTimesheetsFragment")
                run <- query @XeroSubmissionRun |> fetchOne
                run.status `shouldBe` "submitted"
                submission <- query @XeroTimesheetSubmission |> fetchOne
                submission.status `shouldBe` "submitted"
                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowAdminXeroTimesheetsFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "id=\"xero-timesheets-data\""
                fragmentResponse `responseBodyShouldContain` "Submission status"
                fragmentResponse `responseBodyShouldContain` "submitted"

        it "renders readiness issues before Xero draft-timesheet submission" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                let entry = case fixture.entries of
                        firstEntry : _ -> firstEntry
                        []             -> error "expected fixture entry"
                _ <-
                    entry
                        |> set #isApproved False
                        |> set #approvedAt Nothing
                        |> set #approvedByUserId Nothing
                        |> set #staffPayVersionId Nothing
                        |> set #shiftTypePayVersionId Nothing
                        |> updateRecord

                blockedPage <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction XeroAction

                blockedPage `responseStatusShouldBe` status200
                blockedPage `responseBodyShouldContain` "Unapproved entries remain in the pay period."
                blockedPage `responseBodyShouldContain` "There are no approved timesheet entries in the selected period."

        it "renders per-employee Xero submission errors with a retry affordance" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
                _ <-
                    fixture.connection
                        |> set #tenantId ("tenant-id" :: Text)
                        |> set #encryptedRefreshToken encryptedRefreshToken
                        |> updateRecord
                let tokenResponse = XeroTokenResponse "submit-access-token" "submit-refresh-token" 1800 (Just requiredXeroScopesText)
                let failingCreateClient =
                        (referenceSyncXeroClient tokenResponse [] [] [])
                            { createTimesheet = \_ _ _ _ -> pure (Left (XeroHttpError "Xero validation failed: units are invalid"))
                            }
                failedResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest failingCreateClient do
                        withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction SubmitXeroDraftTimesheetsAction

                failedResponse `responseStatusShouldBe` status200
                failedResponse `responseBodyShouldContain` "Xero draft-timesheet submission did not complete successfully."
                failedResponse `responseBodyShouldNotContain` "Retry"
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders failedResponse)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "app-live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "admin_xero_timesheets")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "xero-timesheets-data")
                submission <- query @XeroTimesheetSubmission |> fetchOne
                submission.status `shouldBe` "failed"
                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue fixture.owner fixture.venue.id do
                    callAction ShowAdminXeroTimesheetsFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "Xero validation failed: units are invalid"
                fragmentResponse `responseBodyShouldContain` "Retry"

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
                    callAction ShowAdminXeroFragmentAction
                pageResponse `responseBodyShouldContain` "reconnect required"
                pageResponse `responseBodyShouldContain` "Xero needs to be reconnected before sync can continue."

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
                pageResponse `responseBodyShouldContain` "hx-indicator=\"#xero-reference-sync-indicator\""

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
                staff <- createStaffRecord venue Nothing "Mapped" "Worker"
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


testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "test-client-id"
        , clientSecret = "test-client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "test-token-encryption-key"
        }

withAdminStrictXeroMock :: (XeroRequestBaseUrls -> IO a) -> IO a
withAdminStrictXeroMock action = do
    (identitySpec, payrollSpec) <- XeroMock.loadXeroOpenApiSpecs
    XeroMock.withStrictXeroMock identitySpec payrollSpec action

successfulXeroClient :: XeroTokenResponse -> [XeroTenant] -> XeroClient
successfulXeroClient tokenResponse tenants =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right tenants)
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right [])
        , fetchEarningsRates = \_ _ -> pure (Right [])
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }

referenceSyncXeroClient :: XeroTokenResponse -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> XeroClient
referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right [])
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right employees)
        , fetchEarningsRates = \_ _ -> pure (Right earningsRates)
        , fetchPayrollCalendars = \_ _ -> pure (Right payrollCalendars)
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }

payItemCreateXeroClient :: XeroTokenResponse -> IORef.IORef [(Text, Aeson.Value)] -> XeroClient
payItemCreateXeroClient tokenResponse requestsRef =
    payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef Nothing

payItemCreateXeroClientWithVerifiedLimit :: XeroTokenResponse -> IORef.IORef [(Text, Aeson.Value)] -> Maybe Int -> XeroClient
payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef maybeVerifiedLimit =
    (referenceSyncXeroClient tokenResponse [] [] [])
        { fetchEarningsRates = \_ _ -> do
            requests <- IORef.readIORef requestsRef
            let latestRates = maybe [] xeroPayItemRequestEarningsRateRefs (lastMay (map snd requests))
            pure (Right (maybe latestRates (`take` latestRates) maybeVerifiedLimit))
        , createPayItem = \_ _ idempotencyKey body -> do
            IORef.modifyIORef' requestsRef (<> [(idempotencyKey, body)])
            pure (Right [])
        }

payItemCreateXeroClientFailingRequest :: XeroTokenResponse -> IORef.IORef [(Text, Aeson.Value)] -> Int -> Text -> XeroClient
payItemCreateXeroClientFailingRequest tokenResponse requestsRef failingRequestNumber errorMessage =
    (payItemCreateXeroClient tokenResponse requestsRef)
        { fetchEarningsRates = \_ _ -> do
            requests <- IORef.readIORef requestsRef
            let successfulBodies = map (snd . snd) (filter (\(index, _) -> index /= failingRequestNumber) (zip [1 :: Int ..] requests))
            let latestSuccessfulRates = maybe [] xeroPayItemRequestEarningsRateRefs (lastMay successfulBodies)
            pure (Right latestSuccessfulRates)
        , createPayItem = \_ _ idempotencyKey body -> do
            IORef.modifyIORef' requestsRef (<> [(idempotencyKey, body)])
            requests <- IORef.readIORef requestsRef
            if length requests == failingRequestNumber
                then pure (Left (XeroHttpError errorMessage))
                else pure (Right [])
        }

xeroPayItemRequestEarningsRateRefs :: Aeson.Value -> [XeroEarningsRateRef]
xeroPayItemRequestEarningsRateRefs =
    fromMaybe [] . AesonTypes.parseMaybe \body ->
        Aeson.withObject "PayItem" (\object -> do
            earningsRates <- object Aeson..: "EarningsRates"
            mapM earningsRateRefFromValue (earningsRates :: [Aeson.Value])
        ) body

earningsRateRefFromValue :: Aeson.Value -> AesonTypes.Parser XeroEarningsRateRef
earningsRateRefFromValue value@(Aeson.Object earningsRate) = do
    name <- earningsRate Aeson..: "Name"
    accountCode <- earningsRate Aeson..:? "AccountCode"
    pure $
        XeroEarningsRateRef
            ("created-" <> name)
            name
            (Just "ORDINARYTIMEEARNINGS")
            (Just "RATEPERUNIT")
            accountCode
            True
            value
earningsRateRefFromValue _ = fail "Expected earnings rate"

xeroPayItemRequestName :: Aeson.Value -> Maybe Text
xeroPayItemRequestName =
    AesonTypes.parseMaybe \body ->
        Aeson.withObject "PayItem" (\object -> do
            earningsRates <- object Aeson..: "EarningsRates"
            case earningsRates :: [Aeson.Value] of
                Aeson.Object earningsRate : _ -> earningsRate Aeson..: "Name"
                _                             -> fail "Missing earnings rate"
        ) body

xeroPayItemRequestAccountCode :: Aeson.Value -> Maybe Text
xeroPayItemRequestAccountCode =
    AesonTypes.parseMaybe \body ->
        Aeson.withObject "PayItem" (\object -> do
            earningsRates <- object Aeson..: "EarningsRates"
            case earningsRates :: [Aeson.Value] of
                Aeson.Object earningsRate : _ -> earningsRate Aeson..: "AccountCode"
                _ -> fail "Missing earnings rate"
        ) body

xeroPayItemRequestHas :: Text -> Scientific -> Aeson.Value -> Bool
xeroPayItemRequestHas expectedName expectedRate =
    fromMaybe False . AesonTypes.parseMaybe \body ->
        Aeson.withObject "PayItem" (\object -> do
            earningsRates <- object Aeson..: "EarningsRates"
            case earningsRates :: [Aeson.Value] of
                Aeson.Object earningsRate : _ -> do
                    name <- earningsRate Aeson..: "Name"
                    rate <- earningsRate Aeson..: "RatePerUnit"
                    rateType <- earningsRate Aeson..: "RateType"
                    typeOfUnits <- earningsRate Aeson..: "TypeOfUnits"
                    accountCode <- earningsRate Aeson..: "AccountCode"
                    pure (name == expectedName && rate == expectedRate && rateType == ("RATEPERUNIT" :: Text) && typeOfUnits == ("Hours" :: Text) && accountCode == ("477" :: Text))
                _ -> fail "Missing earnings rate"
        ) body

xeroPayItemRequestOnlyTouchesEarningsRates :: Aeson.Value -> Bool
xeroPayItemRequestOnlyTouchesEarningsRates (Aeson.Object object) =
    AesonKeyMap.member (AesonKey.fromText "EarningsRates") object
        && all
            (not . (`AesonKeyMap.member` object) . AesonKey.fromText)
            ["DeductionTypes", "LeaveTypes", "ReimbursementTypes"]
xeroPayItemRequestOnlyTouchesEarningsRates _ = False

failingRefreshXeroClient :: Text -> XeroClient
failingRefreshXeroClient message =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchConnectedTenants = \_ -> pure (Left (XeroHttpError message))
        , deleteXeroConnection = \_ _ -> pure (Left (XeroHttpError message))
        , refreshXeroToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollEmployees = \_ _ -> pure (Left (XeroHttpError message))
        , fetchEarningsRates = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollCalendars = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayRuns = \_ _ _ -> pure (Left (XeroHttpError message))
        , createPayItem = \_ _ _ _ -> pure (Left (XeroHttpError message))
        , fetchTimesheets = \_ _ _ -> pure (Left (XeroHttpError message))
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError message))
        , createTimesheet = \_ _ _ _ -> pure (Left (XeroHttpError message))
        , updateTimesheet = \_ _ _ _ _ -> pure (Left (XeroHttpError message))
        }

createTestXeroOauthState ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    Text ->
    NominalDiffTime ->
    Maybe UTCTime ->
    IO XeroOauthState
createTestXeroOauthState venue user stateToken lifetime maybeConsumedAt = do
    now <- getCurrentTime
    newRecord @XeroOauthState
        |> set #venueId (unpackId venue.id)
        |> set #userId (unpackId user.id)
        |> set #stateToken stateToken
        |> set #requestedScopes requiredXeroScopesText
        |> set #redirectUri testXeroConfig.redirectUri
        |> set #expiresAt (addUTCTime lifetime now)
        |> set #consumedAt maybeConsumedAt
        |> createRecord

createActiveXeroConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    IO XeroConnection
createActiveXeroConnection venue user =
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId "tenant-existing"
        |> set #tenantName (Just "Existing Demo Company")
        |> set #xeroConnectionRemoteId (Just "connection-existing")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken "encrypted-refresh-token"
        |> set #encryptedAccessToken (Just "encrypted-access-token")
        |> set #connectedByUserId (Just (unpackId user.id))
        |> createRecord

createSyncableXeroConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    IO XeroConnection
createSyncableXeroConnection venue user = do
    encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "existing-refresh-token"
    encryptedAccessToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "existing-access-token"
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId "tenant-existing"
        |> set #tenantName (Just "Existing Demo Company")
        |> set #xeroConnectionRemoteId (Just "connection-existing")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #encryptedAccessToken (Just encryptedAccessToken)
        |> set #connectedByUserId (Just (unpackId user.id))
        |> createRecord

createXeroEmployeeRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Maybe Text ->
    Text ->
    IO XeroEmployee
createXeroEmployeeRecord connection displayName maybeEmail employeeId = do
    now <- getCurrentTime
    newRecord @XeroEmployee
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEmployeeId employeeId
        |> set #displayName displayName
        |> set #email maybeEmail
        |> set #status (Just "ACTIVE")
        |> set #payrollCalendarId Nothing
        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeId])
        |> set #syncedAt now
        |> createRecord

createXeroEarningsRateRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Text ->
    IO XeroEarningsRate
createXeroEarningsRateRecord connection name earningsRateId = do
    now <- getCurrentTime
    newRecord @XeroEarningsRate
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEarningsRateId earningsRateId
        |> set #name name
        |> set #earningsType (Just "REGULAR")
        |> set #rateType (Just "RATEPERUNIT")
        |> set #accountCode (Just "477")
        |> set #isActive True
        |> set #rawPayload (Aeson.object ["EarningsRateID" Aeson..= earningsRateId])
        |> set #syncedAt now
        |> createRecord

createStaffUsingAwardLevel ::
    (?modelContext :: ModelContext) =>
    Venue ->
    Text ->
    Text ->
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    IO Staff
createStaffUsingAwardLevel venue firstName lastName awardLevel employmentBasis = do
    staff <- createStaffRecord venue Nothing firstName lastName
    staff
        |> set #employmentBasis employmentBasis
        |> set #defaultAwardLevelId (Just awardLevel.id)
        |> updateRecord

addCasualBaseAndSaturdayPenalty ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    Scientific ->
    Scientific ->
    IO ()
addCasualBaseAndSaturdayPenalty awardLevel baseRate saturdayRate = do
    payRate <-
        newRecord @FwcMapdPayRate
            |> set #awardFixedId awardLevel.awardFixedId
            |> set #classificationFixedId (Just awardLevel.classificationFixedId)
            |> set #classification awardLevel.classification
            |> set #employeeRateTypeCode (Just "AD")
            |> set #calculatedRate (Just baseRate)
            |> set #calculatedRateType (Just "Hourly")
            |> createRecord
    _ <-
        newRecord @AwardLevelBaseRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis Casual
            |> set #fwcMapdPayRateId (unpackId payRate.id)
            |> set #hourlyRate baseRate
            |> set #rateLabel ("Hourly" :: Text)
            |> createRecord

    penaltyRate <-
        newRecord @FwcMapdPenaltyRate
            |> set #awardFixedId awardLevel.awardFixedId
            |> set #classificationFixedId (Just awardLevel.classificationFixedId)
            |> set #classification awardLevel.classification
            |> set #employeeRateTypeCode (Just "AD")
            |> set #basePayRateId payRate.basePayRateId
            |> set #penaltyDescription (Just (inputValue SaturdayPenalty))
            |> set #penaltyCalculatedValue (Just saturdayRate)
            |> createRecord
    _ <-
        newRecord @AwardLevelPenaltyRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis Casual
            |> set #penaltyKind SaturdayPenalty
            |> set #fwcMapdPenaltyRateId (unpackId penaltyRate.id)
            |> set #hourlyRate saturdayRate
            |> createRecord
    pure ()

fixturePeriodKey fixture =
    cs ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd :: Text)

createPreparationRunForFixture ::
    (?modelContext :: ModelContext) =>
    Preview.PreviewFixture ->
    Text ->
    IO XeroTimesheetPreparationRun
createPreparationRunForFixture fixture status =
    newRecord @XeroTimesheetPreparationRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #createdByUserId (unpackId fixture.owner.id)
        |> set #selectedPayrollCalendarId ("calendar-preview" :: Text)
        |> set #selectedPayrollCalendarName (Just ("Preview Calendar" :: Text))
        |> set #selectedPeriodKey ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd :: Text)
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #status status
        |> createRecord

createXeroPayrollCalendarRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Text ->
    IO XeroPayrollCalendar
createXeroPayrollCalendarRecord connection name payrollCalendarId = do
    now <- getCurrentTime
    newRecord @XeroPayrollCalendar
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroPayrollCalendarId payrollCalendarId
        |> set #name name
        |> set #calendarType (Just "WEEKLY")
        |> set #startDate (Just (fromGregorian 2026 4 27))
        |> set #paymentDate (Just (fromGregorian 2026 5 1))
        |> set #rawPayload (Aeson.object ["PayrollCalendarID" Aeson..= payrollCalendarId])
        |> set #syncedAt now
        |> createRecord

resetXeroStaffMappingForPreparation ::
    (?modelContext :: ModelContext) =>
    Staff ->
    IO ()
resetXeroStaffMappingForPreparation staff = do
    mappings <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId staff.id) |> fetch
    forM_ mappings \mapping ->
        mapping
            |> set #mappingStatus ("not_applicable" :: Text)
            |> set #xeroEmployeeId Nothing
            |> set #xeroEmployeeName Nothing
            |> set #xeroEmployeeEmail Nothing
            |> set #updatedByUserId Nothing
            |> updateRecord
            >>= const (pure ())

createXeroPayItemAccountCodeSelectionRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    IO XeroPayItemAccountCodeSelection
createXeroPayItemAccountCodeSelectionRecord connection accountCode = do
    now <- getCurrentTime
    newRecord @XeroPayItemAccountCodeSelection
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #accountCode (Just accountCode)
        |> set #selectionStatus "verified"
        |> set #lastVerifiedAt (Just now)
        |> createRecord
