module Test.Controller.SupportSpec where

import Application.Async.Queue (activeAppJobStatuses)
import Application.FwcMapd.Job (fwcMapdRefreshJobKind)
import Application.Helper.Controller (passkeyStepUpRedirectSessionKey)
import Application.Helper.ControllerContext
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.Impersonation
import Application.Helper.LiveUpdate
import Application.Helper.OpaqueToken (hashOpaqueToken)
import Application.Helper.Xero
import Application.Support.LiveUpdates
import Config
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Bits (xor)
import qualified Data.ByteString as ByteString
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import qualified Network.Wai as Wai
import Test.Hspec
import Test.Support
import Test.Support.Concurrency (runConcurrentActionsImmediately)
import Test.Support.SurfaceContract
import Test.Support.XeroAdmin (testXeroConfig)
import qualified Web.ClientSession as ClientSession
import Web.Controller.Support ()
import Web.FrontController ()
import Web.RosterWeeks.Paths (supportVenueSwitchReturnPath)
import Web.Types

supportFragmentRef :: SupportLiveFragment -> FrontendSurfaceMountedFragment
supportFragmentRef fragment =
    case filter ((== supportLiveFragmentKey fragment) . (.mountedFragmentKey)) supportCandidateMountedFragments of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support mounted fragment"

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "SupportController" do
        it "drops venue-scoped roster groups from canonical support-switch return paths" $ withContext do
            supportVenueSwitchReturnPath "/ShowRosterWindow?anchorDate=2026-08-10&rosterGroupId=11111111-1111-1111-1111-111111111111"
                `shouldBe` "/RosterWeeks"

        it "redirects unauthenticated users from live support fragments" $ withContext do
            response <- callAction ShowFwcMapdAwardRatesSectionAction

            liveFragmentResponseShouldBeDenied status302 response

        it "redirects ordinary users from live support fragments" $ withContext do
            withCleanDb do
                user <- createUserRecord "support-fragment-user@example.com" "staff" True

                response <- withPasskeyVerifiedUser user do
                    callAction ShowPublicHolidaysSectionAction

                liveFragmentResponseShouldBeDenied status302 response

        it "serves live support fragments to super admins through the surface rule" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-fragment-super@example.com" "staff" (Just SuperAdmin) True

                awardRatesResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowFwcMapdAwardRatesSectionAction
                publicHolidaysResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowPublicHolidaysSectionAction

                liveFragmentResponseShouldRenderTarget awardRatesResponse (supportFragmentRef SupportAwardRatesLiveFragment)
                liveFragmentResponseShouldRenderTarget publicHolidaysResponse (supportFragmentRef SupportPublicHolidaysLiveFragment)

        it "reads a current Xero timesheet into a redacted support diagnostic" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Diagnostic Venue"
                founder <- createUserRecordWithPlatformRole "xero-diagnostic-founder@example.com" "staff" (Just SuperAdmin) True
                staff <- createStaffRecord venue Nothing "Sensitive" "Employee"
                connectionRecord <- createXeroConnectionRecord venue founder "sensitive-tenant-id"
                encryptedAccessToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "sensitive-access-token"
                now <- getCurrentTime
                connection <-
                    connectionRecord
                        |> set #encryptedAccessToken (Just encryptedAccessToken)
                        |> set #accessTokenExpiresAt (Just (addUTCTime 3600 now))
                        |> updateRecord
                let periodStart = fromGregorian 2026 8 10
                let periodEnd = fromGregorian 2026 8 16
                run <-
                    newRecord @XeroSubmissionRun
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #submittedByUserId (unpackId founder.id)
                        |> set #payPeriodStart periodStart
                        |> set #payPeriodEnd periodEnd
                        |> createRecord
                let rawLine =
                        Aeson.object
                            [ "EarningsRateID" Aeson..= ("sensitive-earnings-rate-id" :: Text)
                            , "NumberOfUnits" Aeson..= ([8.5, 0, 0, 0, 0, 0, 0] :: [Scientific])
                            ]
                let rawTimesheet =
                        Aeson.object
                            [ "TimesheetID" Aeson..= ("sensitive-timesheet-id" :: Text)
                            , "EmployeeID" Aeson..= ("sensitive-employee-id" :: Text)
                            , "StartDate" Aeson..= periodStart
                            , "EndDate" Aeson..= periodEnd
                            , "Status" Aeson..= ("DRAFT" :: Text)
                            , "UpdatedDateUTC" Aeson..= ("2026-08-12T08:15:00Z" :: Text)
                            , "TimesheetLines" Aeson..= [rawLine]
                            ]
                submission <-
                    newRecord @XeroTimesheetSubmission
                        |> set #xeroSubmissionRunId (unpackId run.id)
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #xeroEmployeeId "sensitive-employee-id"
                        |> set #payPeriodStart periodStart
                        |> set #payPeriodEnd periodEnd
                        |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
                        |> set #idempotencyKey "persisted-key"
                        |> set #requestPayloadJson (Aeson.Array (pure (Aeson.object ["TimesheetLines" Aeson..= [rawLine]])))
                        |> set #responsePayloadJson (Aeson.object ["Timesheets" Aeson..= [Aeson.object ["Raw" Aeson..= rawTimesheet]]])
                        |> set #xeroTimesheetId (Just "sensitive-timesheet-id")
                        |> createRecord
                _ <-
                    newRecord @XeroEarningsRate
                        |> set #venueId (unpackId venue.id)
                        |> set #xeroConnectionId (unpackId connection.id)
                        |> set #xeroEarningsRateId "sensitive-earnings-rate-id"
                        |> set #name "Sensitive pay item name"
                        |> set #rateType (Just "RatePerUnit")
                        |> set #isActive True
                        |> set #providerAvailable True
                        |> set #rawPayload (Aeson.object ["RatePerUnit" Aeson..= (39.13 :: Scientific), "TypeOfUnits" Aeson..= ("Hours" :: Text)])
                        |> set #syncedAt now
                        |> createRecord
                baseClient <- currentXeroClient
                let remote =
                        XeroTimesheetRef
                            { xeroTimesheetId = Just "sensitive-timesheet-id"
                            , xeroTimesheetEmployeeId = "sensitive-employee-id"
                            , xeroTimesheetStartDate = periodStart
                            , xeroTimesheetEndDate = periodEnd
                            , xeroTimesheetStatus = Just "DRAFT"
                            , xeroTimesheetHours = Just 8.5
                            , xeroTimesheetLines = [XeroTimesheetLineRef (Just "sensitive-earnings-rate-id") Nothing [8.5, 0, 0, 0, 0, 0, 0] rawLine]
                            , xeroTimesheetRaw = rawTimesheet
                            }
                let diagnosticClient = baseClient { fetchTimesheet = \_ _ _ -> pure (Right remote) }

                response <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest diagnosticClient do
                        withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                            callActionWithParams
                                RunXeroTimesheetDiagnosticAction
                                [("submissionId", cs (inputValue submission.id))]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Submitted request"
                response `responseBodyShouldContain` "Stored Xero response"
                response `responseBodyShouldContain` "Current Xero draft"
                response `responseBodyShouldContain` "39.13"
                response `responseBodyShouldContain` cs (Text.take 16 (hashOpaqueToken "sensitive-earnings-rate-id"))
                let secrets :: [Text] = ["sensitive-timesheet-id", "sensitive-employee-id", "sensitive-earnings-rate-id", "Sensitive pay item name", "sensitive-access-token", "sensitive-tenant-id"]
                forM_ secrets \secret ->
                    response `responseBodyShouldNotContain` cs secret

                otherVenue <- createVenueWithConfig "Other Xero Diagnostic Venue"
                crossVenueResponse <- withXeroConfigForTest (Right testXeroConfig) do
                    withXeroClientForTest diagnosticClient do
                        withPasskeyVerifiedUserAndCurrentVenue founder otherVenue.id do
                            callActionWithParams
                                RunXeroTimesheetDiagnosticAction
                                [("submissionId", cs (inputValue submission.id))]
                crossVenueResponse `responseStatusShouldBe` status200
                crossVenueResponse `responseBodyShouldContain` "No Xero submission was found for the current support venue."
                forM_ secrets \secret ->
                    crossVenueResponse `responseBodyShouldNotContain` cs secret

                missingIdResponse <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callAction RunXeroTimesheetDiagnosticAction
                blankIdResponse <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callActionWithParams RunXeroTimesheetDiagnosticAction [("submissionId", "   ")]
                malformedIdResponse <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callActionWithParams RunXeroTimesheetDiagnosticAction [("submissionId", "not-a-uuid")]
                oversizedIdResponse <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callActionWithParams RunXeroTimesheetDiagnosticAction [("submissionId", ByteString.replicate 65 97)]
                forM_ [missingIdResponse, blankIdResponse, malformedIdResponse, oversizedIdResponse] \invalidResponse -> do
                    invalidResponse `responseStatusShouldBe` status200
                    invalidResponse `responseBodyShouldContain` "Enter a valid Bepis Xero submission ID."
                    forM_ secrets \secret ->
                        invalidResponse `responseBodyShouldNotContain` cs secret

        it "starts a signed impersonation session with distinct actual and effective context" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Context Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-actual@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-effective@example.com" "staff" True
                targetMembership <- createVenueMembershipRecord venue targetUser Manager
                targetStaff <- createStaffRecord venue (Just targetUser) "Effective" "User"

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    response <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]

                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Just targetUser.id
                    maybeSessionId <- fmap (>>= UUID.fromText) (getSession @Text impersonationSessionIdSessionKey)
                    maybeSessionId `shouldSatisfy` isJust

                    withCurrentControllerContext do
                        initImpersonationContext
                        (actualUserRecord actualAuthenticatedUser).id `shouldBe` superAdmin.id
                        (effectiveUserRecord effectiveRequestUser).id `shouldBe` targetUser.id
                        fmap (.id) effectiveVenueMembershipOrNothing `shouldBe` Just targetMembership.id
                        effectiveVenueRoleOrNothing `shouldBe` Just Manager
                        fmap (.id) effectiveStaffOrNothing `shouldBe` Just targetStaff.id
                        fmap impersonationSessionId currentImpersonationOrNothing `shouldBe` maybeSessionId

                    pure response

                response `responseStatusShouldBe` status302
                auditEvent <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_entered")
                    |> fetchOne
                auditEvent.actorUserId `shouldBe` unpackId superAdmin.id
                auditEvent.targetId `shouldBe` unpackId targetUser.id

        it "applies worker authorization and self-service ownership while impersonating" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Worker Authorization Impersonation Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-worker-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-effective-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue (Just worker) "Effective" "Worker"

                (adminResponse, profileResponse, rosterResponse) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue worker.id))]
                    adminResponse <- callAction AdminAction
                    profileResponse <- callAction EditProfileAction
                    rosterResponse <- callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                    pure (adminResponse, profileResponse, rosterResponse)

                adminResponse `responseStatusShouldBe` status302
                profileResponse `responseStatusShouldBe` status200
                profileResponse `responseBodyShouldContain` "impersonation-effective-worker@example.com"
                profileResponse `responseBodyShouldContain` "href=\"/Support\""
                profileResponse `responseBodyShouldContain` "support-venue-switch"
                profileResponse `responseBodyShouldNotContain` "href=\"/Admin\""
                profileResponse `responseBodyShouldNotContain` "href=\"/Xero\""
                rosterResponse `responseStatusShouldBe` status200
                rosterResponse `responseBodyShouldContain` "roster-staff-self-service-panel"

        it "applies the effective user's profile-completeness gate" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Gate Impersonation Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-profile-gate-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-incomplete-worker@example.com" "staff" False
                _ <- createVenueMembershipRecord venue worker Worker

                (rosterResponse, supportResponse, exitResponse) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue worker.id))]
                    rosterResponse <- callAction RosterWeeksAction
                    supportResponse <- callAction SupportAction
                    exitResponse <- callAction ExitSupportImpersonationAction
                    pure (rosterResponse, supportResponse, exitResponse)

                rosterResponse `responseStatusShouldBe` status302
                lookup "Location" (Wai.responseHeaders rosterResponse) `shouldBe` Just "http://localhost/EditProfile"
                supportResponse `responseStatusShouldBe` status200
                supportResponse `responseBodyShouldContain` "support-venue-switch"
                exitResponse `responseStatusShouldBe` status302

        it "does not let founder impersonation bypass worker roster-layout authority" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Preference Ownership Impersonation Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-preference-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-preference-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue (Just worker) "Preference" "Worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue worker.id))]
                    callActionWithParams
                        UpdateRosterLayoutPreferenceAction
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1"), ("rosterLayoutMode", "day_columns")]

                response `responseStatusShouldBe` status302
                venueConfig <- query @VenueConfig
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                venueConfig.rosterLayoutMode `shouldBe` DayRows
                query @UserPreference
                    |> filterWhere (#userId, unpackId worker.id)
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "allows unimpersonated founder support to change venue roster layout" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Founder Layout Venue"
                founder <- createUserRecordWithPlatformRole "layout-founder@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callActionWithParams
                        UpdateRosterLayoutPreferenceAction
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1"), ("rosterLayoutMode", "day_columns")]

                response `responseStatusShouldBe` status302
                venueConfig <- query @VenueConfig
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                venueConfig.rosterLayoutMode `shouldBe` DayColumns

        it "enforces the effective venue-role matrix across manager admin and owner routes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Role Matrix Impersonation Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-role-matrix-founder@example.com" "staff" (Just SuperAdmin) True
                roleTargets <- forM
                    [ (Worker, status302, status302, status302)
                    , (Supervisor, status302, status302, status302)
                    , (Manager, status200, status302, status302)
                    , (VenueAdmin, status200, status200, status302)
                    , (VenueOwner, status200, status200, status200)
                    ]
                    \(role, leaveStatus, adminStatus, xeroStatus) -> do
                        user <- createUserRecord ("impersonation-role-" <> inputValue role <> "@example.com") "staff" True
                        _ <- createVenueMembershipRecord venue user role
                        _ <- createStaffRecord venue (Just user) (inputValue role) "Target"
                        pure (user, leaveStatus, adminStatus, xeroStatus)

                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    forM_ roleTargets \(target, leaveStatus, adminStatus, xeroStatus) -> do
                        _ <- callActionWithParams
                            StartSupportImpersonationAction
                            [("userId", cs (inputValue target.id))]
                        leaveResponse <- callAction LeaveRequestsAction
                        adminResponse <- callAction AdminAction
                        xeroResponse <- callAction XeroAction
                        leaveResponse `responseStatusShouldBe` leaveStatus
                        adminResponse `responseStatusShouldBe` adminStatus
                        xeroResponse `responseStatusShouldBe` xeroStatus
                        _ <- callAction ExitSupportImpersonationAction
                        pure ()

        it "blocks credential management while preserving the effective profile" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Credential Boundary Impersonation Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-credential-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-credential-worker@example.com" "staff" True
                replacementUser <- createUserRecord "impersonation-session-replacement@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue (Just worker) "Credential" "Worker"

                (passkeyResponse, registrationResponse, userAccountResponse, sessionReplacementResponse, profileResponse) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue worker.id))]
                    passkeyResponse <- callAction PasskeySetupAction
                    registrationResponse <- callAction BeginPasskeyRegistrationAction
                    userAccountResponse <- callAction NewUserAction
                    sessionReplacementResponse <- callActionWithParams CreateSessionAction
                        [ ("email", cs replacementUser.email)
                        , ("password", cs testPassword)
                        ]
                    profileResponse <- callAction EditProfileAction
                    pure (passkeyResponse, registrationResponse, userAccountResponse, sessionReplacementResponse, profileResponse)

                passkeyResponse `responseStatusShouldBe` status302
                registrationResponse `responseStatusShouldBe` status403
                userAccountResponse `responseStatusShouldBe` status403
                sessionReplacementResponse `responseStatusShouldBe` status403
                profileResponse `responseStatusShouldBe` status200
                profileResponse `responseBodyShouldNotContain` "Sign-In Methods"
                profileResponse `responseBodyShouldContain` "impersonation-credential-worker@example.com"

        it "rejects client tampering with signed impersonation session material" $ withContext do
            key <- ClientSession.getKey "Config/client_session_key.aes"
            encrypted <- ClientSession.encryptIO key "supportImpersonationEffectiveUserId=target&supportImpersonationSessionId=session"
            let tampered =
                    ByteString.init encrypted
                        <> ByteString.singleton (ByteString.last encrypted `xor` 1)

            ClientSession.decrypt key encrypted `shouldSatisfy` isJust
            ClientSession.decrypt key tampered `shouldBe` Nothing

        it "renders active venue users in desktop and mobile impersonation selectors without emails" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Selector Venue"
                founder <- createUserRecordWithPlatformRole "selector-founder@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue founder VenueOwner
                founderStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId founder.id))
                    |> fetchOne
                _ <- founderStaff
                    |> set #firstName "Founder"
                    |> set #lastName "Support"
                    |> updateRecord
                worker <- createUserRecord "selector-ada-lovelace@example.com" "staff" True
                workerMembership <- createVenueMembershipRecord venue worker Worker
                workerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId worker.id))
                    |> fetchOne
                _ <- workerStaff
                    |> set #firstName "Ada"
                    |> set #lastName "Lovelace"
                    |> set #preferredName (Just "Ally")
                    |> updateRecord
                manager <- createUserRecord "selector-ada-byron@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId manager.id))
                    |> fetchOne
                _ <- managerStaff
                    |> set #firstName "Ada"
                    |> set #lastName "Byron"
                    |> set #preferredName (Just "Ally")
                    |> updateRecord
                inactiveUser <- createUserRecord "selector-inactive@example.com" "staff" True
                _ <- createVenueMembershipRecord venue inactiveUser Supervisor
                inactiveAt <- getCurrentTime
                _ <- inactiveUser |> set #deactivatedAt (Just inactiveAt) |> updateRecord
                userWithoutStaff <- createUserRecord "selector-no-staff@example.com" "staff" False
                _ <- createVenueMembershipRecord venue userWithoutStaff Supervisor
                inactiveMembershipUser <- createUserRecord "selector-archived@example.com" "staff" True
                inactiveMembership <- createVenueMembershipRecord venue inactiveMembershipUser VenueAdmin
                _ <- inactiveMembership
                    |> set #isActive False
                    |> set #archivedAt (Just inactiveAt)
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-impersonation-user\""
                response `responseBodyShouldContain` "id=\"support-impersonation-user-mobile\""
                response `responseBodyShouldContain` "hx-post=\"/SwitchSupportImpersonation\""
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                response `responseBodyShouldContain` "this.form.requestSubmit(); this.form.reset()"
                response `responseBodyShouldContain` "app-header-desktop-actions d-none d-xl-flex"
                response `responseBodyShouldContain` "app-mobile-menu-toggle d-xl-none"
                response `responseBodyShouldContain` "app-mobile-nav d-xl-none"
                response `responseBodyShouldContain` "Super admin"
                response `responseBodyShouldContain` "Founder — Venue Owner"
                response `responseBodyShouldContain` "Ally L. — Worker"
                response `responseBodyShouldContain` "Ally B. — Manager"
                response `responseBodyShouldContain` "Venue user — Supervisor"
                response `responseBodyShouldNotContain` worker.email
                response `responseBodyShouldNotContain` manager.email
                response `responseBodyShouldNotContain` userWithoutStaff.email
                response `responseBodyShouldNotContain` inactiveUser.email
                response `responseBodyShouldNotContain` inactiveMembershipUser.email
                workerMembership.venueRole `shouldBe` Worker

        it "switches effective users and exits through safe full-page return paths" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Selector Transition Venue"
                founder <- createUserRecordWithPlatformRole "selector-transition-founder@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "selector-transition-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Manager

                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    enterResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue targetUser.id))
                        , ("next", "/LeaveRequests?weekOffset=1")
                        ]
                    enterResponse `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (Wai.responseHeaders enterResponse)
                        `shouldBe` Just "http://localhost/LeaveRequests?weekOffset=1"
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Just targetUser.id
                    impersonationSessionId <- getSession @Text impersonationSessionIdSessionKey
                    impersonationSessionId `shouldSatisfy` isJust

                    exitResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", "")
                        , ("next", "/Timesheets")
                        ]
                    exitResponse `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (Wai.responseHeaders exitResponse)
                        `shouldBe` Just "http://localhost/Timesheets"
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                    forM_ ["https://evil.example/steal", "/\\evil.example/steal", "/\DEL/steal"] \unsafePath -> do
                        unsafeReturnResponse <- callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue targetUser.id))
                            , ("next", unsafePath)
                            ]
                        unsafeReturnResponse `responseStatusShouldBe` status302
                        lookup HTTP.hLocation (Wai.responseHeaders unsafeReturnResponse)
                            `shouldBe` Just "http://localhost/RosterWeeks"

                    missingNextResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    missingNextResponse `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (Wai.responseHeaders missingNextResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks"

        it "revalidates current-page returns after start, switch, and exit" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Return Authorization Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-return-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-return-worker@example.com" "staff" True
                owner <- createUserRecord "impersonation-return-owner@example.com" "staff" True
                incompleteOwner <- createUserRecord "impersonation-return-incomplete-owner@example.com" "staff" False
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue incompleteOwner VenueOwner

                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    startResponse <- callActionWithParams
                        StartSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/ShowRosterWindow?anchorDate=2026-08-10")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders startResponse)
                        `shouldBe` Just "http://localhost/ShowRosterWindow?anchorDate=2026-08-10"

                    supportFallbackResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/Support?section=security")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders supportFallbackResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks"

                    forM_ ["/Billing", "/Admin", "/Xero", "/ExportJobs", "/EditProfile?section=security", "/PasskeyStepUp", "/VerifyEmail?token=secret", "/UnknownPage"] \unavailablePath -> do
                        unavailableResponse <- callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue worker.id))
                            , ("next", unavailablePath)
                            ]
                        (unavailablePath, lookup HTTP.hLocation (Wai.responseHeaders unavailableResponse))
                            `shouldBe` (unavailablePath, Just "http://localhost/RosterWeeks")

                    forM_ ["/Billing/not-a-route", "/ShowRosterWindowGarbage", "/ShowRosterWindow?anchorDate=not-a-date", "/ShowRosterWindow?anchorDate=2026-08-10&rosterGroupId=not-a-uuid", "/ShowRosterWindow?anchorDate=2026-08-10&anchorDate=2026-08-11", "/ShowRosterWindow?anchorDate=2026-08-10&unexpected=value", "/ShowRosterWindow?anchorDate=2026-08-10&rosterView=invalid", "/ShowRosterWindow?anchorDate=2026-08-10&rosterView=timeline&dayOffset=1", "/RosterWeeks?rosterView"] \malformedPagePath -> do
                        malformedPageResponse <- callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue worker.id))
                            , ("next", malformedPagePath)
                            ]
                        lookup HTTP.hLocation (Wai.responseHeaders malformedPageResponse)
                            `shouldBe` Just "http://localhost/RosterWeeks"

                    incompleteOwnerResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue incompleteOwner.id))
                        , ("next", "/Billing")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders incompleteOwnerResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks"

                    ownerBillingResponse <- withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue owner.id))
                            , ("next", "/Billing")
                            ]
                    ownerBillingResponse `responseStatusShouldBe` status200
                    lookup "HX-Redirect" (Wai.responseHeaders ownerBillingResponse)
                        `shouldBe` Just "/Billing"

                    ownerBillingCancelResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue owner.id))
                        , ("next", "/BillingCancel?attempt_id=11111111-1111-1111-1111-111111111111")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders ownerBillingCancelResponse)
                        `shouldBe` Just "http://localhost/BillingCancel?attempt_id=11111111-1111-1111-1111-111111111111"

                    forM_ ["/Billing?unexpected=value", "/Billing?checkout=nope", "/Billing?checkout=success&attempt_id=not-a-uuid", "/LeaveRequests?archivePage=not-an-int"] \invalidOwnerPath -> do
                        invalidOwnerResponse <- callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue owner.id))
                            , ("next", invalidOwnerPath)
                            ]
                        lookup HTTP.hLocation (Wai.responseHeaders invalidOwnerResponse)
                            `shouldBe` Just "http://localhost/RosterWeeks"

                    ownerLeaveResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue owner.id))
                        , ("next", "/LeaveRequests?archivePage=2&openSection=archive&section=archive")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders ownerLeaveResponse)
                        `shouldBe` Just "http://localhost/LeaveRequests?archivePage=2&openSection=archive&section=archive"

                    forM_
                        [ "/ShowRosterTemplateReference?rosterGroupId=11111111-1111-1111-1111-111111111111&name=Weekly%20Template&scale=week"
                        , "/ShowRosterTemplateApplicationConfirmation?rosterTemplateId=22222222-2222-2222-2222-222222222222&rosterGroupId=11111111-1111-1111-1111-111111111111&targetDropzoneKey=day-1"
                        ]
                        \retiredTemplatePath -> do
                            retiredTemplateResponse <- callActionWithParams
                                SwitchSupportImpersonationAction
                                [ ("userId", cs (inputValue owner.id))
                                , ("next", retiredTemplatePath)
                                ]
                            lookup HTTP.hLocation (Wai.responseHeaders retiredTemplateResponse)
                                `shouldBe` Just "http://localhost/RosterWeeks"

                    workerTimesheetResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/ShowTimesheetWindow?anchorDate=2026-08-10&rosterGroupFilterId=11111111-1111-1111-1111-111111111111")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerTimesheetResponse)
                        `shouldBe` Just "http://localhost/ShowTimesheetWindow?anchorDate=2026-08-10&rosterGroupFilterId=11111111-1111-1111-1111-111111111111"

                    workerTimelineResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/ShowRosterWindow?anchorDate=2026-08-10&rosterView=timeline&dayDate=2026-08-11")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerTimelineResponse)
                        `shouldBe` Just "http://localhost/ShowRosterWindow?anchorDate=2026-08-10&rosterView=timeline&dayDate=2026-08-11"

                    workerRosterGroupResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/RosterWeeks?rosterGroupId=11111111-1111-1111-1111-111111111111")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerRosterGroupResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks?rosterGroupId=11111111-1111-1111-1111-111111111111"

                    workerHelpResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/ShowPageHelp?topic=roster")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerHelpResponse)
                        `shouldBe` Just "http://localhost/ShowPageHelp?topic=roster"

                    workerNewLeaveResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/NewLeaveRequest")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerNewLeaveResponse)
                        `shouldBe` Just "http://localhost/NewLeaveRequest"

                    workerFeedbackResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/NewFeedback")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders workerFeedbackResponse)
                        `shouldBe` Just "http://localhost/NewFeedback"

                    unknownHelpResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue worker.id))
                        , ("next", "/ShowPageHelp?topic=unknown")
                        ]
                    lookup HTTP.hLocation (Wai.responseHeaders unknownHelpResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks"

                    exitResponse <- callActionWithParams
                        ExitSupportImpersonationAction
                        [("next", "/Support?section=security")]
                    lookup HTTP.hLocation (Wai.responseHeaders exitResponse)
                        `shouldBe` Just "http://localhost/Support?section=security"

                    founderNewStaffResponse <- callActionWithParams
                        ExitSupportImpersonationAction
                        [("next", "/NewStaff?anchorDate=2026-08-10")]
                    lookup HTTP.hLocation (Wai.responseHeaders founderNewStaffResponse)
                        `shouldBe` Just "http://localhost/NewStaff?anchorDate=2026-08-10"

                    unknownExitResponse <- callActionWithParams
                        ExitSupportImpersonationAction
                        [("next", "/VerifyEmail?token=secret")]
                    lookup HTTP.hLocation (Wai.responseHeaders unknownExitResponse)
                        `shouldBe` Just "http://localhost/RosterWeeks"

        it "retains safe current-page context through passkey step-up without entering impersonation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Step-up Return Venue"
                founder <- createUserRecordWithPlatformRole "impersonation-step-up-return@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "impersonation-step-up-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                ensureTestUserHasPasskey founder

                (response, storedReturnPath, invalidResponse, invalidStoredReturnPath, effectiveUserId) <- withUserAndCurrentVenue founder venue.id do
                    response <- withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue worker.id))
                            , ("next", "/ShowRosterWindow?anchorDate=2026-08-10")
                            ]
                    storedReturnPath <- getSession @Text passkeyStepUpRedirectSessionKey
                    invalidResponse <- withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            SwitchSupportImpersonationAction
                            [ ("userId", cs (inputValue worker.id))
                            , ("next", "/Billing?checkout=nope")
                            ]
                    invalidStoredReturnPath <- getSession @Text passkeyStepUpRedirectSessionKey
                    effectiveUserId <- getSession @(Id User) effectiveUserSessionKey
                    pure (response, storedReturnPath, invalidResponse, invalidStoredReturnPath, effectiveUserId)

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (Wai.responseHeaders response)
                    `shouldBe` Just "http://localhost/ShowPasskeyStepUpDialog"
                storedReturnPath `shouldBe` Just "/ShowRosterWindow?anchorDate=2026-08-10"
                invalidResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (Wai.responseHeaders invalidResponse)
                    `shouldBe` Just "http://localhost/ShowPasskeyStepUpDialog"
                invalidStoredReturnPath `shouldBe` Just "/RosterWeeks"
                effectiveUserId `shouldBe` Nothing

        it "requires a fresh passkey verification before entering impersonation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Passkey Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-passkey@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-passkey-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker
                ensureTestUserHasPasskey superAdmin

                (entryResponse, selectorResponse) <- withUserAndCurrentVenue superAdmin venue.id do
                    entryResponse <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    selectorResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [ ("userId", cs (inputValue targetUser.id))
                        , ("next", "/RosterWeeks")
                        ]
                    pure (entryResponse, selectorResponse)

                entryResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (Wai.responseHeaders entryResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"
                selectorResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (Wai.responseHeaders selectorResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "denies ordinary users and cross-venue targets without creating session state" $ withContext do
            withCleanDb do
                selectedVenue <- createVenueWithConfig "Selected Impersonation Venue"
                otherVenue <- createVenueWithConfig "Other Impersonation Venue"
                ordinaryUser <- createUserRecord "impersonation-ordinary@example.com" "staff" True
                _ <- createVenueMembershipRecord selectedVenue ordinaryUser VenueOwner
                superAdmin <- createUserRecordWithPlatformRole "impersonation-cross-venue@example.com" "staff" (Just SuperAdmin) True
                crossVenueTarget <- createUserRecord "impersonation-cross-target@example.com" "staff" True
                _ <- createVenueMembershipRecord otherVenue crossVenueTarget Worker

                unauthenticatedResponse <- callAction StartSupportImpersonationAction
                getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                ordinaryResponse <- withPasskeyVerifiedUserAndCurrentVenue ordinaryUser selectedVenue.id do
                    response <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue ordinaryUser.id))]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    pure response
                unauthenticatedResponse `responseStatusShouldBe` status302
                ordinaryResponse `responseStatusShouldBe` status302

                (crossVenueResponse, selectorCrossVenueResponse) <- withPasskeyVerifiedUserAndCurrentVenue superAdmin selectedVenue.id do
                    crossVenueResponse <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue crossVenueTarget.id))]
                    selectorCrossVenueResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [("userId", cs (inputValue crossVenueTarget.id))]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure (crossVenueResponse, selectorCrossVenueResponse)
                crossVenueResponse `responseStatusShouldBe` status403
                selectorCrossVenueResponse `responseStatusShouldBe` status403

                query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_entered")
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "rejects missing and malformed impersonation target ids" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invalid Impersonation Target Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-invalid-target@example.com" "staff" (Just SuperAdmin) True

                (missingResponse, malformedResponse, selectorMalformedResponse) <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    missingResponse <- callAction StartSupportImpersonationAction
                    malformedResponse <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", "not-a-uuid")]
                    selectorMalformedResponse <- callActionWithParams
                        SwitchSupportImpersonationAction
                        [("userId", "not-a-uuid")]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure (missingResponse, malformedResponse, selectorMalformedResponse)

                missingResponse `responseStatusShouldBe` status403
                malformedResponse `responseStatusShouldBe` status403
                selectorMalformedResponse `responseStatusShouldBe` status403

        it "auto-exits when the effective membership is revoked" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Revoked Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-revoked@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-revoked-target@example.com" "staff" True
                membership <- createVenueMembershipRecord venue targetUser Manager

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    revokedAt <- getCurrentTime
                    _ <- membership
                        |> set #isActive False
                        |> set #archivedAt (Just revokedAt)
                        |> updateRecord

                    response <- callAction SupportAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure response

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support impersonation ended because the selected user is no longer available."
                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.actorUserId `shouldBe` unpackId superAdmin.id
                expiry.targetId `shouldBe` unpackId targetUser.id

        it "auto-exits when the effective user is deactivated" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Deactivated Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-deactivated@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-deactivated-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker

                withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    deactivatedAt <- getCurrentTime
                    _ <- targetUser
                        |> set #deactivatedAt (Just deactivatedAt)
                        |> set #deactivatedByUserId (Just superAdmin.id)
                        |> set #deactivationReason (Just "support test")
                        |> updateRecord

                    _ <- callAction SupportAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "audits expiry when the authenticated founder loses super-admin access" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Demoted Founder Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-demoted-founder@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-demoted-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Manager

                withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    _ <- superAdmin |> set #platformRole Nothing |> updateRecord

                    _ <- callAction SupportAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.venueId `shouldBe` unpackId venue.id
                expiry.actorUserId `shouldBe` unpackId superAdmin.id
                expiry.targetId `shouldBe` unpackId targetUser.id

        it "expires instead of migrating impersonation when the selected venue becomes inactive" $ withContext do
            withCleanDb do
                selectedVenue <- createVenueWithConfig "Inactive Selected Impersonation Venue"
                fallbackVenue <- createVenueWithConfig "Active Fallback Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-inactive-venue@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-multi-venue-target@example.com" "staff" True
                _ <- createVenueMembershipRecord selectedVenue targetUser Manager
                _ <- createVenueMembershipRecord fallbackVenue targetUser Manager

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin selectedVenue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    _ <- selectedVenue |> set #status Inactive |> updateRecord

                    response <- callAction SupportAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure response

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support impersonation ended because the selected venue is no longer available."
                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.venueId `shouldBe` unpackId selectedVenue.id
                expiry.targetId `shouldBe` unpackId targetUser.id
                expiry.payload `shouldSatisfy` \case
                    Aeson.Object fields -> AesonKeyMap.lookup "reason" fields == Just (Aeson.String "selected_venue_unavailable")
                    _ -> False

        it "auto-exits when the selected venue no longer exists" $ withContext do
            withCleanDb do
                fallbackVenue <- createVenueWithConfig "Fallback After Deleted Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-deleted-venue@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-deleted-venue-target@example.com" "staff" True
                let deletedVenueId = Id UUID.nil

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin deletedVenueId do
                    setSession effectiveUserSessionKey targetUser.id
                    setSession impersonationSessionIdSessionKey (UUID.toText UUID.nil)

                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support impersonation ended because the selected venue is no longer available."
                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.venueId `shouldBe` unpackId fallbackVenue.id
                expiry.targetId `shouldBe` unpackId targetUser.id

        it "clears effective identity on manual exit and venue switch" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Lifecycle Venue"
                nextVenue <- createVenueWithConfig "Impersonation Lifecycle Next Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-lifecycle@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-lifecycle-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Manager

                withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    exitResponse <- callAction ExitSupportImpersonationAction
                    exitResponse `responseStatusShouldBe` status302
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    _ <- callActionWithParams
                        SwitchSupportVenueAction
                        [ ("venueId", cs (inputValue nextVenue.id))
                        , ("next", "/Support")
                        ]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                exits <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_exited")
                    |> fetch
                length exits `shouldBe` 2

        it "rejects unauthenticated and ordinary-user impersonation exit requests" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Exit Access Venue"
                ordinaryUser <- createUserRecord "impersonation-exit-ordinary@example.com" "staff" True
                _ <- createVenueMembershipRecord venue ordinaryUser Worker

                unauthenticatedResponse <- callAction ExitSupportImpersonationAction
                ordinaryResponse <- withPasskeyVerifiedUserAndCurrentVenue ordinaryUser venue.id do
                    callAction ExitSupportImpersonationAction

                unauthenticatedResponse `responseStatusShouldBe` status302
                ordinaryResponse `responseStatusShouldBe` status302
                query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_exited")
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "clears effective identity on logout" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Logout Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-logout@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-logout-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker

                withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]
                    _ <- callAction DeleteSessionAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_exited")
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "restores the authenticated staff context immediately after exit" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Staff Restore Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-staff-actual@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue superAdmin VenueOwner
                actualStaff <- createStaffRecord venue (Just superAdmin) "Actual" "Founder"
                targetUser <- createUserRecord "impersonation-staff-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker
                _ <- createStaffRecord venue (Just targetUser) "Effective" "Target"

                withUserAndCurrentVenue superAdmin venue.id do
                    withCurrentControllerContext do
                        fmap (.id) effectiveStaffOrNothing `shouldBe` Just actualStaff.id
                        Just _ <- enterCurrentVenueImpersonation targetUser.id
                        _ <- exitCurrentImpersonation "test_exit"
                        fmap (.id) effectiveStaffOrNothing `shouldBe` Just actualStaff.id

        it "audits and clears malformed impersonation session state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Malformed Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-malformed@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-malformed-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    setSession effectiveUserSessionKey targetUser.id
                    setSession impersonationSessionIdSessionKey ("not-a-uuid" :: Text)
                    response <- callAction SupportAction
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure response

                response `responseStatusShouldBe` status200
                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.actorUserId `shouldBe` unpackId superAdmin.id
                expiry.targetId `shouldBe` unpackId targetUser.id
                expiry.payload `shouldBe`
                    Aeson.object
                        [ "reason" Aeson..= ("invalid_session_state" :: Text)
                        , "requestContext" Aeson..= Aeson.object
                            [ "accessMode" Aeson..= ("impersonation" :: Text)
                            , "effectiveUserId" Aeson..= targetUser.id
                            , "impersonationSessionId" Aeson..= ("not-a-uuid" :: Text)
                            ]
                        ]

        it "audits malformed impersonation state without an effective user id" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Malformed Session-Only Impersonation Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-session-only@example.com" "staff" (Just SuperAdmin) True

                withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    setSession impersonationSessionIdSessionKey ("stray-session-value" :: Text)
                    _ <- callAction SupportAction
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing

                expiry <- query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_expired")
                    |> fetchOne
                expiry.actorUserId `shouldBe` unpackId superAdmin.id
                expiry.targetId `shouldBe` unpackId superAdmin.id
                expiry.payload `shouldBe`
                    Aeson.object
                        [ "reason" Aeson..= ("invalid_session_state" :: Text)
                        , "requestContext" Aeson..= Aeson.object
                            [ "accessMode" Aeson..= ("impersonation" :: Text)
                            , "effectiveUserId" Aeson..= Aeson.Null
                            , "impersonationSessionId" Aeson..= ("stray-session-value" :: Text)
                            ]
                        ]

        it "mounts support live surface metadata for super admins" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-surface-super@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support mode"
                response `responseBodyShouldContain` "data-bepis-surface=\"support\""
                response `responseBodyShouldContain` "id=\"support-award-rates\""
                response `responseBodyShouldContain` "hx-target=\"#support-award-rates\""
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                response `responseBodyShouldContain` "hx-target=\"#support-public-holidays\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-public-holiday-refresh-job\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-fwc-mapd-refresh-job\""

        it "does not label a super-admin venue membership as support mode" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Super Admin Member Venue"
                superAdmin <- createUserRecordWithPlatformRole "support-member-super@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue superAdmin VenueOwner

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support venue"
                response `responseBodyShouldNotContain` "Support mode"

        it "shows submitted feedback without the submit-feedback button for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Support Venue"
                submitter <- createUserRecord "feedback-support-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-support-super@example.com" "staff" (Just SuperAdmin) True
                _ <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType Bug
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Roster page needs a clearer publish button"
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "User Feedback"
                response `responseBodyShouldContain` "Roster page needs a clearer publish button"
                response `responseBodyShouldContain` "feedback-support-user@example.com"
                response `responseBodyShouldContain` "Unread feedback: <span class=\"fw-semibold\">1</span>"
                response `responseBodyShouldContain` ">Info</summary>"
                response `responseBodyShouldContain` "Page</dt>"
                response `responseBodyShouldContain` "Not reported"
                response `responseBodyShouldNotContain` "hx-get=\"/NewFeedback\""

        it "shows captured feedback diagnostics inline" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Diagnostics Venue"
                submitter <- createUserRecord "feedback-diagnostics-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-diagnostics-super@example.com" "staff" (Just SuperAdmin) True
                _ <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType Bug
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Diagnostics are available"
                    |> set #submittedPath (Just "/LeaveRequests")
                    |> set #userAgent (Just "FeedbackBrowser/1.0")
                    |> set #submittedRole (Just "venue_admin")
                    |> set #viewportWidth (Just 390)
                    |> set #viewportHeight (Just 844)
                    |> set #devicePixelRatio (Just 2.625)
                    |> set #deviceClass (Just "mobile")
                    |> set #displayMode (Just "standalone")
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Feedback Diagnostics Venue"
                response `responseBodyShouldContain` "/LeaveRequests"
                response `responseBodyShouldContain` "FeedbackBrowser/1.0"
                response `responseBodyShouldContain` "Venue admin"
                response `responseBodyShouldContain` "390 × 844"
                response `responseBodyShouldContain` "2.625"
                response `responseBodyShouldContain` "Mobile"
                response `responseBodyShouldContain` "Standalone PWA"

        it "marks feedback read for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Read Venue"
                submitter <- createUserRecord "feedback-read-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-read-super@example.com" "staff" (Just SuperAdmin) True
                feedbackItem <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType Suggestion
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Make the copy week action clearer"
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction (MarkFeedbackReadAction feedbackItem.id)

                response `responseStatusShouldBe` status302
                updatedFeedback <- fetch feedbackItem.id
                updatedFeedback.readAt `shouldSatisfy` isJust
                updatedFeedback.readByUserId `shouldBe` Just (unpackId superAdmin.id)

        it "routes support refresh mutations through touched resources" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-mutation-super@example.com" "staff" (Just SuperAdmin) True
                versionBefore <- currentLiveUpdateVersion supportSurfaceScope

                response <- withPasskeyVerifiedUser superAdmin do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction CreatePublicHolidayRefreshJobAction
                versionAfter <- currentLiveUpdateVersion supportSurfaceScope

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                versionAfter `shouldBe` versionBefore

        it "deduplicates concurrent award-rate refresh enqueues without 500s" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-concurrent-super@example.com" "staff" (Just SuperAdmin) True
                ensureTestUserHasPasskey superAdmin

                results <- runConcurrentActionsImmediately 12 do
                    withPasskeyVerifiedUser superAdmin do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction CreateFwcMapdRefreshJobAction

                let failures = lefts results
                failures `shouldSatisfy` null
                let responses = rights results
                length responses `shouldBe` 12
                mapM_ (`responseStatusShouldBe` status200) responses

                activeJobs <- query @AppJob
                    |> filterWhere (#jobKind, fwcMapdRefreshJobKind)
                    |> filterWhereIn (#status, activeAppJobStatuses)
                    |> fetch
                length activeJobs `shouldBe` 1
