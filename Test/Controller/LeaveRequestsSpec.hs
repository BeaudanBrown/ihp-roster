module Test.Controller.LeaveRequestsSpec where

import Application.Helper.Controller (LeaveRequestStatus (LeavePending),
                                      PlatformRole (SuperAdminRole))
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Live as LeaveLive
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffLeaveRequestsResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (affectedVenueWeekOffsetsForDateRange)
import Config
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), getCurrentTime, secondsToDiffTime,
                        utctDay)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.FrontController ()
import Web.LeaveRequests.Mutations (LeaveReviewDecision (..),
                                    leaveReviewTouchedResources)
import Web.LeaveRequests.ReadModel (affectedRosterWeekInvalidationTargetsForScopes)
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "LeaveRequestsController" do
        it "redirects unauthenticated users from leave requests page" $ withContext do
            response <- callAction LeaveRequestsAction
            response `responseStatusShouldBe` status302

        it "redirects venue-less super-admins from leave to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "leave-bootstrap-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUser user do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "redirects unauthenticated users from leave requests fragment page" $ withContext do
            response <- callAction ShowleaveRequestsContentLiveFragmentAction
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

        it "selects leave roster invalidation targets from active roster week scopes in the current venue" $ withContext do
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
                venueConfigA <- query @VenueConfig |> filterWhere (#venueId, unpackId venueA.id) |> fetchOne
                let activeTargets =
                        affectedRosterWeekInvalidationTargetsForScopes
                            venueA.id
                            venueConfigA
                            leaveRequest
                            [ (unpackId venueA.id, unpackId rosterGroupA.id, 0)
                            , (unpackId venueA.id, unpackId rosterGroupA.id, 1)
                            , (unpackId venueB.id, unpackId rosterGroupB.id, 0)
                            ]
                activeTargets `shouldBe` [(rosterGroupA.id, 0), (rosterGroupA.id, 1)]

                versionA0Before <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueA.id) (unpackId rosterGroupA.id) 0)
                versionA1Before <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueA.id) (unpackId rosterGroupA.id) 1)
                versionB0Before <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueB.id) (unpackId rosterGroupB.id) 0)

                response <- withUserAndCurrentVenue manager venueA.id do
                    callAction ApproveLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                versionA0After <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueA.id) (unpackId rosterGroupA.id) 0)
                versionA1After <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueA.id) (unpackId rosterGroupA.id) 1)
                versionB0After <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venueB.id) (unpackId rosterGroupB.id) 0)
                refreshedWeekA <- fetch rosterWeekA.id
                refreshedWeekA1 <- fetch rosterWeekA1.id
                refreshedWeekB <- fetch rosterWeekB.id

                versionA0After `shouldBe` versionA0Before
                versionA1After `shouldBe` versionA1Before
                versionB0After `shouldBe` versionB0Before
                refreshedWeekA.updatedAt `shouldBe` staleTimestamp
                refreshedWeekA1.updatedAt `shouldBe` staleTimestamp
                refreshedWeekB.updatedAt `shouldBe` staleTimestamp

        it "records touched resources for approved leave mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Touched Leave Venue"
                manager <- createUserRecord "leave-touched-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Touched" "Staff"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 15) "pending"
                Set.fromList (leaveReviewTouchedResources (fromGregorian 2025 1 10) ApproveLeave (Just LeavePending) leaveRequest)
                    `shouldBe` Set.fromList
                        [ pendingLeaveRequestsResource (unpackId venue.id)
                        , approvedLeaveRequestsResource (unpackId venue.id)
                        , staffLeaveRequestsResource leaveRequest.staffId
                        ]
                Set.fromList (leaveReviewTouchedResources (fromGregorian 2025 1 16) ApproveLeave (Just LeavePending) leaveRequest)
                    `shouldBe` Set.fromList
                        [ archivedLeaveRequestsResource (unpackId venue.id)
                        , staffLeaveRequestsResource leaveRequest.staffId
                        ]

        it "renders a subscribed leave shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createStaffRecord venue (Just user) "Shell" "Viewer"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"leave-requests\""
                response `responseBodyShouldContain` "leave-requests-content"
                response `responseBodyShouldContain` "id=\"leave-requests-content\""

        it "denies the leave review page to ordinary staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-staff-blocked@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Blocked" "Worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "lets super-admin review leave without self-service leave creation" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Support Leave Venue"
                superAdmin <- createUserRecordWithPlatformRole "leave-super-admin@example.com" "staff" (Just SuperAdminRole) True
                worker <- createStaffRecord venue Nothing "Liv" "Worker"
                _ <- createLeaveRequestRecord venue worker (addDays 10 today) (addDays 12 today) "pending"

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending (1)"
                response `responseBodyShouldContain` "Approve"
                response `responseBodyShouldContain` "hx-swap=\"none\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"approve-leave-request\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"deny-leave-request\""
                response `responseBodyShouldNotContain` "Add unavailable time"

        it "denies super-admin self-service leave creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Leave Create Venue"
                superAdmin <- createUserRecordWithPlatformRole "leave-create-super-admin@example.com" "staff" (Just SuperAdminRole) True

                newResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction NewLeaveRequestAction

                createResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams CreateLeaveRequestAction
                        [ ("startDate", "2025-01-08")
                        , ("endDate", "2025-01-10")
                        , ("notes", "No staff identity")
                        ]

                newResponse `responseStatusShouldBe` status302
                createResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders newResponse) `shouldBe` Just "http://localhost/Support"
                lookup "Location" (responseHeaders createResponse) `shouldBe` Just "http://localhost/Support"
                leaveExists <- query @LeaveRequest |> filterWhere (#venueId, unpackId venue.id) |> fetchExists
                leaveExists `shouldBe` False

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
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"

        it "rejects missing required leave dates without creating a row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Required Venue"
                user <- createUserRecord "leave-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Liv" "Required"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("endDate", "2025-01-10")
                            , ("notes", "  <script>alert(1)</script>  ")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "is required by the Surface request contract"
                leaveExists <- query @LeaveRequest |> filterWhere (#venueId, unpackId venue.id) |> fetchExists
                leaveExists `shouldBe` False

        it "renders manager accordion headings with counts inline after the title" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-manager-headings@example.com" "staff" True
                workerUser <- createUserRecord "leave-worker-headings@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Hana" "Headings"
                _ <- createLeaveRequestRecord venue staff (addDays 10 today) (addDays 12 today) "pending"
                _ <- createLeaveRequestRecord venue staff (addDays 13 today) (addDays 14 today) "pending"
                _ <- createLeaveRequestRecord venue staff (addDays 15 today) (addDays 16 today) "approved"
                _ <- createLeaveRequestRecord venue staff (addDays 17 today) (addDays 18 today) "denied"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending (2)"
                response `responseBodyShouldContain` "Approved (1)"
                response `responseBodyShouldContain` "Denied (1)"
                response `responseBodyShouldContain` "Archive (0)"
                response `responseBodyShouldNotContain` "Needs a decision"
                response `responseBodyShouldNotContain` "Already confirmed"
                response `responseBodyShouldNotContain` "Rejected requests"

        it "archives manager leave requests whose date window is fully in the past" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-manager-archive@example.com" "staff" True
                workerUser <- createUserRecord "leave-worker-archive@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Ari" "Archive"
                _ <- createLeaveRequestRecord venue staff (addDays (-20) today) (addDays (-18) today) "pending"
                _ <- createLeaveRequestRecord venue staff (addDays (-17) today) (addDays (-16) today) "approved"
                _ <- createLeaveRequestRecord venue staff (addDays (-15) today) (addDays (-14) today) "denied"
                _ <- createLeaveRequestRecord venue staff (addDays (-1) today) today "approved"
                _ <- createLeaveRequestRecord venue staff (addDays 1 today) (addDays 2 today) "pending"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending (1)"
                response `responseBodyShouldContain` "Approved (1)"
                response `responseBodyShouldContain` "Denied (0)"
                response `responseBodyShouldContain` "Archive (3)"
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                    pendingSection = fst (Text.breakOn "id=\"leave-approved\"" (snd (Text.breakOn "id=\"leave-pending\"" bodyText)))
                    archiveSection = snd (Text.breakOn "id=\"leave-archive\"" bodyText)
                Text.isInfixOf "aria-expanded=\"true\"" pendingSection `shouldBe` True
                Text.isInfixOf "accordion-collapse collapse show" pendingSection `shouldBe` True
                Text.isInfixOf ">Actions<" archiveSection `shouldBe` False
                Text.isInfixOf ">Approve<" archiveSection `shouldBe` False
                Text.isInfixOf ">Deny<" archiveSection `shouldBe` False

        it "paginates archived manager leave requests without changing active sections" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Leave Archive Pagination Venue"
                manager <- createUserRecord "leave-manager-archive-pagination@example.com" "staff" True
                workerUser <- createUserRecord "leave-worker-archive-pagination@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Page" "Archive"
                _ <- createLeaveRequestRecord venue staff (addDays 2 today) (addDays 3 today) "pending"
                forM_ [1 .. 12 :: Int] \index -> do
                    let endDate = addDays (negate (toInteger index)) today
                    leaveRequest <- createLeaveRequestRecord venue staff (addDays (-1) endDate) endDate "approved"
                    leaveRequest
                        |> set #notes (Just ("archive-page-note-" <> tshow index))
                        |> updateRecord

                firstPageResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction
                olderPageResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams LeaveRequestsAction [("archivePage", "2")]
                fragmentResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowleaveRequestsContentLiveFragmentAction [("archivePage", "2")]

                firstPageResponse `responseStatusShouldBe` status200
                firstPageResponse `responseBodyShouldContain` "Pending (1)"
                firstPageResponse `responseBodyShouldContain` "Archive (12)"
                firstPageResponse `responseBodyShouldContain` "archive-page-note-1"
                firstPageResponse `responseBodyShouldContain` "archive-page-note-10"
                firstPageResponse `responseBodyShouldNotContain` "archive-page-note-11"
                firstPageResponse `responseBodyShouldContain` "Older"
                firstPageResponse `responseBodyShouldContain` "archivePage=2"
                firstPageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"archive-leave-requests-page\""

                olderPageResponse `responseStatusShouldBe` status200
                olderPageResponse `responseBodyShouldContain` "Pending (1)"
                olderPageResponse `responseBodyShouldContain` "Archive (12)"
                olderPageResponse `responseBodyShouldContain` "archive-page-note-11"
                olderPageResponse `responseBodyShouldContain` "archive-page-note-12"
                olderPageResponse `responseBodyShouldNotContain` "archive-page-note-10"

                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "id=\"leave-requests-content\""
                fragmentResponse `responseBodyShouldContain` "archive-page-note-11"
                fragmentResponse `responseBodyShouldNotContain` "id=\"app\""

        it "returns only the archive page content for archive pagination OOB swaps" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Leave Archive OOB Pagination Venue"
                manager <- createUserRecord "leave-manager-archive-oob@example.com" "staff" True
                workerUser <- createUserRecord "leave-worker-archive-oob@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Oob" "Archive"
                forM_ [1 .. 12 :: Int] \index -> do
                    let endDate = addDays (negate (toInteger index)) today
                    leaveRequest <- createLeaveRequestRecord venue staff (addDays (-1) endDate) endDate "approved"
                    leaveRequest
                        |> set #notes (Just ("archive-oob-note-" <> tshow index))
                        |> updateRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowleaveRequestsContentLiveFragmentAction
                        [ ("archivePage", "2")
                        , ("openSection", "archive")
                        , ("swapOob", "true")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"leave-archive-page-content\""
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""
                response `responseBodyShouldContain` "archive-oob-note-11"
                response `responseBodyShouldContain` "archive-oob-note-12"
                response `responseBodyShouldNotContain` "id=\"leave-requests-content\""
                response `responseBodyShouldNotContain` "id=\"leave-pending\""
                response `responseBodyShouldNotContain` "id=\"leave-archive-collapse\""

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
                response `responseBodyShouldContain` "Archive (0)"
                response `responseBodyShouldNotContain` "No unavailable periods yet."
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
                    callAction ShowleaveRequestsContentLiveFragmentAction
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowleaveRequestsContentLiveFragmentAction

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Ava Viewer"
                managerResponse `responseBodyShouldContain` "Bea Viewer"
                workerResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders workerResponse) `shouldBe` Just "http://localhost/RosterWeeks"

        it "does not bump cold roster week scopes when denying previously approved leave" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                rosterGroup <- ensureVenueDefaultRosterGroup venue
                manager <- createUserRecord "leave-deny-live-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                _ <- createRosterWeekRecord venue 0 False
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) "approved"

                versionBefore <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venue.id) (unpackId rosterGroup.id) 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction DenyLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status302

                versionAfter <- currentLiveUpdateVersion (RosterLive.rosterWeekLiveScope (unpackId venue.id) (unpackId rosterGroup.id) 0)
                versionAfter `shouldBe` versionBefore

        it "plans manager leave-page actor keys from the same rendered-section resource as passive viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Manager Actor Venue"
                manager <- createUserRecord "leave-manager-actor@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createStaffRecord venue (Just manager) "Mara" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", "2025-01-13")
                            , ("endDate", "2025-01-14")
                            , ("notes", "Manager actor dependency")
                            ]

                response `responseStatusShouldBe` status200
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "leave-section-count")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "leave-section-list")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"leaveSection\":\"archive\"")
                triggerHeader `shouldSatisfy` maybe True (not . Text.isInfixOf "\"leaveSection\":\"pending\"")

        it "creating leave via HTMX updates the actor fragment and bumps the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Liv" "Create"

                versionBefore <- currentLiveUpdateVersion (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldNotContain` "id=\"profile-leave\""
                bodyText `shouldNotContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldNotContain` "id=\"profile-leave-requests-list-fragment\""
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldNotContain` "Unavailable periods"
                bodyText `shouldNotContain` "id=\"profile-content-fragment\""
                let profileLeaveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                profileLeaveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                profileLeaveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "profile-leave-section")
                profileLeaveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "profile-leave")

                versionAfter <- currentLiveUpdateVersion (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "resets the roster self-service form OOB without inventing a roster dependency target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Leave Venue"
                rosterGroup <- ensureVenueDefaultRosterGroup venue
                user <- createUserRecord "leave-roster-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Rae" "Roster"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", "2025-01-13")
                            , ("endDate", "2025-01-14")
                            , ("notes", "Roster quick tool")
                            , ("responseContext", "roster")
                            , ("rosterGroupId", cs (tshow rosterGroup.id))
                            , ("weekOffset", "2")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldContain` "id=\"roster-staff-self-service-leave-form-fragment\" hx-swap-oob=\"outerHTML\""
                bodyText `shouldNotContain` "id=\"roster-content\""
                bodyText `shouldNotContain` "id=\"profile-leave\""
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                lookup "HX-Trigger" (responseHeaders response) `shouldBe` Nothing

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
                bodyText `shouldNotContain` "id=\"profile-leave\""

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldNotContain` "id=\"profile-leave\""
                bodyText `shouldNotContain` "id=\"profile-leave-request-form-fragment\""
                bodyText `shouldNotContain` "id=\"profile-leave-requests-list-fragment\""
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                bodyText `shouldNotContain` "Pending ("
                let inferredProfileLeaveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                inferredProfileLeaveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "profile-leave-section")

        it "manager review actions bump the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                today <- utctDay <$> getCurrentTime
                leaveRequest <- createLeaveRequestRecord venue staff (addDays 7 today) (addDays 9 today) "pending"

                versionBefore <- currentLiveUpdateVersion (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "leave-approve-client")] do
                        callAction ApproveLeaveRequestAction { leaveRequestId = leaveRequest.id }

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                bodyText `shouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                let leaveReviewTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"leave-section-count\"")
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"leave-section-list\"")
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"leaveSection\":\"pending\"")
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"leaveSection\":\"approved\"")
                leaveReviewTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "leave-requests-content")
                versionAfter <- currentLiveUpdateVersion (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

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

