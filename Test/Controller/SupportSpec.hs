module Test.Controller.SupportSpec where

import Application.Async.Queue (activeAppJobStatuses)
import Application.FwcMapd.Job (fwcMapdRefreshJobKind)
import Application.Helper.ControllerContext
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.Impersonation
import Application.Helper.LiveUpdate
import Application.Support.LiveUpdates
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Bits (xor)
import qualified Data.ByteString as ByteString
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
import Test.Support.SurfaceContract
import qualified Web.ClientSession as ClientSession
import Web.Controller.Support ()
import Web.FrontController ()
import Web.Types

supportFragmentRef :: SupportLiveFragment -> FrontendSurfaceMountedFragment
supportFragmentRef fragment =
    case filter ((== supportLiveFragmentKey fragment) . (.mountedFragmentKey)) supportCandidateMountedFragments of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support mounted fragment"

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "SupportController" do
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

        it "rejects client tampering with signed impersonation session material" $ withContext do
            key <- ClientSession.getKey "Config/client_session_key.aes"
            encrypted <- ClientSession.encryptIO key "supportImpersonationEffectiveUserId=target&supportImpersonationSessionId=session"
            let tampered =
                    ByteString.init encrypted
                        <> ByteString.singleton (ByteString.last encrypted `xor` 1)

            ClientSession.decrypt key encrypted `shouldSatisfy` isJust
            ClientSession.decrypt key tampered `shouldBe` Nothing

        it "requires a fresh passkey verification before entering impersonation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Passkey Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-passkey@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-passkey-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Worker
                ensureTestUserHasPasskey superAdmin

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue targetUser.id))]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (Wai.responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

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

                crossVenueResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin selectedVenue.id do
                    response <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue crossVenueTarget.id))]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure response
                crossVenueResponse `responseStatusShouldBe` status403

                query @AuditEvent
                    |> filterWhere (#eventType, "support_impersonation_entered")
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "rejects missing and malformed impersonation target ids" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invalid Impersonation Target Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-invalid-target@example.com" "staff" (Just SuperAdmin) True

                (missingResponse, malformedResponse) <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    missingResponse <- callAction StartSupportImpersonationAction
                    malformedResponse <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", "not-a-uuid")]
                    getSession @(Id User) effectiveUserSessionKey `shouldReturn` Nothing
                    getSession @Text impersonationSessionIdSessionKey `shouldReturn` Nothing
                    pure (missingResponse, malformedResponse)

                missingResponse `responseStatusShouldBe` status403
                malformedResponse `responseStatusShouldBe` status403

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
                    |> set #feedbackType "bug"
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
                    |> set #feedbackType "bug"
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
                    |> set #feedbackType "suggestion"
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

                results <- runConcurrentActions 12 do
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

runConcurrentActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentActions count action = do
    vars <- mapM (const newEmptyMVar) [1 .. count]
    _ <- mapM (\var -> forkIO (try action >>= putMVar var)) vars
    mapM takeMVar vars
