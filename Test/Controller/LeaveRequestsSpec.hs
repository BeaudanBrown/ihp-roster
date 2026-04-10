module Test.Controller.LeaveRequestsSpec where

import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import Config
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.LeaveRequests ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "LeaveRequestsController" do
        it "redirects unauthenticated users from leave requests page" $ withContext do
            response <- callAction LeaveRequestsAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from leave requests fragment page" $ withContext do
            response <- callAction ShowLeaveRequestsContentFragmentAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from new leave request page" $ withContext do
            response <- callAction NewLeaveRequestAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from create leave request action" $ withContext do
            response <- callAction CreateLeaveRequestAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from approve leave action" $ withContext do
            let requestId = "00000000-0000-0000-0000-000000000000" :: Id LeaveRequest
            response <- callAction ApproveLeaveRequestAction { leaveRequestId = requestId }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from deny leave action" $ withContext do
            let requestId = "00000000-0000-0000-0000-000000000000" :: Id LeaveRequest
            response <- callAction DenyLeaveRequestAction { leaveRequestId = requestId }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from delete leave action" $ withContext do
            let requestId = "00000000-0000-0000-0000-000000000000" :: Id LeaveRequest
            response <- callAction DeleteLeaveRequestAction { leaveRequestId = requestId }
            response `responseStatusShouldBe` status302

        it "approving leave invalidates affected roster week scopes only in the current venue" $ withContext do
            withCleanDb do
                let staleTimestamp = UTCTime (fromGregorian 2024 12 1) (secondsToDiffTime 0)
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                rosterGroupA <- ensureVenueDefaultRosterGroup venueA
                rosterGroupB <- ensureVenueDefaultRosterGroup venueB
                manager <- createUserRecord "leave-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                staffA <- createStaffRecord venueA Nothing "Ava" "Leave"
                rosterWeekA <- createRosterWeekRecord venueA 0 False >>= updateRecord . set #updatedAt staleTimestamp
                rosterWeekA1 <- createRosterWeekRecord venueA 1 False >>= updateRecord . set #updatedAt staleTimestamp
                rosterWeekB <- createRosterWeekRecord venueB 0 False >>= updateRecord . set #updatedAt staleTimestamp
                leaveRequest <- createLeaveRequestRecord venueA staffA (fromGregorian 2025 1 8) (fromGregorian 2025 1 15) "pending"

                versionA0Before <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueA.id, rosterGroupId = unpackId rosterGroupA.id, weekOffset = 0 }
                versionA1Before <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueA.id, rosterGroupId = unpackId rosterGroupA.id, weekOffset = 1 }
                versionB0Before <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueB.id, rosterGroupId = unpackId rosterGroupB.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue manager venueA.id do
                    callAction ApproveLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                versionA0After <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueA.id, rosterGroupId = unpackId rosterGroupA.id, weekOffset = 0 }
                versionA1After <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueA.id, rosterGroupId = unpackId rosterGroupA.id, weekOffset = 1 }
                versionB0After <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venueB.id, rosterGroupId = unpackId rosterGroupB.id, weekOffset = 0 }
                refreshedWeekA <- fetch rosterWeekA.id
                refreshedWeekA1 <- fetch rosterWeekA1.id
                refreshedWeekB <- fetch rosterWeekB.id

                versionA0After `shouldBe` versionA0Before + 1
                versionA1After `shouldBe` versionA1Before + 1
                versionB0After `shouldBe` versionB0Before
                refreshedWeekA.updatedAt `shouldBe` staleTimestamp
                refreshedWeekA1.updatedAt `shouldBe` staleTimestamp
                refreshedWeekB.updatedAt `shouldBe` staleTimestamp

        it "renders a subscribed leave shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createStaffRecord venue (Just user) "Shell" "Viewer"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-feature=\"leave-requests\""
                response `responseBodyShouldContain` "data-live-update-client-enabled=\"true\""
                response `responseBodyShouldContain` "data-live-update-scope-kind=\"leave_requests\""
                response `responseBodyShouldContain` "id=\"leave-requests-content\""

        it "denies the leave review page to ordinary staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-staff-blocked@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Blocked" "Worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status403

        it "renders HTMX leave forms with javascript submission disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Liv" "Form"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction NewLeaveRequestAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""

        it "renders explicit delete forms instead of js-delete links for authenticated leave pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-delete-form@example.com" "staff" True
                workerUser <- createUserRecord "leave-delete-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Delia" "Viewer"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 13) (fromGregorian 2025 1 14) "pending"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (pathTo (DeleteLeaveRequestAction leaveRequest.id))
                response `responseBodyShouldContain` cs (pathTo DeleteSessionAction)
                response `responseBodyShouldContain` "name=\"_method\" value=\"DELETE\""
                response `responseBodyShouldNotContain` "js-delete"

        it "renders manager accordion headings with counts inline after the title" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-manager-headings@example.com" "staff" True
                workerUser <- createUserRecord "leave-worker-headings@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Hana" "Headings"
                _ <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "pending"
                _ <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 11) (fromGregorian 2025 1 12) "pending"
                _ <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 13) (fromGregorian 2025 1 14) "approved"
                _ <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 15) (fromGregorian 2025 1 16) "denied"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending (2)"
                response `responseBodyShouldContain` "Approved (1)"
                response `responseBodyShouldContain` "Denied (1)"
                response `responseBodyShouldNotContain` "Needs a decision"
                response `responseBodyShouldNotContain` "Already confirmed"
                response `responseBodyShouldNotContain` "Rejected requests"

        it "renders manager accordions with zero counts instead of empty-state copy when there are no leave requests" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-manager-empty@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending (0)"
                response `responseBodyShouldContain` "Approved (0)"
                response `responseBodyShouldContain` "Denied (0)"
                response `responseBodyShouldNotContain` "No leave requests yet."
                response `responseBodyShouldNotContain` "No requests in this section."

        it "scopes leave fragment refetches to the current viewer visibility" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-fragment-manager@example.com" "staff" True
                workerAUser <- createUserRecord "leave-fragment-worker-a@example.com" "staff" True
                workerBUser <- createUserRecord "leave-fragment-worker-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                _ <- createVenueMembershipRecord venue workerBUser "worker"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Viewer"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Viewer"
                _ <- createLeaveRequestRecord venue workerA (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "pending"
                _ <- createLeaveRequestRecord venue workerB (fromGregorian 2025 1 11) (fromGregorian 2025 1 12) "pending"

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowLeaveRequestsContentFragmentAction
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowLeaveRequestsContentFragmentAction

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Ava Viewer"
                managerResponse `responseBodyShouldContain` "Bea Viewer"
                workerResponse `responseStatusShouldBe` status403

        it "denying previously approved leave invalidates the affected roster week scope" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                rosterGroup <- ensureVenueDefaultRosterGroup venue
                manager <- createUserRecord "leave-deny-live-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                _ <- createRosterWeekRecord venue 0 False
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "approved"

                versionBefore <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId rosterGroup.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction DenyLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                versionAfter <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId rosterGroup.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

        it "creating leave via HTMX updates the actor fragment and bumps the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Liv" "Create"

                versionBefore <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "leave-create-client")
                        ] do
                            callActionWithParams CreateLeaveRequestAction
                                [ ("startDate", "2025-01-13")
                                , ("endDate", "2025-01-14")
                                , ("notes", "Family event")
                                , ("responseContext", "profile")
                                , ("section", "leave")
                                ]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldContain` "id=\"profile-leave-requests-list-fragment\" hx-swap-oob=\"outerHTML\""
                bodyText `shouldContain` "Leave request submitted"
                bodyText `shouldContain` "Submitted Requests"
                bodyText `shouldNotContain` "id=\"profile-content-fragment\""
                bodyText `shouldNotContain` "id=\"profile-leave-requests-content\""

                versionAfter <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` versionBefore + 1

        it "returns the profile leave fragment instead of redirecting when no staff record exists on profile leave submit" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-profile-no-staff@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", "2025-01-13")
                            , ("endDate", "2025-01-14")
                            , ("notes", "Family event")
                            , ("responseContext", "profile")
                            , ("section", "leave")
                            ]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldContain` "No staff record found. Contact an administrator."
                bodyText `shouldNotContain` "id=\"profile-content-fragment\""
                bodyText `shouldNotContain` "id=\"profile-leave-requests-content\""

        it "infers profile leave context from the HTMX target when responseContext is missing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-profile-target-inference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createStaffRecord venue (Just user) "Admin" "Crew"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("HX-Target", "profile-leave-request-form-fragment")
                        ] do
                            callActionWithParams CreateLeaveRequestAction
                                [ ("startDate", "2025-01-13")
                                , ("endDate", "2025-01-14")
                                , ("notes", "HTMX target inference")
                                ]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldContain` "id=\"profile-leave-requests-list-fragment\" hx-swap-oob=\"outerHTML\""
                bodyText `shouldContain` "HTMX target inference"
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                bodyText `shouldNotContain` "Pending ("

        it "manager review actions bump the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "pending"

                versionBefore <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "leave-approve-client")] do
                        callAction ApproveLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "id=\"leave-requests-content\""
                bodyText `shouldNotContain` "id=\"leave-requests-content\" hx-swap-oob="
                versionAfter <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` versionBefore + 1

        it "deleting leave via HTMX bumps the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-htmx-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Del" "Own"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 13) (fromGregorian 2025 1 14) "pending"

                versionBefore <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "leave-delete-client")] do
                        callActionWithParams (DeleteLeaveRequestAction leaveRequest.id)
                            [ ("responseContext", "profile")
                            , ("section", "leave")
                            ]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldContain` "id=\"profile-leave-requests-list-fragment\" hx-swap-oob=\"outerHTML\""
                versionAfter <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId venue.id }
                versionAfter `shouldBe` versionBefore + 1

        it "writes an audit event when approving a leave request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-approve@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Ava" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "pending"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ApproveLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                updatedLeaveRequest <- fetch leaveRequest.id
                inputValue updatedLeaveRequest.status `shouldBe` "approved"

                leaveEvent <- query @LeaveRequestEvent |> fetchOne
                inputValue leaveEvent.eventType `shouldBe` "approved"
                fmap inputValue leaveEvent.previousStatus `shouldBe` Just "pending"
                fmap inputValue leaveEvent.newStatus `shouldBe` Just "approved"

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId manager.id
                auditEvent.eventType `shouldBe` "leave_approved"
                auditEvent.targetTable `shouldBe` "leave_requests"
                auditEvent.targetId `shouldBe` unpackId leaveRequest.id

        it "writes an audit event when denying a leave request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-deny@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 11) (fromGregorian 2025 1 12) "pending"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction DenyLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                updatedLeaveRequest <- fetch leaveRequest.id
                inputValue updatedLeaveRequest.status `shouldBe` "denied"

                leaveEvent <- query @LeaveRequestEvent |> fetchOne
                inputValue leaveEvent.eventType `shouldBe` "denied"
                fmap inputValue leaveEvent.previousStatus `shouldBe` Just "pending"
                fmap inputValue leaveEvent.newStatus `shouldBe` Just "denied"

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "leave_denied"
                auditEvent.targetId `shouldBe` unpackId leaveRequest.id

        it "writes a leave event when creating a leave request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Liv" "Create"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams CreateLeaveRequestAction
                        [ ("startDate", "2025-01-13")
                        , ("endDate", "2025-01-14")
                        , ("notes", "Family event")
                        ]

                response `responseStatusShouldBe` status302

                leaveEvent <- query @LeaveRequestEvent |> fetchOne
                inputValue leaveEvent.eventType `shouldBe` "created"
                leaveEvent.previousStatus `shouldBe` Nothing
                fmap inputValue leaveEvent.newStatus `shouldBe` Just "pending"

        it "writes an audit event when deleting a pending leave request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Del" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 13) (fromGregorian 2025 1 14) "pending"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction DeleteLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                remainingCount <- query @LeaveRequest |> fetchCount
                remainingCount `shouldBe` 0

                leaveEvent <- query @LeaveRequestEvent |> fetchOne
                inputValue leaveEvent.eventType `shouldBe` "deleted"
                fmap inputValue leaveEvent.previousStatus `shouldBe` Just "pending"
                leaveEvent.newStatus `shouldBe` Nothing

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "leave_deleted"
                auditEvent.targetId `shouldBe` unpackId leaveRequest.id

        it "blocks deleting a reviewed leave request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-reviewed-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Rev" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 15) (fromGregorian 2025 1 16) "approved"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction DeleteLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                remainingCount <- query @LeaveRequest |> fetchCount
                remainingCount `shouldBe` 1

                leaveEventCount <- query @LeaveRequestEvent |> fetchCount
                leaveEventCount `shouldBe` 0
