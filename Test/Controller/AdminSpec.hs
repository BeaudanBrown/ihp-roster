module Test.Controller.AdminSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.Helper.Xero
import Config
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime, getCurrentTime)
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
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "AdminController" do
        it "redirects unauthenticated users from admin page" $ withContext do
            response <- callAction AdminAction
            response `responseStatusShouldBe` status302

        it "redirects venue-less super-admins from admin to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "admin-bootstrap-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUser user do
                    callAction AdminAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "shows current-venue admin sections with FWC-backed award level data" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"

                levelA <- createPayLevelRecordWithRates venueA "Level A" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createShiftTypeRecord venueA levelA "Kitchen"
                _ <- createSlotNameRecord venueA "Default Only"
                venueAGroupB <- createVenueRosterGroupWithDefaults venueA "Back of House" 10 True
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venueA.id)
                    |> set #rosterGroupId (unpackId venueAGroupB.id)
                    |> set #name "Pass"
                    |> set #sortOrder 3
                    |> set #isActive True
                    |> createRecord
                _ <- createPayConfigSnapshotRecord venueA admin 1 (Aeson.object [])
                _ <- createPayConfigSnapshotRecord venueA admin 2 (Aeson.object [])

                levelB <- createPayLevelRecord venueB "Level B"
                _ <- createShiftTypeRecord venueB levelB "Bar"
                _ <- createSlotNameRecord venueB "Graveyard"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams AdminAction [("rosterGroupId", idToParam venueAGroupB.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Shift Types"
                response `responseBodyShouldContain` "Slot Names"
                response `responseBodyShouldContain` "Invites"
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "Generate Staff Pay CSV"
                response `responseBodyShouldContain` "Generate Hourly Breakdown ZIP"
                response `responseBodyShouldContain` "Generate Payroll Earnings CSV"
                response `responseBodyShouldContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "admin-invites-fragment"
                body <- responseBody response
                (cs body :: String) `shouldContainInOrder` ["Invites", "Exports", "Shift Types", "Roster Groups"]
                response `responseBodyShouldNotContain` "Venue Config"
                response `responseBodyShouldNotContain` "Award Levels"
                response `responseBodyShouldNotContain` "Pay Levels"
                response `responseBodyShouldNotContain` "Pay Level Day Rules"
                response `responseBodyShouldNotContain` "slot-names-heading"
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldContain` "Kitchen"
                response `responseBodyShouldContain` "Level A"
                response `responseBodyShouldContain` "Level A (perm $31.50/hr)"
                response `responseBodyShouldContain` "Use staff default award level"
                response `responseBodyShouldContain` "Back of House"
                response `responseBodyShouldContain` "Pass"
                response `responseBodyShouldContain` "Default Only"
                response `responseBodyShouldNotContain` "Bar"
                response `responseBodyShouldNotContain` "Graveyard"

        it "scopes slot names to the roster group card and fragment target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Slot Group Venue"
                admin <- createUserRecord "admin-slot-groups@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                firstGroup <- createVenueRosterGroupWithDefaults venue "Front Lane" 10 True
                secondGroup <- createVenueRosterGroupWithDefaults venue "Back Lane" 20 True
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId firstGroup.id)
                    |> set #name "Front Register"
                    |> set #sortOrder 0
                    |> set #isActive True
                    |> createRecord
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId secondGroup.id)
                    |> set #name "Back Pass"
                    |> set #sortOrder 0
                    |> set #isActive True
                    |> createRecord

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Front Lane"
                pageResponse `responseBodyShouldContain` "Back Lane"
                pageResponse `responseBodyShouldContain` "Front Register"
                pageResponse `responseBodyShouldContain` "Back Pass"
                pageResponse `responseBodyShouldContain` ("id=\"admin-slot-names-fragment-" <> tshow firstGroup.id <> "\"")
                pageResponse `responseBodyShouldContain` ("id=\"admin-slot-names-fragment-" <> tshow secondGroup.id <> "\"")
                pageResponse `responseBodyShouldContain` "data-live-update-surface=\""
                pageResponse `responseBodyShouldContain` "admin_slot_names"
                pageResponse `responseBodyShouldContain` ("admin-slot-names-fragment-" <> tshow firstGroup.id)
                pageResponse `responseBodyShouldContain` ("admin-slot-names-fragment-" <> tshow secondGroup.id)
                pageResponse `responseBodyShouldContain` ("hx-target=\"#admin-slot-names-fragment-" <> tshow firstGroup.id <> "\"")
                pageResponse `responseBodyShouldContain` ("hx-target=\"#admin-slot-names-fragment-" <> tshow secondGroup.id <> "\"")

                firstFragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminSlotNamesFragmentAction
                        [("rosterGroupId", idToParam firstGroup.id)]
                firstFragmentResponse `responseStatusShouldBe` status200
                firstFragmentResponse `responseBodyShouldContain` ("id=\"admin-slot-names-fragment-" <> tshow firstGroup.id <> "\"")
                firstFragmentResponse `responseBodyShouldContain` "Front Register"
                firstFragmentResponse `responseBodyShouldNotContain` "Back Pass"
                firstFragmentResponse `responseBodyShouldNotContain` "id=\"app\""

                secondFragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminSlotNamesFragmentAction
                        [("rosterGroupId", idToParam secondGroup.id)]
                secondFragmentResponse `responseStatusShouldBe` status200
                secondFragmentResponse `responseBodyShouldContain` ("id=\"admin-slot-names-fragment-" <> tshow secondGroup.id <> "\"")
                secondFragmentResponse `responseBodyShouldContain` "Back Pass"
                secondFragmentResponse `responseBodyShouldNotContain` "Front Register"

        it "rejects non-admin venue members from admin screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "manager-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status403

        it "shows the Xero admin section as not connected" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Admin Venue"
                admin <- createUserRecord "xero-admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Xero"
                response `responseBodyShouldContain` "not connected"
                response `responseBodyShouldContain` "Connect Xero"

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
                let tenant = XeroTenant "tenant-123" (Just "Demo Company")

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (successfulXeroClient tokenResponse [tenant]) do
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            callActionWithParams XeroOAuthCallbackAction
                                [ ("state", cs oauthState.stateToken)
                                , ("code", "auth-code")
                                ]

                response `responseStatusShouldBe` status302
                connection <- query @XeroConnection |> fetchOne
                connection.venueId `shouldBe` unpackId venue.id
                connection.tenantId `shouldBe` "tenant-123"
                connection.tenantName `shouldBe` Just "Demo Company"
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

        it "disconnects an active Xero connection without hard deleting history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Disconnect Venue"
                admin <- createUserRecord "xero-disconnect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_owner"
                connection <- createActiveXeroConnection venue admin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction DisconnectXeroConnectionAction

                response `responseStatusShouldBe` status302
                updatedConnection <- fetch connection.id
                updatedConnection.connectionStatus `shouldBe` "disconnected"
                updatedConnection.disconnectedByUserId `shouldBe` Just (unpackId admin.id)
                updatedConnection.disconnectedAt `shouldSatisfy` isJust
                updatedConnection.encryptedAccessToken `shouldBe` Nothing
                connectionCount <- query @XeroConnection |> fetchCount
                connectionCount `shouldBe` 1
                auditEvents <- query @AuditEvent |> filterWhere (#eventType, "xero_connection_disconnected" :: Text) |> fetch
                length auditEvents `shouldBe` 1

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

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest (referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars) do
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
                decryptXeroToken testXeroConfig.tokenEncryptionKey updatedConnection.encryptedRefreshToken `shouldBe` Right "new-refresh-token"

        it "records Xero payroll reference sync failures without storing stale rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Sync Failure Venue"
                admin <- createUserRecord "xero-sync-failure@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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

                startResponse `responseStatusShouldBe` status403
                callbackResponse `responseStatusShouldBe` status403
                disconnectResponse `responseStatusShouldBe` status403
                retainedConnection <- fetch connection.id
                retainedConnection.connectionStatus `shouldBe` "active"

        it "allows venue owners to access admin config screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                owner <- createUserRecord "owner-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldNotContain` "Venue Config"

        it "serves inactive toggles through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Fragment Venue"
                admin <- createUserRecord "admin-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue level "Active Shift"
                inactiveShiftType <- createShiftTypeRecord venue level "Inactive Shift"
                _ <- inactiveShiftType
                    |> set #isActive False
                    |> updateRecord
                _ <- createVenueRosterGroupWithDefaults venue "Active Group" 10 True
                _ <- createVenueRosterGroupWithDefaults venue "Inactive Group" 20 False

                hiddenShiftTypesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminShiftTypesFragmentAction
                        [("showInactiveShiftTypes", "false")]
                hiddenShiftTypesResponse `responseStatusShouldBe` status200
                hiddenShiftTypesResponse `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "data-live-update-surface=\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "admin_shift_types"
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-get=\"/ShowAdminShiftTypesFragment?showInactiveShiftTypes=true\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "Active Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "Inactive Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "id=\"app\""

                visibleShiftTypesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminShiftTypesFragmentAction
                        [("showInactiveShiftTypes", "true")]
                visibleShiftTypesResponse `responseStatusShouldBe` status200
                visibleShiftTypesResponse `responseBodyShouldContain` "Inactive Shift"
                visibleShiftTypesBody <- responseBody visibleShiftTypesResponse
                (cs visibleShiftTypesBody :: String) `shouldContainInOrder` ["Active Shift", "Inactive Shift"]
                visibleShiftTypesResponse `responseBodyShouldContain` "checked=\"checked\""

                hiddenRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminRosterGroupsFragmentAction
                        [("showInactiveRosterGroups", "false")]
                hiddenRosterGroupsResponse `responseStatusShouldBe` status200
                hiddenRosterGroupsResponse `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "data-live-update-surface=\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "admin_roster_groups"
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-get=\"/ShowAdminRosterGroupsFragment?showInactiveRosterGroups=true\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "Active Group"
                hiddenRosterGroupsResponse `responseBodyShouldNotContain` "Inactive Group"

                visibleRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminRosterGroupsFragmentAction
                        [("showInactiveRosterGroups", "true")]
                visibleRosterGroupsResponse `responseStatusShouldBe` status200
                visibleRosterGroupsResponse `responseBodyShouldContain` "Inactive Group"
                visibleRosterGroupsBody <- responseBody visibleRosterGroupsResponse
                (cs visibleRosterGroupsBody :: String) `shouldContainInOrder` ["Active Group", "Inactive Group"]
                visibleRosterGroupsResponse `responseBodyShouldContain` "checked=\"checked\""

        it "serves shift type and roster group add/update through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Mutation Fragment Venue"
                admin <- createUserRecord "admin-mutation-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Starter Shift"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Starter Group" 10 True
                inactiveRosterGroup <- createVenueRosterGroupWithDefaults venue "Archived Group" 20 False

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams AdminAction [("showInactiveRosterGroups", "true"), ("showInactiveShiftTypes", "true")]
                pageResponse `responseBodyShouldContain` "hx-post=\"/CreateShiftType\""
                pageResponse `responseBodyShouldContain` "admin_shift_types"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveShiftTypes\" value=\"true\""
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateShiftType?shiftTypeId=" <> tshow shiftType.id <> "\"")
                pageResponse `responseBodyShouldContain` "hx-post=\"/CreateRosterGroup\""
                pageResponse `responseBodyShouldContain` "admin_roster_groups"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveRosterGroups\" value=\"true\""
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateRosterGroup?rosterGroupId=" <> tshow rosterGroup.id)

                shiftTypesVersionBefore <- currentLiveUpdateVersion AdminShiftTypesScope { venueId = unpackId venue.id }
                createShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateShiftTypeAction
                            [ ("name", "Fragment Shift")
                            , ("isActive", "true")
                            , ("overrideAwardLevelId", "")
                            , ("showInactiveShiftTypes", "true")
                            ]
                createShiftResponse `responseStatusShouldBe` status200
                createShiftResponse `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                createShiftResponse `responseBodyShouldContain` "Fragment Shift"
                createShiftResponse `responseBodyShouldContain` "checked=\"checked\""
                createShiftResponse `responseBodyShouldNotContain` "id=\"app\""
                shiftTypesVersionAfter <- currentLiveUpdateVersion AdminShiftTypesScope { venueId = unpackId venue.id }
                shiftTypesVersionAfter `shouldBe` (shiftTypesVersionBefore + 1)

                updateShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateShiftTypeAction shiftType.id)
                            [ ("name", "Updated Fragment Shift")
                            , ("isActive", "false")
                            , ("overrideAwardLevelId", "")
                            , ("showInactiveShiftTypes", "true")
                            ]
                updateShiftResponse `responseStatusShouldBe` status200
                updateShiftResponse `responseBodyShouldContain` "Updated Fragment Shift"
                updateShiftResponse `responseBodyShouldContain` "inactive"

                rosterGroupsVersionBefore <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
                createRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterGroupAction
                            [ ("name", "Fragment Group")
                            , ("isActive", "true")
                            , ("showInactiveRosterGroups", "true")
                            ]
                createRosterGroupResponse `responseStatusShouldBe` status200
                createRosterGroupResponse `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                createRosterGroupResponse `responseBodyShouldContain` "Fragment Group"
                createRosterGroupResponse `responseBodyShouldContain` "Archived Group"
                createRosterGroupResponse `responseBodyShouldContain` "checked=\"checked\""
                createRosterGroupResponse `responseBodyShouldNotContain` "id=\"app\""
                rosterGroupsVersionAfter <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
                rosterGroupsVersionAfter `shouldBe` (rosterGroupsVersionBefore + 1)

                updateRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                            [ ("name", "Updated Fragment Group")
                            , ("isActive", "true")
                            , ("showInactiveRosterGroups", "true")
                            ]
                updateRosterGroupResponse `responseStatusShouldBe` status200
                updateRosterGroupResponse `responseBodyShouldContain` "Updated Fragment Group"
                updateRosterGroupResponse `responseBodyShouldContain` tshow inactiveRosterGroup.id

        it "creates venue-scoped non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                inviteNow <- getCurrentTime

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                slotResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                inviteResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "new-worker@example.com")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                inviteResponse `responseStatusShouldBe` status302

                createdSlotName <- query @SlotName |> filterWhere (#name, "Swing") |> fetchOne
                createdShiftType <- query @ShiftType |> filterWhere (#name, "Supervisor") |> fetchOne
                createdInvitation <- query @VenueInvitation |> filterWhere (#email, "new-worker@example.com") |> fetchOne
                let inviteExpiryDeltaSeconds = diffUTCTime (fromMaybe inviteNow createdInvitation.expiresAt) inviteNow

                createdRosterGroup.venueId `shouldBe` unpackId venue.id
                createdRosterGroup.sortOrder `shouldBe` 1
                createdRosterGroup.isActive `shouldBe` True
                createdSlotName.name `shouldBe` "Swing"
                createdSlotName.rosterGroupId `shouldBe` unpackId createdRosterGroup.id
                createdSlotName.isActive `shouldBe` True
                createdSlotName.sortOrder `shouldBe` 3
                createdShiftType.name `shouldBe` "Supervisor"
                createdShiftType.overrideAwardLevelId `shouldBe` Nothing
                createdShiftType.isActive `shouldBe` True
                createdInvitation.venueId `shouldBe` unpackId venue.id
                createdInvitation.invitedByUserId `shouldBe` Just (unpackId admin.id)
                createdInvitation.acceptedAt `shouldBe` Nothing
                inputValue createdInvitation.inviteRole `shouldBe` "worker"
                inputValue createdInvitation.status `shouldBe` "pending"
                inputValue createdInvitation.deliveryStatus `shouldSatisfy` (`elem` ["queued", "sent", "failed"])
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 86000 && seconds < 87000)

        it "updates non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Kitchen"
                overrideLevel <- createPayLevelRecord venue "Level 2"
                slotName <- fetchSlotNameRecord venue "Early"
                middleSlotName <- fetchSlotNameRecord venue "Mid"
                lastSlotName <- fetchSlotNameRecord venue "Late"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 5 True

                moveGroupUpResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (MoveRosterGroupUpAction rosterGroup.id)
                moveGroupUpResponse `responseStatusShouldBe` status302

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                        [ ("name", "Back of House Updated")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("name", "Kitchen Updated")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", idToParam overrideLevel.id)
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                slotResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateSlotNameAction slotName.id)
                        [ ("name", "Early Updated")
                        ]
                slotResponse `responseStatusShouldBe` status302

                moveDownResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (MoveSlotNameDownAction slotName.id)
                moveDownResponse `responseStatusShouldBe` status302

                moveUpResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (MoveSlotNameUpAction lastSlotName.id)
                moveUpResponse `responseStatusShouldBe` status302

                deleteSlotResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (DeleteSlotNameAction middleSlotName.id)
                deleteSlotResponse `responseStatusShouldBe` status302

                updatedShiftType <- fetch shiftType.id
                updatedSlotName <- fetch slotName.id
                updatedRosterGroup <- fetch rosterGroup.id
                defaultRosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                updatedRosterGroup.name `shouldBe` "Back of House Updated"
                updatedRosterGroup.sortOrder `shouldBe` 0
                updatedRosterGroup.isActive `shouldBe` True
                get #id defaultRosterGroup `shouldBe` get #id updatedRosterGroup
                updatedShiftType.name `shouldBe` "Kitchen Updated"
                updatedShiftType.overrideAwardLevelId `shouldBe` Just overrideLevel.id
                updatedShiftType.isActive `shouldBe` False
                updatedSlotName.name `shouldBe` "Early Updated"
                updatedSlotName.isActive `shouldBe` True
                updatedSlotName.sortOrder `shouldBe` 2
                (fmap (get #isActive) (fetch middleSlotName.id)) `shouldReturn` False
                (fmap (get #sortOrder) (fetch lastSlotName.id)) `shouldReturn` 1
                (fmap (map (.name)) (fetchActiveRosterGroupSlotNames (Id updatedSlotName.rosterGroupId :: Id RosterGroup))) `shouldReturn` ["Late", "Early Updated"]

        it "updates the roster week start before venue history exists and snapshots the new setting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-week-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [("rosterWeekStartsOn", "2")]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch

                venueConfig.rosterWeekStartsOn `shouldBe` 2
                venueConfig.weekOffsetEpoch `shouldBe` defaultWeekOffsetEpochForStartDay 2
                map (.versionLabel) snapshots `shouldBe` ["v1"]

        it "rejects updates to config rows outside the current venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"
                foreignLevel <- createPayLevelRecord venueB "Foreign Level"
                foreignShiftType <- createShiftTypeRecord venueB foreignLevel "Foreign Shift"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdateShiftTypeAction foreignShiftType.id)
                        [ ("name", "Should Not Work")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", "")
                        ]

                response `responseStatusShouldBe` status403

                unchangedShiftType <- fetch foreignShiftType.id
                unchangedShiftType.name `shouldBe` "Foreign Shift"
                unchangedShiftType.isActive `shouldBe` True

        it "snapshots payroll-relevant FWC-backed config changes while skipping roster-only edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                query @PayConfigSnapshot |> fetch `shouldReturn` []

                _ <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v1"]

                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne
                slotResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v1"]

                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch
                map (.createdByUserId) snapshots `shouldBe` [unpackId admin.id]

shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    case mapM markerPosition needles of
        Nothing -> expectationFailure ("Expected body to contain all markers in order: " ++ cs (show needles))
        Just positions -> positions `shouldSatisfy` ordered
    where
        markerPosition marker = List.findIndex (List.isPrefixOf marker) (List.tails haystack)
        ordered positions = positions == List.sort positions

testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "test-client-id"
        , clientSecret = "test-client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "test-token-encryption-key"
        }

successfulXeroClient :: XeroTokenResponse -> [XeroTenant] -> XeroClient
successfulXeroClient tokenResponse tenants =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right tenants)
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right [])
        , fetchEarningsRates = \_ _ -> pure (Right [])
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        }

referenceSyncXeroClient :: XeroTokenResponse -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> XeroClient
referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right [])
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right employees)
        , fetchEarningsRates = \_ _ -> pure (Right earningsRates)
        , fetchPayrollCalendars = \_ _ -> pure (Right payrollCalendars)
        }

failingRefreshXeroClient :: Text -> XeroClient
failingRefreshXeroClient message =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchConnectedTenants = \_ -> pure (Left (XeroHttpError message))
        , refreshXeroToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollEmployees = \_ _ -> pure (Left (XeroHttpError message))
        , fetchEarningsRates = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollCalendars = \_ _ -> pure (Left (XeroHttpError message))
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
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #encryptedAccessToken (Just encryptedAccessToken)
        |> set #connectedByUserId (Just (unpackId user.id))
        |> createRecord
