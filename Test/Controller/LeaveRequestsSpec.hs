module Test.Controller.LeaveRequestsSpec where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Live as LeaveLive
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffLeaveRequestsResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (affectedVenueWeekOffsetsForDateRange)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception.Safe (SomeException, try)
import Control.Monad (zipWithM)
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
import Web.LeaveRequests.Blackouts (currentVenueCalendarDay)
import Web.LeaveRequests.Mutations (LeaveReviewDecision (..),
                                    leaveReviewTouchedResources)
import Web.LeaveRequests.ReadModel (affectedRosterWeekInvalidationTargetsForScopes)
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "LeaveRequestsController" do
        it "redirects unauthenticated users through shared controller middleware" $ withContext do
            let requestId = "00000000-0000-0000-0000-000000000000" :: Id LeaveRequest
            actionResponsesShouldHaveStatus status302
                [ ("index", callAction LeaveRequestsAction)
                , ("content fragment", callAction ShowleaveRequestsContentLiveFragmentAction)
                , ("new request", callAction NewLeaveRequestAction)
                , ("create request", callAction CreateLeaveRequestAction)
                , ("approve", callAction ApproveLeaveRequestAction { leaveRequestId = requestId })
                , ("deny", callAction DenyLeaveRequestAction { leaveRequestId = requestId })
                ]

        it "provides venue-scoped inclusive unavailability blackout persistence" $ withContext do
            relations <- sqlQuery
                "SELECT to_regclass('unavailability_blackouts')::text"
                ()
            relations `shouldBe` [Only (Just ("unavailability_blackouts" :: Text))]

        it "lets venue admins create inclusive blackout periods" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Create Venue"
                admin <- createUserRecord "blackout-create-admin@example.com" "admin" True
                owner <- createUserRecord "blackout-create-owner@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue owner VenueOwner
                today <- utctDay <$> getCurrentTime
                let firstBlockedDate = addDays 2 today
                let lastBlockedDate = addDays 4 today

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateUnavailabilityBlackoutAction
                        [ ("startDate", cs (tshow firstBlockedDate))
                        , ("endDate", cs (tshow lastBlockedDate))
                        , ("reason", "Annual stocktake")
                        ]

                response `responseStatusShouldBe` status302
                blackout <- query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                blackout.startDate `shouldBe` firstBlockedDate
                blackout.endDate `shouldBe` lastBlockedDate
                blackout.reason `shouldBe` "Annual stocktake"

                ownerResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams CreateUnavailabilityBlackoutAction
                        [ ("startDate", cs (tshow (addDays 1 lastBlockedDate)))
                        , ("endDate", cs (tshow (addDays 1 lastBlockedDate)))
                        , ("reason", "Owner closure")
                        ]
                ownerResponse `responseStatusShouldBe` status302
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 2)

        it "accepts a start on venue-local today" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Venue Local Today"
                config <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- config |> set #timezone "Etc/GMT+12" |> updateRecord
                admin <- createUserRecord "blackout-local-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                now <- getCurrentTime
                venueToday :: Day <- sqlQueryScalar "SELECT (?::timestamptz AT TIME ZONE 'Etc/GMT+12')::date" (Only now)

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateUnavailabilityBlackoutAction
                        [ ("startDate", cs (tshow venueToday))
                        , ("endDate", cs (tshow venueToday))
                        , ("reason", "Local calendar date")
                        ]

                response `responseStatusShouldBe` status302
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 1)

        it "enforces staff-visible reason and 366-day inclusive limits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Validation Venue"
                admin <- createUserRecord "blackout-validation-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                today <- currentVenueCalendarDay venueConfig
                let submit endDate reason = withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callActionWithParams CreateUnavailabilityBlackoutAction
                            [ ("startDate", cs (tshow today))
                            , ("endDate", cs (tshow endDate))
                            , ("reason", reason)
                            ]

                _ <- submit today " x "
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 0)
                _ <- submit (addDays 366 today) "Too long"
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 0)
                whitespaceResult <- (try $
                    newRecord @UnavailabilityBlackout
                        |> set #venueId (unpackId venue.id)
                        |> set #startDate today
                        |> set #endDate today
                        |> set #reason "   "
                        |> createRecord) :: IO (Either SomeException UnavailabilityBlackout)
                whitespaceResult `shouldSatisfy` either (const True) (const False)
                let maximumReason = cs (Text.replicate 160 "r")
                validResponse <- submit (addDays 365 today) maximumReason
                validResponse `responseStatusShouldBe` status302
                saved <- query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                Text.length saved.reason `shouldBe` 160
                saved.endDate `shouldBe` addDays 365 today

        it "rejects inclusive blackout overlaps while allowing the next date" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Overlap Venue"
                admin <- createUserRecord "blackout-overlap-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                today <- utctDay <$> getCurrentTime
                let firstBlockedDate = addDays 2 today
                let lastBlockedDate = addDays 4 today
                _ <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate firstBlockedDate
                    |> set #endDate lastBlockedDate
                    |> set #reason "Existing closure"
                    |> createRecord

                overlapResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateUnavailabilityBlackoutAction
                            [ ("startDate", cs (tshow lastBlockedDate))
                            , ("endDate", cs (tshow (addDays 1 lastBlockedDate)))
                            , ("reason", "Overlapping closure")
                            ]
                overlapResponse `responseStatusShouldBe` status200
                overlapResponse `responseBodyShouldContain` "Blackout periods cannot overlap"
                overlapResponse `responseBodyShouldContain` "Overlapping closure"
                overlapResponse `responseBodyShouldContain` "invalid-feedback"
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 1)

                adjacentResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateUnavailabilityBlackoutAction
                        [ ("startDate", cs (tshow (addDays 1 lastBlockedDate)))
                        , ("endDate", cs (tshow (addDays 1 lastBlockedDate)))
                        , ("reason", "Adjacent closure")
                        ]
                adjacentResponse `responseStatusShouldBe` status302
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 2)

        it "serializes concurrent overlapping blackout creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent Blackout Venue"
                admin <- createUserRecord "concurrent-blackout-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                today <- utctDay <$> getCurrentTime
                let createAction reason = withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callActionWithParams CreateUnavailabilityBlackoutAction
                            [ ("startDate", cs (tshow (addDays 2 today)))
                            , ("endDate", cs (tshow (addDays 4 today)))
                            , ("reason", reason)
                            ]

                results <- runConcurrentLeaveActionList
                    [createAction "Concurrent closure one", createAction "Concurrent closure two"]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 1)

        it "rejects a self-service unavailable range at inclusive blackout boundaries with the visible reason" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Submission Venue"
                worker <- createUserRecord "blackout-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Blocked" "Worker"
                today <- utctDay <$> getCurrentTime
                let blockedDate = addDays 3 today
                _ <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate blockedDate
                    |> set #endDate blockedDate
                    |> set #reason "Annual fire inspection"
                    |> createRecord

                blockedResponse <- withUserAndCurrentVenue worker venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("responseContext", "self-service")
                            , ("startDate", cs (tshow blockedDate))
                            , ("endDate", cs (tshow (addDays 1 blockedDate)))
                            , ("notes", "Need this date")
                            ]
                blockedResponse `responseStatusShouldBe` status200
                blockedResponse `responseBodyShouldContain` "Annual fire inspection"
                query @LeaveRequest |> filterWhere (#staffId, unpackId staff.id) |> fetchCount >>= (`shouldBe` 0)

                beforeResponse <- withUserAndCurrentVenue worker venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("responseContext", "self-service")
                            , ("startDate", cs (tshow (addDays (-1) blockedDate)))
                            , ("endDate", cs (tshow blockedDate))
                            , ("notes", "Boundary before")
                            ]
                beforeResponse `responseStatusShouldBe` status200
                query @LeaveRequest |> filterWhere (#staffId, unpackId staff.id) |> fetchCount >>= (`shouldBe` 1)

        it "lets managers and support enter staff requests without overriding blackouts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout No Override Venue"
                manager <- createUserRecord "blackout-manager@example.com" "manager" True
                superAdmin <- createUserRecordWithPlatformRole "blackout-support@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Target" "Staff"
                today <- utctDay <$> getCurrentTime
                let blockedDate = addDays 5 today
                _ <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate blockedDate
                    |> set #endDate blockedDate
                    |> set #reason "Mandatory training day"
                    |> createRecord
                let requestParams =
                        [ ("responseContext", "staff")
                        , ("staffId", cs (tshow staff.id))
                        , ("startDate", cs (tshow blockedDate))
                        , ("endDate", cs (tshow (addDays 1 blockedDate)))
                        , ("notes", "Manager entry")
                        ]

                managerResponse <- withPasskeyVerifiedUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction requestParams
                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Mandatory training day"

                supportResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction requestParams
                supportResponse `responseStatusShouldBe` status200
                supportResponse `responseBodyShouldContain` "Mandatory training day"
                supportManagementResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams CreateUnavailabilityBlackoutAction
                        [ ("startDate", cs (tshow (addDays 1 blockedDate)))
                        , ("endDate", cs (tshow (addDays 1 blockedDate)))
                        , ("reason", "Support override period")
                        ]
                supportManagementResponse `responseStatusShouldBe` status302
                query @UnavailabilityBlackout |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 2)
                query @LeaveRequest |> filterWhere (#staffId, unpackId staff.id) |> fetchCount >>= (`shouldBe` 0)

        it "lets admins edit and remove blackouts while managers cannot manage them" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Manage Venue"
                foreignVenue <- createVenueWithConfig "Foreign Blackout Manage Venue"
                admin <- createUserRecord "blackout-manage-admin@example.com" "admin" True
                manager <- createUserRecord "blackout-manage-manager@example.com" "manager" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord foreignVenue admin VenueAdmin
                _ <- createVenueMembershipRecord venue manager Manager
                today <- utctDay <$> getCurrentTime
                blackout <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate (addDays 2 today)
                    |> set #endDate (addDays 3 today)
                    |> set #reason "Original reason"
                    |> createRecord

                managerResponse <- withPasskeyVerifiedUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateUnavailabilityBlackoutAction blackout.id)
                        [ ("startDate", cs (tshow (addDays 3 today)))
                        , ("endDate", cs (tshow (addDays 4 today)))
                        , ("reason", "Manager changed")
                        ]
                managerResponse `responseStatusShouldBe` status302
                managerRejected <- fetch blackout.id
                managerRejected.reason `shouldBe` "Original reason"

                crossVenueResponse <- withPasskeyVerifiedUserAndCurrentVenue admin foreignVenue.id do
                    callActionWithParams (UpdateUnavailabilityBlackoutAction blackout.id)
                        [ ("startDate", cs (tshow (addDays 3 today)))
                        , ("endDate", cs (tshow (addDays 4 today)))
                        , ("reason", "Cross venue change")
                        ]
                crossVenueResponse `responseStatusShouldBe` status403
                crossVenueRejected <- fetch blackout.id
                crossVenueRejected.reason `shouldBe` "Original reason"

                updateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateUnavailabilityBlackoutAction blackout.id)
                        [ ("startDate", cs (tshow (addDays 3 today)))
                        , ("endDate", cs (tshow (addDays 4 today)))
                        , ("reason", "Updated closure")
                        ]
                updateResponse `responseStatusShouldBe` status302
                updated <- fetch blackout.id
                updated.startDate `shouldBe` addDays 3 today
                updated.endDate `shouldBe` addDays 4 today
                updated.reason `shouldBe` "Updated closure"

                deleteResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (DeleteUnavailabilityBlackoutAction blackout.id)
                deleteResponse `responseStatusShouldBe` status302
                query @UnavailabilityBlackout |> filterWhere (#id, blackout.id) |> fetchCount >>= (`shouldBe` 0)

        it "renders active blackout visibility by role and pre-existing exceptions for admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blackout Visibility Venue"
                admin <- createUserRecord "blackout-visibility-admin@example.com" "admin" True
                manager <- createUserRecord "blackout-visibility-manager@example.com" "manager" True
                worker <- createUserRecord "blackout-visibility-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Visible" "Worker"
                today <- utctDay <$> getCurrentTime
                existingRequest <- createLeaveRequestRecord venue staff today (addDays 1 today) LeaveRequestStatusEnumApproved
                activeBlackout <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate today
                    |> set #endDate (addDays 1 today)
                    |> set #reason "Kitchen renovation"
                    |> createRecord
                _ <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate (addDays (-3) today)
                    |> set #endDate (addDays (-1) today)
                    |> set #reason "Ended closure"
                    |> createRecord

                retainedRequest <- fetch existingRequest.id
                inputValue retainedRequest.status `shouldBe` "approved"
                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction LeaveRequestsAction
                adminResponse `responseBodyShouldContain` "Kitchen renovation"
                adminResponse `responseBodyShouldContain` "Add blackout"
                adminResponse `responseBodyShouldContain` "Pre-existing exceptions"
                adminResponse `responseBodyShouldContain` "Visible Worker"
                adminResponse `responseBodyShouldNotContain` "Ended closure"

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction
                managerResponse `responseBodyShouldContain` "Kitchen renovation"
                managerResponse `responseBodyShouldNotContain` "Add blackout"
                managerResponse `responseBodyShouldNotContain` "Pre-existing exceptions"

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction ShowVisibleUnavailabilityBlackoutsFragmentAction
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldContain` activeBlackout.reason
                workerResponse `responseBodyShouldNotContain` "Ended closure"


        it "renders staff blackout fragments for support-mode super-admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Staff Blackout Fragment Venue"
                superAdmin <- createUserRecordWithPlatformRole "support-staff-blackout-fragment@example.com" "staff" (Just SuperAdmin) True
                today <- utctDay <$> getCurrentTime
                _ <- newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId venue.id)
                    |> set #startDate (addDays (-1) today)
                    |> set #endDate (addDays 1 today)
                    |> set #reason "Support-visible closure"
                    |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ShowVisibleUnavailabilityBlackoutsFragmentAction [("surface", "staff")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"staff-visible-unavailability-blackouts\""
                response `responseBodyShouldContain` "Support-visible closure"
                response `responseBodyShouldNotContain` "Founder support"

        it "redirects venue-less super-admins from leave to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "leave-bootstrap-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- withUser user do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "renders grouped threshold warnings for distinct active linked and trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Threshold Venue"
                foreignVenue <- createVenueWithConfig "Foreign Leave Threshold Venue"
                manager <- createUserRecord "leave-threshold-manager@example.com" "staff" True
                linkedUser <- createUserRecord "leave-threshold-linked@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue linkedUser Worker
                linkedStaff <- createStaffRecord venue (Just linkedUser) "Linked" "Worker"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                inactiveStaff <- createStaffRecord venue Nothing "Inactive" "Worker" >>= updateRecord . set #isActive False
                now <- getCurrentTime
                archivedStaff <- createStaffRecord venue Nothing "Archived" "Worker"
                    >>= updateRecord
                        . set #archivedAt (Just now)
                        . set #archivedByUserId (Just (unpackId manager.id))
                        . set #archiveReason (Just "threshold_test")
                deletedStaff <- createStaffRecord venue Nothing "Deleted" "Worker"
                foreignStaff <- createStaffRecord foreignVenue Nothing "Foreign" "Worker"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig |> set #unavailableStaffWarningThreshold (Just 2) |> updateRecord
                today <- utctDay <$> getCurrentTime
                let firstWarningDay = addDays 1 today
                let availableAgain = addDays 4 today
                _ <- createLeaveRequestRecord venue linkedStaff firstWarningDay availableAgain LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue trialStaff firstWarningDay (addDays 3 today) LeaveRequestStatusEnumApproved
                _ <- createLeaveRequestRecord venue trialStaff (addDays 3 today) availableAgain LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue inactiveStaff firstWarningDay availableAgain LeaveRequestStatusEnumApproved
                _ <- createLeaveRequestRecord venue archivedStaff firstWarningDay availableAgain LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue deletedStaff firstWarningDay availableAgain LeaveRequestStatusEnumApproved
                    >>= updateRecord
                        . set #deletedAt (Just now)
                        . set #deletedByUserId (Just (unpackId manager.id))
                        . set #deleteReason (Just "threshold_test")
                _ <- createLeaveRequestRecord venue linkedStaff firstWarningDay availableAgain LeaveRequestStatusEnumDenied
                _ <- createLeaveRequestRecord foreignVenue foreignStaff firstWarningDay availableAgain LeaveRequestStatusEnumApproved

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Unavailable-staff threshold reached"
                response `responseBodyShouldContain` "Warning threshold: 2 active staff"
                response `responseBodyShouldContain` "2 staff unavailable"
                response `responseBodyShouldContain` "Linked Worker"
                response `responseBodyShouldContain` "Trial Worker"
                response `responseBodyShouldContain` "Pending and approved"
                response `responseBodyShouldContain` (cs (formatTime defaultTimeLocale "%d/%m/%Y" firstWarningDay))
                response `responseBodyShouldContain` (cs (formatTime defaultTimeLocale "%d/%m/%Y" (addDays 3 today)))
                response `responseBodyShouldNotContain` "3 staff unavailable"
                response `responseBodyShouldNotContain` "Foreign Worker"

        it "shows managers the disabled threshold state and withholds warnings from workers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Disabled Threshold Venue"
                manager <- createUserRecord "leave-disabled-threshold-manager@example.com" "staff" True
                worker <- createUserRecord "leave-disabled-threshold-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue (Just worker) "Threshold" "Worker"

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction LeaveRequestsAction
                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction LeaveRequestsAction

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "id=\"leave-availability-warnings\""
                managerResponse `responseBodyShouldNotContain` "Unavailable-staff warnings are disabled for this venue."
                workerResponse `responseStatusShouldBe` status302
                workerResponse `responseBodyShouldNotContain` "Unavailable-staff warnings"

        it "selects leave roster invalidation targets from active roster week scopes in the current venue" $ withContext do
            withCleanDb do
                let staleTimestamp = UTCTime (fromGregorian 2024 12 1) (secondsToDiffTime 0)
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                rosterGroupA <- ensureVenueDefaultRosterGroup venueA
                rosterGroupB <- ensureVenueDefaultRosterGroup venueB
                manager <- createUserRecord "leave-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager Manager
                staffA <- createStaffRecord venueA Nothing "Ava" "Leave"
                rosterWeekA <- createRosterWeekRecord venueA 0 False >>= updateRecord . set #updatedAt staleTimestamp
                rosterWeekA1 <- createRosterWeekRecord venueA 1 False >>= updateRecord . set #updatedAt staleTimestamp
                rosterWeekB <- createRosterWeekRecord venueB 0 False >>= updateRecord . set #updatedAt staleTimestamp
                leaveRequest <- createLeaveRequestRecord venueA staffA (fromGregorian 2025 1 8) (fromGregorian 2025 1 15) LeaveRequestStatusEnumPending
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
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Touched" "Staff"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 15) LeaveRequestStatusEnumPending
                Set.fromList (leaveReviewTouchedResources (fromGregorian 2025 1 10) ApproveLeave LeaveRequestStatusEnumPending leaveRequest)
                    `shouldBe` Set.fromList
                        [ leaveAvailabilityWarningsResource (unpackId venue.id)
                        , pendingLeaveRequestsResource (unpackId venue.id)
                        , approvedLeaveRequestsResource (unpackId venue.id)
                        , staffLeaveRequestsResource leaveRequest.staffId
                        ]
                Set.fromList (leaveReviewTouchedResources (fromGregorian 2025 1 16) ApproveLeave LeaveRequestStatusEnumPending leaveRequest)
                    `shouldBe` Set.fromList
                        [ leaveAvailabilityWarningsResource (unpackId venue.id)
                        , archivedLeaveRequestsResource (unpackId venue.id)
                        , staffLeaveRequestsResource leaveRequest.staffId
                        ]

        it "renders a subscribed leave shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Manager
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
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Blocked" "Worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "lets super-admin review leave without self-service leave creation" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "Support Leave Venue"
                superAdmin <- createUserRecordWithPlatformRole "leave-super-admin@example.com" "staff" (Just SuperAdmin) True
                worker <- createStaffRecord venue Nothing "Liv" "Worker"
                _ <- createLeaveRequestRecord venue worker (addDays 10 today) (addDays 12 today) LeaveRequestStatusEnumPending

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
                superAdmin <- createUserRecordWithPlatformRole "leave-create-super-admin@example.com" "staff" (Just SuperAdmin) True

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
                _ <- createVenueMembershipRecord venue user Worker
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
                _ <- createVenueMembershipRecord venue user Worker
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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                staff <- createStaffRecord venue (Just workerUser) "Hana" "Headings"
                _ <- createLeaveRequestRecord venue staff (addDays 10 today) (addDays 12 today) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue staff (addDays 13 today) (addDays 14 today) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue staff (addDays 15 today) (addDays 16 today) LeaveRequestStatusEnumApproved
                _ <- createLeaveRequestRecord venue staff (addDays 17 today) (addDays 18 today) LeaveRequestStatusEnumDenied

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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                staff <- createStaffRecord venue (Just workerUser) "Ari" "Archive"
                _ <- createLeaveRequestRecord venue staff (addDays (-20) today) (addDays (-18) today) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue staff (addDays (-17) today) (addDays (-16) today) LeaveRequestStatusEnumApproved
                _ <- createLeaveRequestRecord venue staff (addDays (-15) today) (addDays (-14) today) LeaveRequestStatusEnumDenied
                _ <- createLeaveRequestRecord venue staff (addDays (-1) today) today LeaveRequestStatusEnumApproved
                _ <- createLeaveRequestRecord venue staff (addDays 1 today) (addDays 2 today) LeaveRequestStatusEnumPending

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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                staff <- createStaffRecord venue (Just workerUser) "Page" "Archive"
                _ <- createLeaveRequestRecord venue staff (addDays 2 today) (addDays 3 today) LeaveRequestStatusEnumPending
                forM_ [1 .. 12 :: Int] \index -> do
                    let endDate = addDays (negate (toInteger index)) today
                    leaveRequest <- createLeaveRequestRecord venue staff (addDays (-1) endDate) endDate LeaveRequestStatusEnumApproved
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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                staff <- createStaffRecord venue (Just workerUser) "Oob" "Archive"
                forM_ [1 .. 12 :: Int] \index -> do
                    let endDate = addDays (negate (toInteger index)) today
                    leaveRequest <- createLeaveRequestRecord venue staff (addDays (-1) endDate) endDate LeaveRequestStatusEnumApproved
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
                _ <- createVenueMembershipRecord venue manager Manager

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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerAUser Worker
                _ <- createVenueMembershipRecord venue workerBUser Worker
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Viewer"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Viewer"
                _ <- createLeaveRequestRecord venue workerA (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) LeaveRequestStatusEnumPending
                _ <- createLeaveRequestRecord venue workerB (fromGregorian 2025 1 11) (fromGregorian 2025 1 12) LeaveRequestStatusEnumPending

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
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                _ <- createRosterWeekRecord venue 0 False
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) LeaveRequestStatusEnumApproved

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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mara" "Manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig |> set #unavailableStaffWarningThreshold (Just 1) |> updateRecord

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
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "leave-availability-warnings")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"leaveSection\":\"archive\"")
                triggerHeader `shouldSatisfy` maybe True (not . Text.isInfixOf "\"leaveSection\":\"pending\"")

        it "creating self-service leave updates actor fragments without manager-scope fanout" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Liv" "Create"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig |> set #unavailableStaffWarningThreshold (Just 1) |> updateRecord

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
                                , ("responseContext", "self-service")
                                ]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldNotContain` "id=\"profile-leave\""
                bodyText `shouldNotContain` "id=\"self-service-leave-form-fragment\""
                bodyText `shouldNotContain` "id=\"self-service-leave-history-fragment\""
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldNotContain` "id=\"profile-content-fragment\""
                let actorRefreshHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-form")
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-history")

                versionAfter <- currentLiveUpdateVersion (LeaveLive.leaveRequestsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "resets the shared self-service form and refreshes profile history when mounted" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Shared Leave Venue"
                user <- createUserRecord "leave-shared-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Rae" "Roster"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", "2025-01-13")
                            , ("endDate", "2025-01-14")
                            , ("notes", "Shared quick tool")
                            , ("responseContext", "self-service")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldNotContain` "id=\"self-service-leave-form-fragment\""
                bodyText `shouldNotContain` "id=\"self-service-leave-history-fragment\""
                bodyText `shouldNotContain` "id=\"roster-content\""
                bodyText `shouldNotContain` "id=\"profile-leave\""
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                let actorRefreshHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-form")
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-history")

        it "redirects self-service submission when no operational staff record exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                incompleteUser <- createUserRecord "leave-profile-no-staff@example.com" "staff" False
                _ <- createVenueMembershipRecord venue incompleteUser Worker
                user <- incompleteUser |> set #isProfileCompleted True |> updateRecord

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", "2025-01-13")
                            , ("endDate", "2025-01-14")
                            , ("notes", "Family event")
                            , ("responseContext", "profile")
                            , ("section", "leave")
                            ]

                response `responseStatusShouldBe` status302

        it "infers shared self-service context from the HTMX target when responseContext is missing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                user <- createUserRecord "leave-profile-target-inference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Manager
                _ <- createStaffRecord venue (Just user) "Admin" "Crew"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("HX-Target", "self-service-leave-form-fragment")
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
                bodyText `shouldNotContain` "id=\"self-service-leave-form-fragment\""
                bodyText `shouldNotContain` "id=\"self-service-leave-history-fragment\""
                bodyText `shouldContain` "Unavailable period submitted"
                bodyText `shouldNotContain` "id=\"leave-requests-content\""
                let actorRefreshHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-form")
                actorRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "self-service-leave-history")

        it "manager review actions bump the leave scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Leave Venue"
                manager <- createUserRecord "leave-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                today <- utctDay <$> getCurrentTime
                leaveRequest <- createLeaveRequestRecord venue staff (addDays 7 today) (addDays 9 today) LeaveRequestStatusEnumPending

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
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Ava" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 8) (fromGregorian 2025 1 10) LeaveRequestStatusEnumPending

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
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Dina" "Leave"
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2025 1 11) (fromGregorian 2025 1 12) LeaveRequestStatusEnumPending

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
                _ <- createVenueMembershipRecord venue user Worker
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

runConcurrentLeaveActionList :: [IO result] -> IO [Either SomeException result]
runConcurrentLeaveActionList actions = do
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

