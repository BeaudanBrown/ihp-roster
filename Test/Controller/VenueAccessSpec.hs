{-# LANGUAGE TypeApplications #-}

module Test.Controller.VenueAccessSpec where

import Application.Async.Queue (EnqueueAppJobResult (EnqueuedAppJob))
import Application.EmailDelivery
import Application.FwcMapd.Job (fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Controller (currentVenueSessionKey,
                                      initCurrentVenueContext)
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import qualified Application.Helper.FrontendContract.Surface.Billing.Live as BillingLive
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Live as LeaveLive
import qualified Application.Helper.FrontendContract.Surface.Profile.Live as ProfileLive
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import qualified Application.Helper.FrontendContract.Surface.Support.Live as SupportLive
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as TimesheetsLive
import Application.Helper.LiveUpdate
import Application.InvitationDelivery.Enqueue (enqueueVenueOnboardingInvitationEmail)
import Application.PublicHolidays.Job (publicHolidayRefreshJobKind)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, try)
import Control.Monad (zipWithM)
import Data.Coerce (coerce)
import qualified Data.Serialize as Serialize
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime, diffUTCTime, getCurrentTime)
import Generated.Types
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import IHP.Controller.Context (ControllerContext, newControllerContext)
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.LoginSupport.Middleware (initAuthentication)
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import qualified Network.Wai as Wai
import Test.Hspec
import Test.Support
import Web.Controller.Admin ()
import Web.Controller.LeaveRequests ()
import Web.Controller.RosterWeeks ()
import Web.Controller.Sessions ()
import Web.Controller.Staff ()
import Web.Controller.Support ()
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.SurfaceInvalidation (authorizeSurfaceScope)
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Venue-scoped access control" do
        it "denies editing a staff record from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-a@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager Manager
                foreignStaff <- createStaffRecord venueB Nothing "Brie" "Foreign"

                response <- withUser manager do
                    callActionWithParams (EditStaffAction foreignStaff.id) [("anchorDate", "2025-01-06")]

                response `responseStatusShouldBe` status403

        it "denies approving a timesheet entry from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-timesheet@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager Manager
                foreignStaff <- createStaffRecord venueB Nothing "Tia" "Outside"
                foreignEntry <- createTimesheetEntryRecord venueB foreignStaff defaultWeekEpoch

                response <- withUser manager do
                    callAction ApproveTimesheetEntryAction { timesheetEntryId = foreignEntry.id }

                response `responseStatusShouldBe` status403

        it "denies approving a leave request from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-leave@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager Manager
                foreignStaff <- createStaffRecord venueB Nothing "Lea" "Outside"
                foreignLeave <- createLeaveRequestRecord venueB foreignStaff defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending

                response <- withUser manager do
                    callAction ApproveLeaveRequestAction { leaveRequestId = foreignLeave.id }

                response `responseStatusShouldBe` status403

        it "denies Publishing a roster window from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-roster@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager Manager
                foreignWeek <- createRosterWeekRecord venueB 0 False

                response <- withUser manager do
                    callActionWithParams
                        ToggleRosterWeekLiveStatusAction
                        [ ("anchorDate", "2025-01-06")
                        , ("rosterGroupId", idToParam (Id foreignWeek.fixtureRosterGroupId :: Id RosterGroup))
                        , ("rosterCalendarRevision", "1")
                        , ("isLive", "true")
                        ]

                response `responseStatusShouldBe` status403

        it "denies updating a roster slot from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-slot@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager Manager
                foreignWeek <- createRosterWeekRecord venueB 0 False
                foreignDay <- createRosterDayRecord foreignWeek 0
                foreignSlotName <- fetchSlotNameRecord venueB "Late"
                foreignSlot <- createRosterSlotRecord foreignDay foreignSlotName Nothing 0

                response <- withUser manager do
                    callActionWithParams (UpdateRosterSlotAction foreignSlot.id) [("startTime", "09:00")]

                response `responseStatusShouldBe` status403

    describe "Venue membership authority" do
        it "does not let users.user_role bypass admin access checks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUser user do
                    callAction AdminAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "does not let users.user_role bypass manager-only roster actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-manager-bypass@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user Worker
                rosterWeek <- createRosterWeekRecord venue 0 False

                response <- withUser user do
                    callAction ToggleRosterWeekLiveStatusAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "does not let venue managers subscribe to admin roster-group live scopes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "manager-live-admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                authorized <- withAuthenticatedControllerContext manager venue.id do
                    authorizeSurfaceScope (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))

                authorized `shouldBe` False

        it "lets venue admins subscribe to admin live scopes for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "admin-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                rosterGroupsAuthorized <- withAuthenticatedControllerContext admin venue.id do
                    authorizeSurfaceScope (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                invitesAuthorized <- withAuthenticatedControllerContext admin venue.id do
                    authorizeSurfaceScope (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                exportsAuthorized <- withAuthenticatedControllerContext admin venue.id do
                    authorizeSurfaceScope (AdminLive.adminExportsLiveScope (unpackId venue.id))

                rosterGroupsAuthorized `shouldBe` True
                invitesAuthorized `shouldBe` True
                exportsAuthorized `shouldBe` True

        it "lets current-venue users subscribe to ordinary live scopes for their venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Worker" "Live"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                rosterAuthorized <- withAuthenticatedControllerContext user venue.id do
                    authorizeSurfaceScope (RosterLive.rosterWeekLiveScope (unpackId venue.id) (unpackId rosterGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                leaveAuthorized <- withAuthenticatedControllerContext user venue.id do
                    authorizeSurfaceScope (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))
                timesheetAuthorized <- withAuthenticatedControllerContext user venue.id do
                    authorizeSurfaceScope (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                profileAuthorized <- withAuthenticatedControllerContext user venue.id do
                    authorizeSurfaceScope (ProfileLive.profileLiveScope (unpackId venue.id) (unpackId staff.id))

                rosterAuthorized `shouldBe` True
                leaveAuthorized `shouldBe` False
                timesheetAuthorized `shouldBe` True
                profileAuthorized `shouldBe` True

        it "does not let users subscribe to live scopes for another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-foreign-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueAdmin
                rosterGroupB <- query @RosterGroup |> filterWhere (#venueId, unpackId venueB.id) |> fetchOne
                foreignStaff <- createStaffRecord venueB Nothing "Foreign" "Staff"

                rosterAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (RosterLive.rosterWeekLiveScope (unpackId venueB.id) (unpackId rosterGroupB.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                adminXeroAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (AdminLive.adminXeroLiveScope (unpackId venueB.id))
                billingAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (BillingLive.billingVenueLiveScope (unpackId venueB.id))
                leaveAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (LeaveLive.leaveRequestsLiveScope (unpackId venueB.id))
                timesheetAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (TimesheetsLive.timesheetWeekLiveScope (unpackId venueB.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                profileAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (ProfileLive.profileLiveScope (unpackId venueB.id) (unpackId foreignStaff.id))

                rosterAuthorized `shouldBe` False
                adminXeroAuthorized `shouldBe` False
                billingAuthorized `shouldBe` False
                leaveAuthorized `shouldBe` False
                timesheetAuthorized `shouldBe` False
                profileAuthorized `shouldBe` False

        it "does not let users subscribe to another user's profile live scope" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-profile-live-scope@example.com" "staff" True
                otherUser <- createUserRecord "other-profile-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createVenueMembershipRecord venue otherUser Worker
                otherStaff <- createStaffRecord venue (Just otherUser) "Other" "Profile"

                authorized <- withAuthenticatedControllerContext user venue.id do
                    authorizeSurfaceScope (ProfileLive.profileLiveScope (unpackId venue.id) (unpackId otherStaff.id))

                authorized `shouldBe` False

        it "does not let users combine their venue id with another venue's roster group in live scopes" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-mixed-roster-group-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueAdmin
                rosterGroupB <- query @RosterGroup |> filterWhere (#venueId, unpackId venueB.id) |> fetchOne

                rosterAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (RosterLive.rosterWeekLiveScope (unpackId venueA.id) (unpackId rosterGroupB.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                adminRosterGroupsAuthorized <- withAuthenticatedControllerContext admin venueA.id do
                    authorizeSurfaceScope (AdminLive.adminRosterGroupsLiveScope (unpackId venueA.id))

                rosterAuthorized `shouldBe` False
                adminRosterGroupsAuthorized `shouldBe` True

        it "lets super-admins subscribe to the support live scope without an active venue" $ withContext do
            withCleanDb do
                founder <- createUserRecordWithPlatformRole "founder-support-live@example.com" "staff" (Just SuperAdmin) True

                authorized <- withAuthenticatedControllerContextNoVenue founder do
                    authorizeSurfaceScope SupportLive.supportPlatformLiveScope

                authorized `shouldBe` True

        it "does not let ordinary users subscribe to the support live scope" $ withContext do
            withCleanDb do
                user <- createUserRecord "ordinary-support-live@example.com" "staff" True

                authorized <- withAuthenticatedControllerContextNoVenue user do
                    authorizeSurfaceScope SupportLive.supportPlatformLiveScope

                authorized `shouldBe` False

        it "lets super-admin bypass venue membership for admin screens in another active venue" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                supportVenue <- createVenueWithConfig "Support Venue"
                founder <- createUserRecordWithPlatformRole "founder-support@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                _ <- createStaffRecord supportVenue (Just founder) "Support" "Founder"

                response <- withPasskeyVerifiedUserAndCurrentVenue founder supportVenue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"

        it "denies the support page to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withUser admin do
                    callAction SupportAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "lets super-admin open the support page and see active venues" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-support-page@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner
                _ <- createTestPasskeyRecord founder "Support laptop"

                response <- withPasskeyVerifiedUser founder do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Switch Venue"
                response `responseBodyShouldNotContain` "Current support venue"
                response `responseBodyShouldContain` "Invite Venue Owner"
                response `responseBodyShouldNotContain` "Create Venue"
                response `responseBodyShouldNotContain` "Roster window start day"
                response `responseBodyShouldContain` "Sign-In Methods"
                response `responseBodyShouldContain` "Support laptop"
                response `responseBodyShouldNotContain` "Add passkey"
                response `responseBodyShouldContain` "Award Rates"
                response `responseBodyShouldContain` "Refresh award rates"
                response `responseBodyShouldNotContain` "data-success-redirect=\"/Support\""
                response `responseBodyShouldNotContain` "href=\"/EditProfile\">profile</a>"

        it "lets bootstrap super-admin open support before any venue exists" $ withContext do
            withCleanDb do
                founder <- createUserRecordWithPlatformRole "founder-empty-support@example.com" "staff" (Just SuperAdmin) True

                response <- withUser founder do
                    let ?request = ?request { Wai.rawPathInfo = "/Support" }
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Support"
                response `responseBodyShouldContain` "Invite Venue Owner"
                response `responseBodyShouldContain` "Create passkey"
                response `responseBodyShouldContain` "successRedirect=%2FSupport"
                response `responseBodyShouldNotContain` "Create Venue"
                response `responseBodyShouldContain` "data-bepis-surface=\""
                response `responseBodyShouldContain` "support"

        it "lets super-admin queue an award rate refresh from support" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-award-refresh@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                response <- withPasskeyVerifiedUser founder do
                    callAction CreateFwcMapdRefreshJobAction

                response `responseStatusShouldBe` status302

                job <- query @AppJob |> filterWhere (#jobKind, fwcMapdRefreshJobKind) |> fetchOne

                job.dedupeKey `shouldBe` Just fwcMapdRefreshJobDedupeKey
                job.requestedByUserId `shouldBe` Just (unpackId founder.id)
                inputValue job.status `shouldBe` "job_status_not_started"

        it "returns the award rate section for HTMX award refresh submissions" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-award-refresh-htmx@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                response <- withPasskeyVerifiedUser founder do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction CreateFwcMapdRefreshJobAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-award-rates\""
                response `responseBodyShouldContain` "Refresh queued/running"
                response `responseBodyShouldContain` "hx-post=\"/CreateFwcMapdRefreshJob\""

        it "does not add active-job polling to the award rate support section" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-award-refresh-fragment@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                _ <- withPasskeyVerifiedUser founder do
                    callAction CreateFwcMapdRefreshJobAction

                response <- withPasskeyVerifiedUser founder do
                    callAction ShowFwcMapdAwardRatesSectionAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-award-rates\""
                response `responseBodyShouldNotContain` "hx-get=\"/ShowFwcMapdAwardRatesSection\""
                response `responseBodyShouldNotContain` "hx-trigger=\"load delay:2s\""
                response `responseBodyShouldContain` "Refresh queued/running"

        it "deduplicates active award rate refresh jobs" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-award-refresh-dedupe@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                _ <- withPasskeyVerifiedUser founder do
                    callAction CreateFwcMapdRefreshJobAction
                response <- withPasskeyVerifiedUser founder do
                    callAction CreateFwcMapdRefreshJobAction

                response `responseStatusShouldBe` status302
                jobCount <- query @AppJob |> filterWhere (#jobKind, fwcMapdRefreshJobKind) |> fetchCount
                jobCount `shouldBe` 1

        it "denies award rate refresh creation to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin-award-refresh@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withUser admin do
                    callAction CreateFwcMapdRefreshJobAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                jobCount <- query @AppJob |> filterWhere (#jobKind, fwcMapdRefreshJobKind) |> fetchCount
                jobCount `shouldBe` 0

        it "deduplicates active public holiday refresh jobs" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-public-holiday-refresh-dedupe@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                _ <- withPasskeyVerifiedUser founder do
                    callAction CreatePublicHolidayRefreshJobAction
                response <- withPasskeyVerifiedUser founder do
                    callAction CreatePublicHolidayRefreshJobAction

                response `responseStatusShouldBe` status302
                jobCount <- query @AppJob |> filterWhere (#jobKind, publicHolidayRefreshJobKind) |> fetchCount
                jobCount `shouldBe` 1

        it "returns the public holiday section for HTMX public holiday refresh submissions" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-public-holiday-refresh-htmx@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                response <- withPasskeyVerifiedUser founder do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction CreatePublicHolidayRefreshJobAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                response `responseBodyShouldContain` "Refresh queued/running"
                response `responseBodyShouldContain` "hx-post=\"/CreatePublicHolidayRefreshJob\""

        it "denies public holiday refresh creation to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin-public-holiday-refresh@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withUser admin do
                    callAction CreatePublicHolidayRefreshJobAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                jobCount <- query @AppJob |> filterWhere (#jobKind, publicHolidayRefreshJobKind) |> fetchCount
                jobCount `shouldBe` 0

        it "lets super-admin create a venue owner onboarding invitation" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-create-owner-invite@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                beforeCreate <- getCurrentTime
                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams CreateSupportVenueOnboardingInvitationAction
                        [ ("email", "new-owner@example.com")
                        ]

                response `responseStatusShouldBe` status302

                invitation <- query @VenueOnboardingInvitation |> filterWhere (#email, "new-owner@example.com") |> fetchOne

                invitation.invitedByUserId `shouldBe` Just (unpackId founder.id)
                inputValue invitation.status `shouldBe` "pending"
                invitation.expiresAt `shouldSatisfy` maybe False (\expiresAt ->
                    let remaining = diffUTCTime expiresAt beforeCreate
                     in remaining > 13 * 24 * 60 * 60 && remaining <= 14 * 24 * 60 * 60 + 5)

        it "rejects registered accounts and ordinary pending invitations with one owner-invite conflict" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Owner Invite Conflict Home Venue"
                invitedVenue <- createVenueWithConfig "Owner Invite Conflict Invited Venue"
                founder <- createUserRecordWithPlatformRole "founder-owner-conflict@example.com" "staff" (Just SuperAdmin) True
                registered <- createUserRecord "registered-owner-conflict@example.com" "staff" True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                _ <- createVenueInvitationRecord invitedVenue Nothing "pending-owner-conflict@example.com" Worker

                responses <- withPasskeyVerifiedUser founder do
                    forM [registered.email, "pending-owner-conflict@example.com"] \email ->
                        callActionWithParams CreateSupportVenueOnboardingInvitationAction [("email", cs email)]

                forM_ responses \response -> do
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "This email already has an account or pending invitation."
                query @VenueOnboardingInvitation |> fetchCount >>= (`shouldBe` 0)

        it "renews an owner onboarding invitation with a corrected two-week replacement" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-renew-owner-invite@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                now <- getCurrentTime
                original <-
                    createVenueOnboardingInvitationRecord (Just founder) "mistyped-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))
                EnqueuedEmailDelivery originalJob <- enqueueVenueOnboardingInvitationEmail (Just founder.id) original

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                        [ ("email", "  Corrected-Owner@Example.com  ")
                        ]

                response `responseStatusShouldBe` status302
                replacedInvitation <- fetch original.id
                inputValue replacedInvitation.status `shouldBe` "revoked"

                freshInvitation <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "corrected-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchOne
                freshInvitation.id `shouldNotBe` original.id
                freshInvitation.invitedByUserId `shouldBe` Just (unpackId founder.id)
                freshInvitation.expiresAt `shouldSatisfy` maybe False (\expiresAt ->
                    let remaining = diffUTCTime expiresAt now
                     in remaining > 13 * 24 * 60 * 60 && remaining <= 14 * 24 * 60 * 60 + 5)

                jobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "venue_onboarding_invitations")
                    |> fetch
                freshJob <- jobs
                    |> find ((== Just (unpackId freshInvitation.id)) . (.relatedId))
                    |> maybe (expectationFailure "fresh invitation delivery job missing" >> error "unreachable") pure
                freshJob.dedupeKey `shouldNotBe` originalJob.dedupeKey

                oldLinkResponse <- callActionWithParams NewVenueOnboardingUserAction
                    [("invitationId", idToParam original.id)]
                oldLinkResponse `responseStatusShouldBe` status200
                oldLinkResponse `responseBodyShouldContain` "no longer valid"

                freshLinkResponse <- callActionWithParams NewVenueOnboardingUserAction
                    [("invitationId", idToParam freshInvitation.id)]
                freshLinkResponse `responseStatusShouldBe` status200
                freshLinkResponse `responseBodyShouldContain` "Create Your Venue"
                freshLinkResponse `responseBodyShouldContain` "corrected-owner@example.com"

        it "handles concurrent renewal requests without duplicate replacements or 500s" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-concurrent-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                ensureTestUserHasPasskey founder
                original <- createVenueOnboardingInvitationRecord (Just founder) "concurrent-owner@example.com"

                results <- runConcurrentVenueAccessActions 12 do
                    withPasskeyVerifiedUser founder do
                        callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                            [("email", "replacement-owner@example.com")]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)

                replacements <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "replacement-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetch
                length replacements `shouldBe` 1
                jobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "venue_onboarding_invitations")
                    |> fetch
                length jobs `shouldBe` 1

        it "serializes different owner invitations renewed to the same corrected email" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-target-email-renewal-race@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                ensureTestUserHasPasskey founder
                firstOriginal <- createVenueOnboardingInvitationRecord (Just founder) "first-original-owner@example.com"
                secondOriginal <- createVenueOnboardingInvitationRecord (Just founder) "second-original-owner@example.com"

                results <- runConcurrentVenueAccessActionList
                    [ withPasskeyVerifiedUser founder do
                        callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                            [("email", "shared-corrected-owner@example.com")]
                    | original <- [firstOriginal, secondOriginal]
                    ]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)
                replacements <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "shared-corrected-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetch
                length replacements `shouldBe` 1
                originals <- query @VenueOnboardingInvitation
                    |> filterWhereIn (#id, [firstOriginal.id, secondOriginal.id])
                    |> fetch
                length (filter ((== "revoked") . inputValue . (.status)) originals) `shouldBe` 2
                query @AppJob
                    |> filterWhere (#relatedTable, Just "venue_onboarding_invitations")
                    |> fetchCount
                    >>= (`shouldBe` 2)

        it "serializes owner acceptance against renewal so only one link can win" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-acceptance-renewal-race@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                ensureTestUserHasPasskey founder
                invitation <- createVenueOnboardingInvitationRecord (Just founder) "acceptance-renewal-race@example.com"
                let signupParams =
                        [ ("invitationId", idToParam invitation.id)
                        , ("passwordHash", "test-password-123")
                        , ("passwordConfirmation", "test-password-123")
                        , ("name", "Acceptance Renewal Race Venue")
                        , ("rosterWeekStartsOn", "1")
                        , ("firstName", "Race")
                        , ("lastName", "Owner")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Emergency Contact")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "3")
                        ]

                results <- runConcurrentVenueAccessActionList
                    [ callActionWithParams CreateVenueOnboardingUserAction signupParams
                    , withPasskeyVerifiedUser founder do
                        callActionWithParams (RenewSupportVenueOnboardingInvitationAction invitation.id)
                            [("email", "acceptance-renewal-replacement@example.com")]
                    ]

                lefts results `shouldSatisfy` null
                mapM_ (\response -> Wai.responseStatus response `shouldSatisfy` (`elem` [status200, status302])) (rights results)

                finalInvitation <- fetch invitation.id
                replacementCount <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "acceptance-renewal-replacement@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchCount
                venueCount <- query @Venue |> filterWhere (#name, "Acceptance Renewal Race Venue") |> fetchCount
                case inputValue finalInvitation.status of
                    "accepted" -> do
                        replacementCount `shouldBe` 0
                        venueCount `shouldBe` 1
                    "revoked" -> do
                        replacementCount `shouldBe` 1
                        venueCount `shouldBe` 0
                    unexpectedStatus -> expectationFailure ("unexpected race status: " <> cs unexpectedStatus)

        it "serializes queued delivery against renewal" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-delivery-renewal-race@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                ensureTestUserHasPasskey founder
                invitation <- createVenueOnboardingInvitationRecord (Just founder) "delivery-renewal-race@example.com"
                EnqueuedEmailDelivery appJob <- enqueueVenueOnboardingInvitationEmail (Just founder.id) invitation

                let performDelivery = withFrameworkConfig config \frameworkConfig -> do
                        let ?context = frameworkConfig
                        performEmailDeliveryJobWith venueAccessEmailRuntime appJob
                results <- runConcurrentVenueAccessActionList
                    [ performDelivery >> pure status200
                    , withPasskeyVerifiedUser founder do
                        response <- callActionWithParams (RenewSupportVenueOnboardingInvitationAction invitation.id)
                            [("email", "delivery-renewal-replacement@example.com")]
                        pure (Wai.responseStatus response)
                    ]

                lefts results `shouldSatisfy` null
                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.status `shouldBe` "revoked"
                updatedInvitation.deliveredAt `shouldSatisfy` maybe True (<= updatedInvitation.updatedAt)
                query @VenueOnboardingInvitation
                    |> filterWhere (#email, "delivery-renewal-replacement@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "replaces existing pending owner invitations when renewing to the same email" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-conflicting-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                original <- createVenueOnboardingInvitationRecord (Just founder) "original-owner@example.com"
                _ <- createVenueOnboardingInvitationRecord (Just founder) "existing-owner@example.com"

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                        [("email", "EXISTING-owner@example.com")]

                response `responseStatusShouldBe` status302
                replacedOriginal <- fetch original.id
                inputValue replacedOriginal.status `shouldBe` "revoked"
                invitations <- query @VenueOnboardingInvitation |> fetch
                length invitations `shouldBe` 3
                length (filter ((== InvitationStatusEnumPending) . (.status)) invitations) `shouldBe` 1
                query @AppJob |> filterWhere (#relatedTable, Just "venue_onboarding_invitations") |> fetchCount >>= (`shouldBe` 1)

        it "rejects blank, malformed, and oversized corrected emails without revoking the original" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-invalid-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner

                let invalidEmails =
                        [ Just "   "
                        , Just "not-an-email"
                        , Just (Text.replicate 300 "a" <> "@example.com")
                        ]
                forM_ (zip [1 :: Int ..] invalidEmails) \(index, maybeInvalidEmail) -> do
                    original <- createVenueOnboardingInvitationRecord (Just founder) ("invalid-renewal-" <> tshow index <> "@example.com")

                    response <- withPasskeyVerifiedUser founder do
                        case maybeInvalidEmail of
                            Nothing -> callAction (RenewSupportVenueOnboardingInvitationAction original.id)
                            Just invalidEmail -> callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                                [("email", cs invalidEmail)]

                    response `responseStatusShouldBe` status302
                    unchangedOriginal <- fetch original.id
                    inputValue unchangedOriginal.status `shouldBe` "pending"

                query @VenueOnboardingInvitation |> fetchCount >>= (`shouldBe` 3)
                query @AppJob |> filterWhere (#relatedTable, Just "venue_onboarding_invitations") |> fetchCount >>= (`shouldBe` 0)

        it "renews with the original email when no corrected email is submitted" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-same-email-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                original <- createVenueOnboardingInvitationRecord (Just founder) "same-email-owner@example.com"

                response <- withPasskeyVerifiedUser founder do
                    callAction (RenewSupportVenueOnboardingInvitationAction original.id)

                response `responseStatusShouldBe` status302
                replacedOriginal <- fetch original.id
                inputValue replacedOriginal.status `shouldBe` "revoked"
                replacement <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "same-email-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchOne
                replacement.id `shouldNotBe` original.id

        it "replaces an expired pending invite already using the corrected email" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-expired-target-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                now <- getCurrentTime
                original <- createVenueOnboardingInvitationRecord (Just founder) "source-owner@example.com"
                expiredTarget <-
                    createVenueOnboardingInvitationRecord (Just founder) "expired-target-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams (RenewSupportVenueOnboardingInvitationAction original.id)
                        [("email", "expired-target-owner@example.com")]

                response `responseStatusShouldBe` status302
                replacedOriginal <- fetch original.id
                replacedTarget <- fetch expiredTarget.id
                inputValue replacedOriginal.status `shouldBe` "revoked"
                inputValue replacedTarget.status `shouldBe` "revoked"
                query @VenueOnboardingInvitation
                    |> filterWhere (#email, "expired-target-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "does not replace an accepted owner onboarding invitation" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-accepted-owner-renewal@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                now <- getCurrentTime
                acceptedInvitation <-
                    createVenueOnboardingInvitationRecord (Just founder) "accepted-renewal@example.com"
                        >>= updateRecord
                            . set #status (Accepted)
                            . set #acceptedAt (Just now)

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams (RenewSupportVenueOnboardingInvitationAction acceptedInvitation.id)
                        [("email", "replacement-for-accepted@example.com")]

                response `responseStatusShouldBe` status302
                unchangedInvitation <- fetch acceptedInvitation.id
                inputValue unchangedInvitation.status `shouldBe` "accepted"
                query @VenueOnboardingInvitation |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> filterWhere (#relatedTable, Just "venue_onboarding_invitations") |> fetchCount >>= (`shouldBe` 0)

        it "normalizes and replaces duplicate pending venue owner onboarding invitations" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-duplicate-owner-invite@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                _ <- createVenueOnboardingInvitationRecord (Just founder) "duplicate-owner@example.com"

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams CreateSupportVenueOnboardingInvitationAction
                        [ ("email", "  DUPLICATE-OWNER@example.com  ")
                        ]

                response `responseStatusShouldBe` status302
                invitations <- query @VenueOnboardingInvitation |> fetch
                length invitations `shouldBe` 2
                let matchingInvitations = filter ((== "duplicate-owner@example.com") . Text.toLower . Text.strip . (.email)) invitations
                length (filter ((== InvitationStatusEnumPending) . (.status)) matchingInvitations) `shouldBe` 1
                length (filter ((== Revoked) . (.status)) matchingInvitations) `shouldBe` 1

        it "allows a new venue owner onboarding invitation after the prior invite was accepted" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-accepted-owner-invite@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                now <- getCurrentTime
                _ <- createVenueOnboardingInvitationRecord (Just founder) "accepted-owner@example.com"
                    >>= updateRecord
                        . set #status (Accepted)
                        . set #acceptedAt (Just now)

                response <- withPasskeyVerifiedUser founder do
                    callActionWithParams CreateSupportVenueOnboardingInvitationAction
                        [ ("email", "Accepted-Owner@Example.com")
                        ]

                response `responseStatusShouldBe` status302
                newInvitation <- query @VenueOnboardingInvitation
                    |> filterWhere (#email, "accepted-owner@example.com")
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchOne
                newInvitation.invitedByUserId `shouldBe` Just (unpackId founder.id)

        it "shows recent venue owner invites with delivery state on the support page" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-owner-invite-list@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                _ <-
                    createVenueOnboardingInvitationRecord (Just founder) "listed-owner@example.com"
                        >>= updateRecord
                            . set #deliveryStatus (Sent)

                response <- withPasskeyVerifiedUser founder do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "listed-owner@example.com"
                response `responseBodyShouldContain` "Sent"

        it "shows expired owner invitations with a corrected-email renewal control" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-expired-owner-invite-list@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord homeVenue founder VenueOwner
                now <- getCurrentTime
                _ <-
                    createVenueOnboardingInvitationRecord (Just founder) "expired-listed-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))

                response <- withPasskeyVerifiedUser founder do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Expired"
                response `responseBodyShouldContain` "/RenewSupportVenueOnboardingInvitation"
                response `responseBodyShouldContain` "value=\"expired-listed-owner@example.com\""

        it "denies venue owner onboarding invitation renewal to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                founder <- createUserRecordWithPlatformRole "founder-renewal-target@example.com" "staff" (Just SuperAdmin) True
                admin <- createUserRecord "venue-admin-owner-renewal@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                invitation <- createVenueOnboardingInvitationRecord (Just founder) "blocked-renewal@example.com"

                response <- withUser admin do
                    callActionWithParams (RenewSupportVenueOnboardingInvitationAction invitation.id)
                        [("email", "changed-by-admin@example.com")]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                unchangedInvitation <- fetch invitation.id
                inputValue unchangedInvitation.status `shouldBe` "pending"
                query @VenueOnboardingInvitation |> fetchCount >>= (`shouldBe` 1)

        it "denies venue owner onboarding invitation creation to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin-owner-invite@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withUser admin do
                    callActionWithParams CreateSupportVenueOnboardingInvitationAction
                        [ ("email", "blocked-owner@example.com")
                        ]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                invitationCount <- query @VenueOnboardingInvitation |> filterWhere (#email, "blocked-owner@example.com") |> fetchCount
                invitationCount `shouldBe` 0

    describe "Current venue selection" do
        it "stores the earliest active membership venue during beforeLogin" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-login@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user Worker
                _ <- createVenueMembershipRecord venueB user Worker

                selectedVenueId <- withControllerTestContext do
                    Sessions.beforeLogin @User user
                    getSession @(Id Venue) currentVenueSessionKey

                selectedVenueId `shouldBe` Just venueA.id

        it "stores the requested active venue during beforeLogin for a super-admin without memberships" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-login@example.com" "staff" (Just SuperAdmin) True

                selectedVenueId <- withControllerTestContext do
                    Sessions.beforeLogin @User founder
                    getSession @(Id Venue) currentVenueSessionKey

                selectedVenueId `shouldBe` Just venueA.id

        it "uses the earliest active membership when no current venue session exists" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-request@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user Manager
                _ <- createVenueMembershipRecord venueB user Manager
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending

                response <- withUser user do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Alpha Person"
                response `responseBodyShouldNotContain` "Beta Person"

        it "honors the current venue session when resolving request context" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-session@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user Manager
                _ <- createVenueMembershipRecord venueB user Manager
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending

                response <- withUserAndCurrentVenue user venueB.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Beta Person"
                response `responseBodyShouldNotContain` "Alpha Person"

        it "allows the support switch action for super-admin and redirects back to support" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "/LeaveRequests")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/LeaveRequests"

        it "preserves venue-independent roster landing options after a support switch" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-roster-options@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "/RosterWeeks?rosterView=timeline")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks?rosterView=timeline"

        it "drops unsupported offset roster return paths after a support switch" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-roster-week@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                forM_
                    [ "/ShowRosterWeek?weekOffset=3"
                    , "/ShowRosterWeek?weekOffset=3&note=hello%20world"
                    , "/ShowRosterWeek?weekOffset=3&note=one%26two"
                    , "/ShowRosterWeek?weekOffset=3&note=left%3Dright"
                    , "/ShowRosterWeek?weekOffset=3&note=100%25"
                    , "/ShowRosterWeek?weekOffset=3&note="
                    , "/ShowRosterWeek?weekOffset=3&token=abc.def_123"
                    ] \nextPath -> do
                        response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                            callActionWithParams SwitchSupportVenueAction
                                [ ("venueId", cs (tshow venueB.id))
                                , ("next", nextPath)
                                ]

                        response `responseStatusShouldBe` status302
                        lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "drops the previous venue roster scope when redirecting after a support switch" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-roster@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "drops a malformed previous venue roster scope without replaying it" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-malformed-roster@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                forM_ ["", "%20", "%26", "%3D", "%25", "abc.def_123", "%ZZ"] \rosterGroupIdValue -> do
                    response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                        callActionWithParams SwitchSupportVenueAction
                            [ ("venueId", cs (tshow venueB.id))
                            , ("next", "/ShowRosterWeek?weekOffset=0&rosterGroupId=" <> rosterGroupIdValue)
                            ]

                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "falls back to support when given an unsafe redirect target" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-unsafe@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "https://evil.example.com/")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/Support"

        it "honors a foreign current venue session for super-admin without requiring a membership" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-session@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venueA founder VenueOwner
                _ <- createStaffRecord venueB (Just founder) "Beta" "Founder"
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venueB.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Beta Person"
                response `responseBodyShouldNotContain` "Alpha Person"

    describe "Venue-scoped manager queries" do
        it "shows only current-venue leave requests on the leave requests page" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-leave-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager Manager
                staffA <- createStaffRecord venueA Nothing "Ava" "Leave"
                staffB <- createStaffRecord venueB Nothing "Bea" "Leave"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) LeaveRequestStatusEnumPending

                response <- withUser manager do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Leave"
                response `responseBodyShouldNotContain` "Bea Leave"

        it "shows only current-venue timesheet entries on the weekly timesheets page" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-timesheet-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager Manager
                staffA <- createStaffRecord venueA (Just manager) "Ava" "Hours"
                staffBUser <- createUserRecord "venue-b-timesheet-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueB staffBUser Worker
                staffB <- createStaffRecord venueB (Just staffBUser) "Bea" "Hours"
                _ <- createTimesheetEntryRecord venueA staffA defaultWeekEpoch
                _ <- createTimesheetEntryRecord venueB staffB defaultWeekEpoch

                response <- withUser manager do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Hours"
                response `responseBodyShouldNotContain` "Bea Hours"

        it "shows only current-venue staff in the roster staff panel" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-roster-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager Manager
                _ <- createVenueMembershipRecord venueB manager Manager
                _ <- createRosterWeekRecord venueA 0 False
                _ <- createRosterWeekRecord venueB 0 False
                linkedUserA <- createUserRecord "alpha-staff@example.com" "staff" True
                linkedUserB <- createUserRecord "beta-staff@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA linkedUserA Worker
                _ <- createVenueMembershipRecord venueB linkedUserB Worker
                _ <- createStaffRecord venueA (Just linkedUserA) "Alpha" "Crew"
                _ <- createStaffRecord venueB (Just linkedUserB) "Beta" "Crew"

                response <- withUser manager do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-staff-panel"
                response `responseBodyShouldNotContain` "Beta Crew"

        it "uses only current-venue slot names when materializing a roster window" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-slot-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager Manager
                _ <- forM ["Early", "Mid", "Late"] (fetchSlotNameRecord venueA)
                _ <- forM ["Early", "Mid", "Late"] (fetchSlotNameRecord venueB)

                response <- withUser manager do
                    callActionWithParams CreateRosterWeekAction (rosterMutationParams 0)

                response `responseStatusShouldBe` status302

                rosterDays <- query @RosterDay
                    |> filterWhere (#venueId, unpackId venueA.id)
                    |> fetch
                rosterLanes <- query @RosterLane
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                otherVenueDays <- query @RosterDay
                    |> filterWhere (#venueId, unpackId venueB.id)
                    |> fetch

                length rosterDays `shouldBe` 7
                nub (map (.name) rosterLanes) `shouldMatchList` ["Early", "Mid", "Late"]
                otherVenueDays `shouldBe` []

runConcurrentVenueAccessActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentVenueAccessActions count action =
    runConcurrentVenueAccessActionList (replicate count action)

runConcurrentVenueAccessActionList :: [IO a] -> IO [Either SomeException a]
runConcurrentVenueAccessActionList actions = do
    resultVars <- mapM (const newEmptyMVar) actions
    readyVars <- mapM (const newEmptyMVar) actions
    startVar <- newEmptyMVar
    _ <- zipWithM (\resultVar (readyVar, action) -> forkIO do
            putMVar readyVar ()
            _ <- readMVar startVar
            try action >>= putMVar resultVar
        ) resultVars (zip readyVars actions)
    mapM_ takeMVar readyVars
    putMVar startVar ()
    mapM takeMVar resultVars

venueAccessEmailRuntime :: EmailDeliveryRuntime
venueAccessEmailRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail = \_ -> pure ()
        }

withAuthenticatedControllerContext ::
    forall result.
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request, ?modelContext :: ModelContext) =>
    User ->
    Id Venue ->
    ((?context :: ControllerContext) => IO result) ->
    IO result
withAuthenticatedControllerContext user venueId action =
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        , (currentVenueSessionKey, Serialize.encode venueId)
        ]
        do
            let ?frameworkConfig = config
            controllerContext <- newControllerContext
            let ?context = controllerContext
            initAuthentication @User
            initCurrentVenueContext
            action

withAuthenticatedControllerContextNoVenue ::
    forall result.
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request, ?modelContext :: ModelContext) =>
    User ->
    ((?context :: ControllerContext) => IO result) ->
    IO result
withAuthenticatedControllerContextNoVenue user action =
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        ]
        do
            let ?frameworkConfig = config
            controllerContext <- newControllerContext
            let ?context = controllerContext
            initAuthentication @User
            initCurrentVenueContext
            action
