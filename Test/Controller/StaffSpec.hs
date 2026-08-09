module Test.Controller.StaffSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.EmailDelivery
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (leaveAvailabilityWarningsResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import qualified Application.Helper.LiveUpdate as LiveUpdate
import Application.Helper.PasskeySetupTokens (PasskeySetupTokenPurpose (..),
                                              issuePasskeySetupToken)
import Application.Helper.PasswordResetTokens (issuePasswordResetToken)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.StaffShiftPreferences (encodeShiftPreferenceKey,
                                                 shiftPreferenceEndHourParamName,
                                                 shiftPreferenceStartHourParamName)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (operationalDayForUtcTime)
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay,
                                          venueWeekStartDate)
import Application.InvitationDelivery.Enqueue (enqueueVenueInvitationEmail)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception.Safe (SomeException, try)
import Control.Monad (void, zipWithM)
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.Staff ()
import Web.FrontController ()
import Web.Routes
import Web.Staff.Mutations (staffCreateTouchedResources,
                            staffRosterGroupResources, staffTimesheetResources,
                            staffUpdateTouchedResources)
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "StaffController" do
        let sampleStaffId = Id "6f9638dc-f13c-4ed3-b4f1-a2f860532cab"
        it "redirects unauthenticated users through shared controller middleware" $ withContext do
            actionResponsesShouldHaveStatus status302
                [ ("edit", callActionWithParams (EditStaffAction sampleStaffId) [("weekOffset", "7")])
                , ( "update"
                  , callActionWithParams (UpdateStaffAction sampleStaffId)
                        [ ("section", "profile")
                        , ("firstName", "Test")
                        , ("lastName", "User")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Casey User")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "3")
                        , ("weekOffset", "7")
                        ]
                  )
                , ("new trial", callAction NewStaffAction)
                ]

        it "labels the trial staff dialog as add trial" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Dialog Venue"
                manager <- createUserRecord "trial-staff-dialog-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction NewStaffAction

                defaultRosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isDefault, True)
                    |> fetchOne
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Add Trial"
                response `responseBodyShouldNotContain` "Edit Staff Member"
                response `responseBodyShouldNotContain` ">Roster Groups</label>"
                response `responseBodyShouldContain` cs ("name=\"rosterGroupIds\" value=\"" <> tshow (unpackId defaultRosterGroup.id) <> "\"")

        it "assigns the sole active roster group when staff creation omits group fields" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Implicit Trial Staff Group Venue"
                manager <- createUserRecord "implicit-trial-group-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                soleRosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateStaffAction
                        [ ("firstName", "Implicit")
                        , ("lastName", "Group")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        ]

                response `responseStatusShouldBe` status302
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Implicit" :: Text)
                    |> fetchOne
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                map (.rosterGroupId) assignments `shouldBe` [unpackId soleRosterGroup.id]

        it "rejects new assignments to inactive roster groups" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Inactive Trial Staff Group Venue"
                manager <- createUserRecord "inactive-trial-group-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                activeGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetchOne
                inactiveGroup <- createVenueRosterGroupWithDefaults venue "Inactive group" 20 False

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateStaffAction
                        [ ("firstName", "Rejected")
                        , ("lastName", "Inactive")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("rosterGroupIds", cs (tshow activeGroup.id))
                        , ("rosterGroupIds", cs (tshow inactiveGroup.id))
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Inactive roster groups can only be retained"
                query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Rejected" :: Text)
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "shows roster-group choices when multiple active groups exist" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Multiple Trial Staff Groups Venue"
                manager <- createUserRecord "multiple-trial-groups-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                secondGroup <- createVenueRosterGroupWithDefaults venue "Second group" 20 True

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction NewStaffAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Roster Groups</label>"
                response `responseBodyShouldContain` secondGroup.name
                response `responseBodyShouldContain` cs ("id=\"staff-roster-group-" <> tshow secondGroup.id <> "\"")

        it "lets managers create active casual trial staff placeholders with selected roster groups" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Venue"
                manager <- createUserRecord "trial-staff-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Trial")
                        , ("lastName", "Placeholder")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow frontOfHouse.id))
                        , ("rosterGroupIds", cs (tshow backOfHouse.id))
                        ]

                response `responseStatusShouldBe` status302
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Trial" :: Text)
                    |> filterWhere (#lastName, "Placeholder" :: Text)
                    |> fetchOne
                staff.userId `shouldBe` Nothing
                staff.isActive `shouldBe` True
                staff.employmentBasis `shouldBe` Casual
                staff.payAssignmentMode `shouldBe` RosterOnly
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                sort (map (.rosterGroupId) assignments) `shouldBe` sort [unpackId frontOfHouse.id, unpackId backOfHouse.id]

        it "silently applies the venue award default when a manager creates staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Manager Default Award Venue"
                manager <- createUserRecord "manager-default-award@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                awardLevel <- createPayLevelRecordWithRates venue "Default Level" 32.75 3.25 6.50 1 1.25 1.50
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig
                    |> set #defaultStaffPayAssignmentMode AwardRate
                    |> set #defaultStaffAwardLevelId (Just awardLevel.id)
                    |> updateRecord
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Award")
                        , ("lastName", "Default")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Award" :: Text)
                    |> fetchOne
                staff.payAssignmentMode `shouldBe` AwardRate
                staff.defaultAwardLevelId `shouldBe` Just awardLevel.id
                staff.importedXeroPayItemId `shouldBe` Nothing

        it "blocks manager staff creation when the venue award default is unavailable" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Manager Invalid Default Venue"
                manager <- createUserRecord "manager-invalid-default@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                awardLevel <- createPayLevelRecordWithRates venue "Inactive Default" 32.75 3.25 6.50 1 1.25 1.50
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig
                    |> set #defaultStaffPayAssignmentMode AwardRate
                    |> set #defaultStaffAwardLevelId (Just awardLevel.id)
                    |> updateRecord
                casualRates <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                    |> filterWhere (#employmentBasis, Casual)
                    |> fetch
                deleteRecords casualRates
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Blocked")
                        , ("lastName", "Default")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "The venue default staff rate is unavailable"
                query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Blocked" :: Text)
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "lets venue admins override the venue staff-rate default during creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Default Override Venue"
                admin <- createUserRecord "admin-default-override@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                awardLevel <- createPayLevelRecordWithRates venue "Venue Default" 32.75 3.25 6.50 1 1.25 1.50
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig
                    |> set #defaultStaffPayAssignmentMode AwardRate
                    |> set #defaultStaffAwardLevelId (Just awardLevel.id)
                    |> updateRecord
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Roster")
                        , ("lastName", "Only")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("employmentBasis", "casual")
                        , ("payRateSelection", "")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Roster" :: Text)
                    |> fetchOne
                staff.payAssignmentMode `shouldBe` RosterOnly
                staff.defaultAwardLevelId `shouldBe` Nothing

        it "prevents non-managers from creating trial staff placeholders" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Worker Venue"
                worker <- createUserRecord "trial-staff-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue worker venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Blocked")
                        , ("lastName", "Trial")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "1")
                        , ("isActive", "on")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                exists <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#firstName, "Blocked" :: Text) |> fetchExists
                exists `shouldBe` False

        it "rejects cross-venue roster group ids when creating trial staff placeholders" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Current Venue"
                otherVenue <- createVenueWithConfig "Trial Staff Other Venue"
                manager <- createUserRecord "trial-staff-cross-venue-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                otherGroup <- createVenueRosterGroupWithDefaults otherVenue "Other Venue Group" 1 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Cross")
                        , ("lastName", "Venue")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "1")
                        , ("isActive", "on")
                        , ("rosterGroupIds", cs (tshow otherGroup.id))
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Choose roster groups from the current venue."
                exists <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#firstName, "Cross" :: Text) |> fetchExists
                exists `shouldBe` False

        it "records touched resources for trial staff creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Create Touched Venue"
                staff <- createStaffRecord venue Nothing "Trace" "Trial"

                Set.fromList (staffCreateTouchedResources staff)
                    `shouldBe` Set.fromList
                        [ staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)

                        ]

        it "records touched resources for staff updates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Touched Venue"
                staff <- createStaffRecord venue Nothing "Sam" "Touched"

                Set.fromList (staffUpdateTouchedResources staff)
                    `shouldBe` Set.fromList
                        [ leaveAvailabilityWarningsResource (unpackId venue.id)
                        , staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)
                        ]

        it "touches active roster weeks for every previous and newly selected staff group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Group Resource Venue"
                previousGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                selectedGroup <- createVenueRosterGroupWithDefaults venue "Selected Group" 1 False
                otherVenue <- createVenueWithConfig "Other Staff Group Resource Venue"
                otherGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId otherVenue.id) |> filterWhere (#isDefault, True) |> fetchOne
                let activeScopes =
                        [ (unpackId venue.id, unpackId previousGroup.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        , (unpackId venue.id, unpackId selectedGroup.id, testAnchorForOffset 1, addDays 7 (testAnchorForOffset 1), 1)
                        , (unpackId otherVenue.id, unpackId otherGroup.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        ]

                let resources = staffRosterGroupResources (unpackId venue.id) activeScopes [previousGroup.id, selectedGroup.id]

                Set.fromList resources
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId previousGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                        , rosterSlotsContentResource (unpackId previousGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                        , rosterWeekResource (unpackId selectedGroup.id) (testAnchorForOffset 1) (addDays 7 (testAnchorForOffset 1))
                        , rosterSlotsContentResource (unpackId selectedGroup.id) (testAnchorForOffset 1) (addDays 7 (testAnchorForOffset 1))
                        ]

        it "touches every active venue Timesheet week after staff pay changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Timesheet Resource Venue"
                otherVenue <- createVenueWithConfig "Other Staff Timesheet Resource Venue"
                let resources = staffTimesheetResources (unpackId venue.id)
                        [ (unpackId venue.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        , (unpackId venue.id, testAnchorForOffset 2, addDays 7 (testAnchorForOffset 2), 1)
                        , (unpackId otherVenue.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        ]

                Set.fromList resources `shouldBe` Set.fromList
                    [ timesheetWeekResource (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                    , timesheetWeekResource (unpackId venue.id) (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2))
                    ]

        it "invalidates roster child and staff list resources for HTMX roster-launched staff edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-modal-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-modal-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue linkedUser Worker
                _ <- createRosterWeekRecord venue 0 False
                staff <- createStaffRecord venue (Just linkedUser) "Alpha" "Crew"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateStaffAction staff.id)
                            [ ("section", "profile")
                            , ("firstName", "Updated")
                            , ("lastName", "Crew")
                            , ("preferredName", "")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Morgan Crew")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "4")
                            , ("isActive", "on")
                            , ("weekOffset", "0")
                            , ("rosterGroupIds", cs (tshow rosterGroup.id))
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "Staff member updated"
                response `responseBodyShouldContain` "id=\"toast-overlay-mount\""
                response `responseBodyShouldNotContain` "id=\"roster-content\""
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "\"kind\":\"roster-content\"")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-slots-grid\"")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")

        it "hides trial staff invitation email from the staff details form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Field Venue"
                manager <- createUserRecord "staff-trial-invite-field-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Trial" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"invitationEmail\""
                response `responseBodyShouldNotContain` "Send an invite link to claim this trial staff profile."

        it "keeps pending trial invites out of the staff details form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Pending Invite Field Venue"
                manager <- createUserRecord "staff-pending-invite-field-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Pending" "Invite"
                _ <- createVenueInvitationRecord venue (Just manager) "pending-trial-invite@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Pending invite"
                response `responseBodyShouldNotContain` "pending-trial-invite@example.com"
                response `responseBodyShouldNotContain` "name=\"invitationEmail\""

        it "opens the dedicated invitation dialog for adoptable trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Dialog Venue"
                manager <- createUserRecord "staff-trial-invite-dialog-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Trial" "Dialog"
                _ <- createVenueInvitationRecord venue (Just manager) "pending-dialog@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (NewTrialStaffInvitationAction staff.id)
                            [ ("weekOffset", "3")
                            , ("rosterGroupId", cs (tshow rosterGroup.id))
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite trial staff"
                response `responseBodyShouldNotContain` "app-staff-edit-dialog"
                response `responseBodyShouldContain` "id=\"trial-staff-invite-form\""
                response `responseBodyShouldContain` "pending-dialog@example.com"
                response `responseBodyShouldContain` "name=\"weekOffset\" value=\"3\""

        it "shows expired trial invitations with corrected-email renewal controls" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Expired Trial Invite Dialog Venue"
                manager <- createUserRecord "staff-expired-trial-dialog-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Expired" "Trial"
                now <- getCurrentTime
                invitation <- createVenueInvitationRecord venue (Just manager) "expired-trial-dialog@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id) . set #expiresAt (Just (addUTCTime (-60) now))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (NewTrialStaffInvitationAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Expired"
                response `responseBodyShouldContain` cs (pathTo (RenewTrialStaffInvitationAction invitation.id))
                response `responseBodyShouldContain` "name=\"invitationEmail\""
                response `responseBodyShouldContain` "value=\"expired-trial-dialog@example.com\""

        it "rejects opening the invitation dialog for linked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Linked Invite Dialog Venue"
                manager <- createUserRecord "staff-linked-invite-dialog-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-linked-invite-dialog-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just linkedUser) "Linked" "Dialog"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (NewTrialStaffInvitationAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Only active trial staff without a linked login can be invited."
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\""
                response `responseBodyShouldNotContain` "id=\"trial-staff-invite-form\""

        it "keeps invalid invitation emails in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Invalid Trial Invite Venue"
                manager <- createUserRecord "staff-invalid-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Invalid" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", "not-an-email")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite trial staff"
                response `responseBodyShouldContain` "Enter a valid email address."
                response `responseBodyShouldContain` "value=\"not-an-email\""
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "requires an invitation email in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Missing Trial Invite Email Venue"
                manager <- createUserRecord "staff-missing-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Missing" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CreateTrialStaffInvitationAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite email is required."
                response `responseBodyShouldContain` "id=\"trial-staff-invite-form\""
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "rejects oversized invitation emails in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Oversized Trial Invite Email Venue"
                manager <- createUserRecord "staff-oversized-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Oversized" "Invite"
                let oversizedEmail = Text.replicate 250 "a" <> "@example.com"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", cs oversizedEmail)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Email must be 254 characters or fewer."
                response `responseBodyShouldContain` cs oversizedEmail
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "lets managers create worker adoption invitations for current-venue trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Venue"
                manager <- createUserRecord "staff-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Trial" "Invite"
                versionBefore <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", "trial-invite-claim@example.com")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation queued for trial-invite-claim@example.com and should arrive shortly"
                response `responseBodyShouldContain` "id=\"toast-overlay-mount\""
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldNotContain` "Edit Staff Member"
                invitation <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "trial-invite-claim@example.com" :: Text)
                    |> fetchOne
                invitation.staffId `shouldBe` Just staff.id
                inputValue invitation.inviteRole `shouldBe` "worker"
                inputValue invitation.status `shouldBe` "pending"
                now <- getCurrentTime
                diffUTCTime (fromMaybe now invitation.expiresAt) now
                    `shouldSatisfy` (\seconds -> seconds > 1209500 && seconds < 1210100)
                appJob <- query @AppJob
                    |> filterWhere (#relatedTable, Just ("venue_invitations" :: Text))
                    |> filterWhere (#relatedId, Just (unpackId invitation.id))
                    |> fetchOne
                appJob.jobKind `shouldBe` emailDeliveryJobKind
                versionAfter <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "renews a trial staff invitation with a fresh link and the same staff identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Renew Trial Invite Venue"
                manager <- createUserRecord "staff-renew-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Renew" "Invite"
                original <- createVenueInvitationRecord venue (Just manager) "renew-trial-invite@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                EnqueuedEmailDelivery originalJob <- enqueueVenueInvitationEmail (Just manager.id) original

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (RenewTrialStaffInvitationAction original.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Renewed invitation queued for renew-trial-invite@example.com and should arrive shortly"
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldNotContain` "Invite trial staff"
                revokedOriginal <- fetch original.id
                inputValue revokedOriginal.status `shouldBe` "revoked"
                replacement <- query @VenueInvitation
                    |> filterWhere (#staffId, Just staff.id)
                    |> filterWhere (#status, original.status)
                    |> fetchOne
                replacement.id `shouldNotBe` original.id
                replacement.email `shouldBe` original.email
                replacement.staffId `shouldBe` Just staff.id
                inputValue replacement.deliveryStatus `shouldBe` "queued"
                replacementJob <- query @AppJob
                    |> filterWhere (#relatedId, Just (unpackId replacement.id))
                    |> fetchOne
                replacementJob.id `shouldNotBe` originalJob.id
                replacementJob.dedupeKey `shouldNotBe` originalJob.dedupeKey
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith testEmailRuntime originalJob
                    performEmailDeliveryJobWith testEmailRuntime replacementJob
                staleOriginal <- fetch original.id
                deliveredReplacement <- fetch replacement.id
                staleOriginal.deliveredAt `shouldBe` Nothing
                deliveredReplacement.deliveredAt `shouldSatisfy` isJust

        it "rejects blank, malformed, and oversized corrected renewal emails without revoking the link" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Invalid Trial Renewal Venue"
                manager <- createUserRecord "staff-invalid-trial-renewal-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Invalid" "Renewal"
                original <- createVenueInvitationRecord venue (Just manager) "valid-trial-renewal@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                let invalidEmails = ["   ", "not-an-email", Text.replicate 250 "a" <> "@example.com", "<script>alert(1)</script>@example.com"]

                forM_ invalidEmails \invalidEmail -> do
                    response <- withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams (RenewTrialStaffInvitationAction original.id)
                                [("invitationEmail", cs invalidEmail)]
                    response `responseStatusShouldBe` status200

                unchanged <- fetch original.id
                inputValue unchanged.status `shouldBe` "pending"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> fetchCount >>= (`shouldBe` 0)

        it "serializes concurrent renewals to one active link for the trial staff identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Concurrent Trial Invite Venue"
                manager <- createUserRecord "staff-concurrent-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Concurrent" "Invite"
                original <- createVenueInvitationRecord venue (Just manager) "concurrent-trial-invite@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                results <- runConcurrentStaffActionList
                    [ withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction (RenewTrialStaffInvitationAction original.id)
                    , withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction (RenewTrialStaffInvitationAction original.id)
                    ]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status200) (rights results)
                query @VenueInvitation
                    |> filterWhere (#staffId, Just staff.id)
                    |> filterWhere (#status, original.status)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "serializes trial invitation acceptance against renewal so only one link outcome wins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Accept Renew Race Venue"
                manager <- createUserRecord "staff-accept-renew-race-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Accept" "Race"
                original <- createVenueInvitationRecord venue (Just manager) "staff-accept-renew-race@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                results <- runConcurrentStaffActionList
                    [ void $ callActionWithParams CreateUserAction
                        [ ("invitationId", idToParam original.id)
                        , ("passwordHash", "test-password-123")
                        , ("passwordConfirmation", "test-password-123")
                        , ("firstName", "Accept")
                        , ("lastName", "Race")
                        , ("preferredName", "")
                        , ("phone", "0499999999")
                        , ("emergencyContactName", "Casey Race")
                        , ("emergencyContactPhone", "0488888888")
                        , ("idealShiftsPerWeek", "4")
                        ]
                    , void $ withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction (RenewTrialStaffInvitationAction original.id)
                    ]

                lefts results `shouldSatisfy` null
                finalOriginal <- fetch original.id
                inputValue finalOriginal.status `shouldSatisfy` (`elem` ["accepted", "revoked"])
                acceptedUserCount <- query @User
                    |> filterWhere (#email, "staff-accept-renew-race@example.com")
                    |> fetchCount
                pendingReplacementCount <- query @VenueInvitation
                    |> filterWhere (#staffId, Just staff.id)
                    |> filterWhere (#status, original.status)
                    |> fetchCount
                acceptedUserCount + pendingReplacementCount `shouldBe` 1

        it "serializes trial invitation acceptance against staff removal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Accept Removal Race Venue"
                admin <- createUserRecord "staff-accept-removal-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Accept" "Removal"
                invitation <- createVenueInvitationRecord venue (Just admin) "staff-accept-removal@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                results <- runConcurrentStaffActionList
                    [ void $ callActionWithParams CreateUserAction
                        [ ("invitationId", idToParam invitation.id)
                        , ("passwordHash", "test-password-123")
                        , ("passwordConfirmation", "test-password-123")
                        , ("firstName", "Accept")
                        , ("lastName", "Removal")
                        , ("preferredName", "")
                        , ("phone", "0499999999")
                        , ("emergencyContactName", "Casey Removal")
                        , ("emergencyContactPhone", "0488888888")
                        , ("idealShiftsPerWeek", "4")
                        ]
                    , void $ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    ]

                lefts results `shouldSatisfy` null
                removedStaff <- fetch staff.id
                removedStaff.archivedAt `shouldSatisfy` isJust
                finalInvitation <- fetch invitation.id
                acceptedUserCount <- query @User
                    |> filterWhere (#email, "staff-accept-removal@example.com")
                    |> fetchCount
                case acceptedUserCount of
                    0 -> do
                        removedStaff.userId `shouldBe` Nothing
                        inputValue finalInvitation.status `shouldBe` ("revoked" :: Text)
                    1 -> do
                        removedStaff.userId `shouldSatisfy` isJust
                        inputValue finalInvitation.status `shouldBe` ("accepted" :: Text)
                        linkedMembership <- query @VenueMembership
                            |> filterWhere (#venueId, unpackId venue.id)
                            |> filterWhere (#userId, fromMaybe (error "Expected linked user") removedStaff.userId)
                            |> fetchOne
                        linkedMembership.isActive `shouldBe` False
                    _ -> expectationFailure "Acceptance/removal race created multiple users"

        it "serializes queued delivery against trial invitation renewal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Delivery Renew Race Venue"
                manager <- createUserRecord "staff-delivery-renew-race-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Delivery" "Race"
                original <- createVenueInvitationRecord venue (Just manager) "staff-delivery-renew-race@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                EnqueuedEmailDelivery originalJob <- enqueueVenueInvitationEmail (Just manager.id) original

                results <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    runConcurrentStaffActionList
                        [ performEmailDeliveryJobWith testEmailRuntime originalJob
                        , void $ withUserAndCurrentVenue manager venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callAction (RenewTrialStaffInvitationAction original.id)
                        ]

                lefts results `shouldSatisfy` null
                finalOriginal <- fetch original.id
                inputValue finalOriginal.status `shouldBe` "revoked"
                query @VenueInvitation
                    |> filterWhere (#staffId, Just staff.id)
                    |> filterWhere (#status, original.status)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "renews to a corrected email and revokes every prior pending link for the trial staff identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Corrected Trial Invite Venue"
                manager <- createUserRecord "staff-corrected-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Corrected" "Invite"
                firstOriginal <- createVenueInvitationRecord venue (Just manager) "first-trial-invite@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                secondOriginal <- createVenueInvitationRecord venue (Just manager) "second-trial-invite@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (RenewTrialStaffInvitationAction firstOriginal.id)
                            [("invitationEmail", " corrected-trial-invite@example.com ")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Renewed invitation queued for corrected-trial-invite@example.com and should arrive shortly"
                renewedOriginals <- query @VenueInvitation
                    |> filterWhereIn (#id, [firstOriginal.id, secondOriginal.id])
                    |> fetch
                map (inputValue . (.status)) renewedOriginals `shouldMatchList` ["revoked", "revoked"]
                replacements <- query @VenueInvitation
                    |> filterWhere (#staffId, Just staff.id)
                    |> filterWhere (#status, firstOriginal.status)
                    |> fetch
                map (.email) replacements `shouldBe` ["corrected-trial-invite@example.com"]

        it "prevents non-managers from renewing trial staff invitations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Worker Renew Venue"
                worker <- createUserRecord "staff-worker-renew-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue Nothing "Worker" "Renew"
                invitation <- createVenueInvitationRecord venue Nothing "worker-renew-trial@example.com" Worker
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- withUserAndCurrentVenue worker venue.id do
                    callAction (RenewTrialStaffInvitationAction invitation.id)

                response `responseStatusShouldBe` status302
                unchanged <- fetch invitation.id
                inputValue unchanged.status `shouldBe` "pending"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)

        it "rejects cross-venue trial invitation renewal" $ withContext do
            withCleanDb do
                currentVenue <- createVenueWithConfig "Staff Renew Current Venue"
                foreignVenue <- createVenueWithConfig "Staff Renew Foreign Venue"
                manager <- createUserRecord "staff-cross-venue-renew-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord currentVenue manager Manager
                foreignStaff <- createStaffRecord foreignVenue Nothing "Foreign" "Renew"
                invitation <- createVenueInvitationRecord foreignVenue Nothing "foreign-renew-trial@example.com" Worker
                    >>= updateRecord . set #staffId (Just foreignStaff.id)

                response <- withUserAndCurrentVenue manager currentVenue.id do
                    callAction (RenewTrialStaffInvitationAction invitation.id)

                response `responseStatusShouldBe` status403
                unchanged <- fetch invitation.id
                inputValue unchanged.status `shouldBe` "pending"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)

        it "prevents non-managers from creating trial staff adoption invitations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Worker Invite Venue"
                worker <- createUserRecord "staff-worker-invite-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue Nothing "Worker" "Invite"

                response <- withUserAndCurrentVenue worker venue.id do
                    callActionWithParams
                        (CreateTrialStaffInvitationAction staff.id)
                        [("invitationEmail", "worker-invite-claim@example.com")]

                response `responseStatusShouldBe` status302
                exists <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "worker-invite-claim@example.com" :: Text)
                    |> fetchExists
                exists `shouldBe` False

        it "rejects adoption invitations for linked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Linked Invite Venue"
                manager <- createUserRecord "staff-linked-invite-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-linked-invite-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just linkedUser) "Linked" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (CreateTrialStaffInvitationAction staff.id)
                        [("invitationEmail", "linked-invite-claim@example.com")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Only active trial staff without a linked login can be invited."
                exists <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "linked-invite-claim@example.com" :: Text)
                    |> fetchExists
                exists `shouldBe` False

        it "renders shift preferences in a dedicated staff edit accordion section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Preferences Accordion Venue"
                manager <- createUserRecord "staff-preferences-accordion-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"staff\""
                response `responseBodyShouldContain` "data-bepis-surface-config="
                response `responseBodyShouldContain` "data-bepis-surface-action=\"update-staff-profile\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"update-staff-shift-preferences\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-staff-leave-request\""
                response `responseBodyShouldContain` "id=\"staff-profile-details-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"staff-profile-preferences-collapse\" class=\"accordion-collapse collapse\""
                soleRosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetchOne
                response `responseBodyShouldContain` "id=\"staff-shift-preferences-form\""
                response `responseBodyShouldContain` "<span class=\"fw-semibold\">Shift Preferences</span>"
                response `responseBodyShouldNotContain` ">Roster Groups</label>"
                response `responseBodyShouldContain` cs ("name=\"rosterGroupIds\" value=\"" <> tshow (unpackId soleRosterGroup.id) <> "\"")

        it "preserves inactive roster-group history while collapsing the sole active choice" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Inactive Group History Venue"
                manager <- createUserRecord "staff-inactive-group-history-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                activeGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetchOne
                inactiveGroup <- createVenueRosterGroupWithDefaults venue "Inactive history" 20 False
                staff <- createStaffRecord venue Nothing "History" "Keeper"
                _ <- newRecord @StaffRosterGroup
                    |> set #staffId (unpackId staff.id)
                    |> set #rosterGroupId (unpackId inactiveGroup.id)
                    |> createRecord

                editResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]
                editResponse `responseStatusShouldBe` status200
                editResponse `responseBodyShouldNotContain` ">Roster Groups</label>"
                editResponse `responseBodyShouldContain` cs ("name=\"rosterGroupIds\" value=\"" <> tshow (unpackId activeGroup.id) <> "\"")
                editResponse `responseBodyShouldContain` cs ("name=\"rosterGroupIds\" value=\"" <> tshow (unpackId inactiveGroup.id) <> "\"")

                updateResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "History")
                        , ("lastName", "Keeper")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Keeper")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow activeGroup.id))
                        , ("rosterGroupIds", cs (tshow inactiveGroup.id))
                        ]
                updateResponse `responseStatusShouldBe` status302
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                sort (map (.rosterGroupId) assignments) `shouldBe` sort [unpackId activeGroup.id, unpackId inactiveGroup.id]

        it "updates explicit roster-group applicability from the staff edit form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-group-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow frontOfHouse.id))
                        , ("rosterGroupIds", cs (tshow backOfHouse.id))
                        ]

                response `responseStatusShouldBe` status302
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                sort (map (.rosterGroupId) assignments) `shouldBe` sort [unpackId frontOfHouse.id, unpackId backOfHouse.id]

        it "keeps existing shift preferences when saving staff profile details" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Preserve Preferences Venue"
                manager <- createUserRecord "staff-preserve-preferences-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #weekdayIndex 1
                        |> set #preferredStartHour 9
                        |> set #preferredEndHour 17
                        |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> filterWhere (#deletedAt, Nothing) |> fetch
                map (.weekdayIndex) preferences `shouldBe` [1]
                map (.preferredStartHour) preferences `shouldBe` [9]
                map (.preferredEndHour) preferences `shouldBe` [17]

        it "saves staff shift preferences from the dedicated preferences form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Dedicated Preferences Venue"
                manager <- createUserRecord "staff-dedicated-preferences-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                let preferenceKey = encodeShiftPreferenceKey 2

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "preferences")
                        , ("weekOffset", "0")
                        , ("shiftPreferenceKeys", cs preferenceKey)
                        , (cs (shiftPreferenceStartHourParamName preferenceKey), "8")
                        , (cs (shiftPreferenceEndHourParamName preferenceKey), "14")
                        ]

                response `responseStatusShouldBe` status302
                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> filterWhere (#deletedAt, Nothing) |> fetch
                map (.weekdayIndex) preferences `shouldBe` [2]
                map (.preferredStartHour) preferences `shouldBe` [8]
                map (.preferredEndHour) preferences `shouldBe` [14]

        it "rejects malformed roster group ids and shift preference keys without throwing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-malformed-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateStaffAction staff.id)
                            [ ("section", "profile")
                            , ("firstName", "Alpha")
                            , ("lastName", "Crew")
                            , ("preferredName", "")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Jordan Crew")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "4")
                            , ("isActive", "on")
                            , ("weekOffset", "0")
                            , ("rosterGroupIds", "not-a-uuid")
                            , ("shiftPreferenceKeys", "bad|key|not-a-uuid")
                            ]

                response `responseStatusShouldBe` status200
                preferenceExists <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetchExists
                preferenceExists `shouldBe` False

        it "allows venue admins to update staff employment basis and default pay level" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "staff-pay-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                payLevel <- createPayLevelRecord venue "Level 2"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                xeroVersionBefore <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("award:" <> tshow payLevel.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.employmentBasis `shouldBe` Permanent
                updatedStaff.defaultAwardLevelId `shouldBe` Just payLevel.id
                updatedStaff.payAssignmentMode `shouldBe` AwardRate
                xeroVersionAfter <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                xeroVersionAfter `shouldBe` xeroVersionBefore

        it "shows synced award level hourly rates in the staff pay selector" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "staff-pay-options-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createPayLevelRecordWithRates venue "Level 3" 32.75 3.25 6.50 1 1.25 1.50
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin (get #id venue) do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldContain` "Award rates"
                response `responseBodyShouldContain` "Level 3 (Part-time $32.75/hr, casual $40.94/hr)"
                response `responseBodyShouldContain` "No Timesheets (roster only)"

        it "marks Profile Details when staff pay configuration requires remediation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Pay Remediation Header Venue"
                admin <- createUserRecord "staff-pay-remediation-header-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Needs" "Pay Setup"
                _ <- staff
                    |> set #payAssignmentMode LegacyUnresolved
                    |> set #defaultAwardLevelId Nothing
                    |> set #importedXeroPayItemId Nothing
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Profile Details"
                response `responseBodyShouldContain` "Pay configuration required. A venue admin must choose a default pay rate or “No Timesheets (roster only).”"

        it "replaces the ordinary active-status control with an admin destructive removal action" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Removal Workflow Venue"
                admin <- createUserRecord "staff-removal-workflow-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Removal" "Target"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"isActive\""
                response `responseBodyShouldContain` "Remove staff member"
                response `responseBodyShouldNotContain` "data-staff-removal-panel"
                response `responseBodyShouldNotContain` "This keeps historical records"

        it "renders a destructive confirmation dialog before staff removal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Removal Confirmation Venue"
                admin <- createUserRecord "staff-removal-confirmation-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Confirm" "Removal"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (NewRemoveStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Remove staff member"
                response `responseBodyShouldContain` "Are you sure you want to remove this staff member? This cannot be undone."
                response `responseBodyShouldNotContain` "Future roster assignments and pending unavailability will be removed"
                response `responseBodyShouldNotContain` "Existing timesheets, payroll history, and past roster records are kept"
                response `responseBodyShouldContain` (cs ("action=\"" <> pathTo (RemoveStaffAction staff.id) <> "\""))
                response `responseBodyShouldContain` "hx-post"

        it "soft-removes an active trial staff member from the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Removal Venue"
                admin <- createUserRecord "trial-staff-removal-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Trial" "Removal"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                removedStaff <- fetch staff.id
                removedStaff.isActive `shouldBe` False
                removedStaff.archivedAt `shouldSatisfy` isJust
                removedStaff.archivedByUserId `shouldBe` Just (unpackId admin.id)
                removedStaff.archiveReason `shouldBe` Just "Removed from venue staff"

        it "rejects removal by a manager without mutating staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Manager Removal Rejection Venue"
                manager <- createUserRecord "staff-removal-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Protected" "Worker"

                editResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (EditStaffAction staff.id)
                editResponse `responseBodyShouldNotContain` "data-staff-removal-panel"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                unchangedStaff <- fetch staff.id
                unchangedStaff.isActive `shouldBe` True
                unchangedStaff.archivedAt `shouldBe` Nothing

        it "rejects removal of a venue owner even when another owner submits the request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Owner Removal Rejection Venue"
                actor <- createUserRecord "staff-removal-actor-owner@example.com" "staff" True
                targetUser <- createUserRecord "staff-removal-target-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor VenueOwner
                _ <- createVenueMembershipRecord venue targetUser VenueOwner
                staff <- createStaffRecord venue (Just targetUser) "Protected" "Owner"

                editResponse <- withPasskeyVerifiedUserAndCurrentVenue actor venue.id do
                    callAction (EditStaffAction staff.id)
                editResponse `responseBodyShouldNotContain` "data-staff-removal-panel"

                response <- withPasskeyVerifiedUserAndCurrentVenue actor venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                unchangedStaff <- fetch staff.id
                unchangedStaff.isActive `shouldBe` True
                unchangedStaff.archivedAt `shouldBe` Nothing

        it "archives only the linked current-venue membership and preserves the user's other venue access" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Linked Staff Removal Venue"
                otherVenue <- createVenueWithConfig "Preserved Other Venue"
                admin <- createUserRecord "linked-staff-removal-admin@example.com" "staff" True
                worker <- createUserRecord "linked-staff-removal-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                currentMembership <- createVenueMembershipRecord venue worker Worker
                otherMembership <- createVenueMembershipRecord otherVenue worker Manager
                currentStaff <- createStaffRecord venue (Just worker) "Current" "Worker"
                otherStaff <- createStaffRecord otherVenue (Just worker) "Other" "Worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction currentStaff.id)

                response `responseStatusShouldBe` status302
                archivedMembership <- fetch currentMembership.id
                archivedMembership.isActive `shouldBe` False
                archivedMembership.archivedAt `shouldSatisfy` isJust
                archivedMembership.archivedByUserId `shouldBe` Just (unpackId admin.id)
                archivedMembership.archiveReason `shouldBe` Just "Staff removed from venue"
                preservedMembership <- fetch otherMembership.id
                preservedMembership.isActive `shouldBe` True
                preservedMembership.archivedAt `shouldBe` Nothing
                preservedStaff <- fetch otherStaff.id
                preservedStaff.isActive `shouldBe` True
                preservedStaff.archivedAt `shouldBe` Nothing

        it "revokes current-venue staff credential links for the removed target and issuer" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Credential Cleanup Venue"
                otherVenue <- createVenueWithConfig "Preserved Credential Venue"
                admin <- createUserRecord "staff-credential-cleanup-admin@example.com" "staff" True
                worker <- createUserRecord "staff-credential-cleanup-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createVenueMembershipRecord otherVenue worker Worker
                otherTarget <- createUserRecord "staff-credential-cleanup-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue otherTarget Worker
                staff <- createStaffRecord venue (Just worker) "Credential" "Worker"
                passkey <- createTestPasskeyRecord worker "Preserved global passkey"
                invitation <- createVenueInvitationRecord venue (Just admin) worker.email Worker
                    >>= updateRecord . set #staffId (Just staff.id)
                (currentVenueRecoveryToken, _) <- issuePasskeySetupToken StaffPasskeyRecovery worker (Just admin.id) (Just venue.id)
                (currentVenueSetupToken, _) <- issuePasskeySetupToken StaffNewDevicePasskeySetup worker (Just admin.id) (Just venue.id)
                (unattributedToken, _) <- issuePasskeySetupToken StaffPasskeyRecovery worker Nothing (Just venue.id)
                (selfIssuedToken, _) <- issuePasskeySetupToken SelfNewDevicePasskeySetup worker (Just worker.id) (Just venue.id)
                (issuedSetupToken, _) <- issuePasskeySetupToken StaffPasskeyRecovery otherTarget (Just worker.id) (Just venue.id)
                (otherVenueToken, _) <- issuePasskeySetupToken StaffNewDevicePasskeySetup worker (Just admin.id) (Just otherVenue.id)
                (targetResetToken, _) <- issuePasswordResetToken worker admin.id venue.id
                (issuedResetToken, _) <- issuePasswordResetToken otherTarget worker.id venue.id

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                revokedInvitation <- fetch invitation.id
                inputValue revokedInvitation.status `shouldBe` ("revoked" :: Text)
                invalidatedRecoveryToken <- fetch currentVenueRecoveryToken.id
                invalidatedRecoveryToken.consumedAt `shouldSatisfy` isJust
                invalidatedSetupToken <- fetch currentVenueSetupToken.id
                invalidatedSetupToken.consumedAt `shouldSatisfy` isJust
                invalidatedUnattributedToken <- fetch unattributedToken.id
                invalidatedUnattributedToken.consumedAt `shouldSatisfy` isJust
                invalidatedIssuedSetupToken <- fetch issuedSetupToken.id
                invalidatedIssuedSetupToken.consumedAt `shouldSatisfy` isJust
                invalidatedTargetResetToken <- fetch targetResetToken.id
                invalidatedTargetResetToken.consumedAt `shouldSatisfy` isJust
                invalidatedTargetResetToken.deliveryTokenCiphertext `shouldBe` Nothing
                invalidatedIssuedResetToken <- fetch issuedResetToken.id
                invalidatedIssuedResetToken.consumedAt `shouldSatisfy` isJust
                invalidatedIssuedResetToken.deliveryTokenCiphertext `shouldBe` Nothing
                preservedSelfToken <- fetch selfIssuedToken.id
                preservedSelfToken.consumedAt `shouldBe` Nothing
                preservedOtherVenueToken <- fetch otherVenueToken.id
                preservedOtherVenueToken.consumedAt `shouldBe` Nothing
                preservedPasskey <- fetch passkey.id
                preservedPasskey.userId `shouldBe` unpackId worker.id

        it "deletes current and future roster assignments across groups while retaining past history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Roster Cleanup Venue"
                admin <- createUserRecord "staff-roster-cleanup-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Roster" "Removal"
                defaultGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                secondGroup <- createVenueRosterGroupWithDefaults venue "Second" 1 True
                defaultSlotName <- createSlotNameRecordForRosterGroup venue defaultGroup "Default lane"
                secondSlotName <- createSlotNameRecordForRosterGroup venue secondGroup "Second lane"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                pastWeek <- createRosterWeekRecordForRosterGroup venue defaultGroup (currentWeekOffset - 1) True
                currentWeek <- createRosterWeekRecordForRosterGroup venue defaultGroup currentWeekOffset True
                futureWeek <- createRosterWeekRecordForRosterGroup venue secondGroup (currentWeekOffset + 1) True
                pastDay <- createRosterDayRecord pastWeek 0
                currentDay <- createRosterDayRecord currentWeek (fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset)))
                futureDay <- createRosterDayRecord futureWeek 0
                pastSlot <- createRosterSlotRecord pastDay defaultSlotName (Just staff) 0
                currentSlot <- createRosterSlotRecord currentDay defaultSlotName (Just staff) 0
                futureSlot <- createRosterSlotRecord futureDay secondSlotName (Just staff) 0

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                retainedPastSlot <- fetch pastSlot.id
                retainedPastSlot.deletedAt `shouldBe` Nothing
                removedCurrentSlot <- fetch currentSlot.id
                removedCurrentSlot.deletedAt `shouldSatisfy` isJust
                removedCurrentSlot.deletedByUserId `shouldBe` Just (unpackId admin.id)
                removedCurrentSlot.deleteReason `shouldBe` Just "Staff removed from venue"
                removedFutureSlot <- fetch futureSlot.id
                removedFutureSlot.deletedAt `shouldSatisfy` isJust

        it "serializes removal against current roster assignment creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Roster Creation Race Venue"
                admin <- createUserRecord "staff-roster-creation-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Roster" "Race"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- createSlotNameRecordForRosterGroup venue rosterGroup "Race lane"
                payLevel <- createPayLevelRecord venue "Race level"
                shiftType <- createShiftTypeRecord venue payLevel "Race shift"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup currentWeekOffset True
                rosterDay <- createRosterDayRecord rosterWeek (fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset)))
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams
                                (CreateRosterSlotAction rosterDay.id (coerce slotDefinition.id) 0)
                                [ ("staffId", cs (tshow staff.id))
                                , ("startTime", "09:00")
                                , ("endTime", "17:00")
                                , ("shiftTypeId", cs (tshow shiftType.id))
                                ]
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right createResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        createResponse `responseStatusShouldBe` status200
                    _ -> expectationFailure "Expected removal and roster creation responses"
                removedStaff <- fetch staff.id
                removedStaff.archivedAt `shouldSatisfy` isJust
                query @RosterSlot
                    |> filterWhere (#staffId, Just (unpackId staff.id))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "serializes removal against an in-flight staff profile update" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Profile Removal Race Venue"
                admin <- createUserRecord "staff-profile-removal-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Profile" "Race"
                let preferenceKey = encodeShiftPreferenceKey 1
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams
                                (UpdateStaffAction staff.id)
                                [ ("section", "preferences")
                                , ("weekOffset", "0")
                                , ("shiftPreferenceKeys", cs preferenceKey)
                                , (cs (shiftPreferenceStartHourParamName preferenceKey), "9")
                                , (cs (shiftPreferenceEndHourParamName preferenceKey), "17")
                                ]
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right profileResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        Network.Wai.responseStatus profileResponse `shouldSatisfy` (`elem` [status200, status403])
                        when (Network.Wai.responseStatus profileResponse == status200) do
                            profileResponseBody :: Text <- cs <$> IHP.Test.Mocking.responseBody profileResponse
                            profileResponseBody `shouldSatisfy` \body ->
                                "Shift preferences updated" `Text.isInfixOf` body
                                    || "staff-profile-preferences" `Text.isInfixOf` body
                    _ -> expectationFailure "Expected removal and profile update responses"
                archivedStaff <- fetch staff.id
                archivedStaff.archivedAt `shouldSatisfy` isJust
                let archivedAt = fromMaybe (error "Expected removed staff archival") archivedStaff.archivedAt
                archivedStaff.updatedAt `shouldSatisfy` (<= archivedAt)
                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetch
                map (.createdAt) preferences `shouldSatisfy` all (<= archivedAt)

        it "serializes removal against reassignment without resurrecting a deleted slot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Roster Reassignment Race Venue"
                admin <- createUserRecord "staff-roster-reassignment-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                removedStaff <- createStaffRecord venue Nothing "Removed" "Race"
                replacementStaff <- createStaffRecord venue Nothing "Replacement" "Race"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- createSlotNameRecordForRosterGroup venue rosterGroup "Reassignment lane"
                payLevel <- createPayLevelRecord venue "Reassignment level"
                shiftType <- createShiftTypeRecord venue payLevel "Reassignment shift"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup currentWeekOffset True
                rosterDay <- createRosterDayRecord rosterWeek (fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset)))
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just removedStaff) 0
                    >>= updateRecord
                        . setTestStartTime (Just (TimeOfDay 9 0 0))
                        . setTestEndTime (Just (TimeOfDay 17 0 0))
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction removedStaff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams
                                (UpdateRosterSlotAction rosterSlot.id)
                                [ ("staffId", cs (tshow replacementStaff.id))
                                , ("startTime", "09:00")
                                , ("endTime", "17:00")
                                , ("shiftTypeId", cs (tshow shiftType.id))
                                ]
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right reassignmentResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        Network.Wai.responseStatus reassignmentResponse `shouldSatisfy` (`elem` [status200, status403])
                    _ -> expectationFailure "Expected removal and roster reassignment responses"
                archivedStaff <- fetch removedStaff.id
                archivedStaff.archivedAt `shouldSatisfy` isJust
                let archivedAt = fromMaybe (error "Expected removed staff archival") archivedStaff.archivedAt
                finalSlot <- fetch rosterSlot.id
                when (isNothing finalSlot.deletedAt) do
                    finalSlot.staffId `shouldBe` Just (unpackId replacementStaff.id)
                    finalSlot.updatedAt `shouldSatisfy` (<= archivedAt)

        it "serializes removal against moving a current assignment" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Roster Move Race Venue"
                admin <- createUserRecord "staff-roster-move-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Move" "Race"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- createSlotNameRecordForRosterGroup venue rosterGroup "Move race lane"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup currentWeekOffset True
                rosterDay <- createRosterDayRecord rosterWeek (fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset)))
                rosterSlot <- createCompleteRosterSlotRecord rosterDay slotName staff 0
                let sourceToken = "existing:" <> tshow rosterSlot.id
                let targetToken = "new:" <> tshow rosterDay.id <> ":" <> tshow rosterSlot.rosterWeekSlotDefinitionId <> ":1"
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams MoveRosterShiftToSlotAction
                                ( [ ("rosterGroupId", cs (tshow rosterGroup.id))
                                  , ("sourceItemKey", cs sourceToken)
                                  , ("targetDropzoneKey", cs targetToken)
                                  ]
                                    <> rosterMutationParams currentWeekOffset
                                )
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right moveResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        moveResponse `responseStatusShouldBe` status200
                    _ -> expectationFailure "Expected removal and roster move responses"
                finalSlot <- fetch rosterSlot.id
                finalSlot.deletedAt `shouldSatisfy` isJust

        it "serializes roster slot updates against deletion without resurrection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Slot Delete Update Race Venue"
                manager <- createUserRecord "roster-slot-delete-update-race-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Delete Update" "Race"
                slotName <- createSlotNameRecord venue "Delete update race lane"
                payLevel <- createPayLevelRecord venue "Delete update race level"
                shiftType <- createShiftTypeRecord venue payLevel "Delete update race shift"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just staff) 0
                    >>= updateRecord
                        . setTestStartTime (Just (TimeOfDay 9 0 0))
                        . setTestEndTime (Just (TimeOfDay 17 0 0))
                        . set #shiftTypeId (Just (unpackId shiftType.id))

                results <- runConcurrentStaffActionList
                    [ withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams
                                (UpdateRosterSlotAction rosterSlot.id)
                                [ ("staffId", cs (tshow staff.id))
                                , ("startTime", "10:00")
                                , ("endTime", "18:00")
                                , ("shiftTypeId", cs (tshow shiftType.id))
                                ]
                    , withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams (DeleteRosterSlotAction rosterSlot.id) (rosterMutationParams 0)
                    ]

                lefts results `shouldSatisfy` null
                finalSlot <- fetch rosterSlot.id
                finalSlot.deletedAt `shouldSatisfy` isJust

        it "serializes removal against roster week replacement without recreating current or future assignments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Roster Copy Race Venue"
                admin <- createUserRecord "staff-roster-copy-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Copy" "Race"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- createSlotNameRecordForRosterGroup venue rosterGroup "Copy race lane"
                payLevel <- createPayLevelRecord venue "Copy race level"
                staff <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Copy race shift"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup currentWeekOffset True
                let operationalDayOffset = fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset))
                sourceDay <- createRosterDayRecord sourceWeek operationalDayOffset
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup (currentWeekOffset + 1) False
                _ <- createRosterDayRecord targetWeek operationalDayOffset
                _ <- createRosterSlotRecord sourceDay slotName (Just staff) 0
                    >>= updateRecord
                        . setTestStartTime (Just (TimeOfDay 9 0 0))
                        . setTestEndTime (Just (TimeOfDay 17 0 0))
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams CopyRosterWeekAction (rosterCopyParams currentWeekOffset (currentWeekOffset + 1))
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right copyResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        copyResponse `responseStatusShouldBe` status200
                        copyResponseBody :: Text <- cs <$> IHP.Test.Mocking.responseBody copyResponse
                        copyResponseBody `shouldSatisfy` \body ->
                            "Roster week copied from the previous week." `Text.isInfixOf` body
                                || "no longer available for rostering" `Text.isInfixOf` body
                                || "Resolve pay configuration" `Text.isInfixOf` body
                    _ -> expectationFailure "Expected removal and roster copy responses"
                removedStaff <- fetch staff.id
                removedStaff.archivedAt `shouldSatisfy` isJust
                activeRosterSlots <- query @RosterSlot
                    |> filterWhere (#staffId, Just (unpackId staff.id))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                activeRosterSlots `shouldBe` []

        it "serializes removal against new roster week copy without recreating current or future assignments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff New Roster Copy Race Venue"
                admin <- createUserRecord "staff-new-roster-copy-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "New Copy" "Race"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- createSlotNameRecordForRosterGroup venue rosterGroup "New copy race lane"
                payLevel <- createPayLevelRecord venue "New copy race level"
                staff <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "New copy race shift"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                now <- getCurrentTime
                operationalToday <- operationalDayForUtcTime venueConfig now
                let currentWeekOffset = venueWeekOffsetForDay venueConfig operationalToday
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup currentWeekOffset True
                sourceDay <- createRosterDayRecord sourceWeek (fromInteger (diffDays operationalToday (venueWeekStartDate venueConfig currentWeekOffset)))
                _ <- createRosterSlotRecord sourceDay slotName (Just staff) 0
                    >>= updateRecord
                        . setTestStartTime (Just (TimeOfDay 9 0 0))
                        . setTestEndTime (Just (TimeOfDay 17 0 0))
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams CopyRosterWeekAction (rosterCopyParams currentWeekOffset (currentWeekOffset + 1))
                    ]

                lefts results `shouldSatisfy` null
                case results of
                    [Right removalResponse, Right copyResponse] -> do
                        removalResponse `responseStatusShouldBe` status302
                        copyResponse `responseStatusShouldBe` status200
                        copyResponseBody :: Text <- cs <$> IHP.Test.Mocking.responseBody copyResponse
                        copyResponseBody `shouldSatisfy` \body ->
                            "Roster week copied from the previous week." `Text.isInfixOf` body
                                || "no longer available for rostering" `Text.isInfixOf` body
                                || "Resolve pay configuration" `Text.isInfixOf` body
                    _ -> expectationFailure "Expected removal and new roster copy responses"
                removedStaff <- fetch staff.id
                removedStaff.archivedAt `shouldSatisfy` isJust
                activeRosterSlots <- query @RosterSlot
                    |> filterWhere (#staffId, Just (unpackId staff.id))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                activeRosterSlots `shouldBe` []

        it "denies pending unavailability through retained lifecycle events and preserves reviewed history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Leave Cleanup Venue"
                admin <- createUserRecord "staff-leave-cleanup-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Leave" "Removal"
                today <- utctDay <$> getCurrentTime
                pendingRequest <- createLeaveRequestRecord venue staff today (addDays 1 today) LeaveRequestStatusEnumPending
                approvedRequest <- createLeaveRequestRecord venue staff (addDays 2 today) (addDays 3 today) LeaveRequestStatusEnumApproved
                deniedRequest <- createLeaveRequestRecord venue staff (addDays 4 today) (addDays 5 today) LeaveRequestStatusEnumDenied

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                deniedPendingRequest <- fetch pendingRequest.id
                inputValue deniedPendingRequest.status `shouldBe` ("denied" :: Text)
                retainedApprovedRequest <- fetch approvedRequest.id
                inputValue retainedApprovedRequest.status `shouldBe` ("approved" :: Text)
                retainedDeniedRequest <- fetch deniedRequest.id
                inputValue retainedDeniedRequest.status `shouldBe` ("denied" :: Text)
                leaveEvent <- query @LeaveRequestEvent |> filterWhere (#leaveRequestId, unpackId pendingRequest.id) |> fetchOne
                inputValue leaveEvent.eventType `shouldBe` ("denied" :: Text)
                fmap inputValue leaveEvent.previousStatus `shouldBe` Just "pending"
                fmap inputValue leaveEvent.newStatus `shouldBe` Just "denied"
                leaveEvent.actorUserId `shouldBe` unpackId admin.id

        it "serializes removal against pending unavailability submission" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Leave Submission Race Venue"
                admin <- createUserRecord "staff-leave-submission-race-admin@example.com" "staff" True
                worker <- createUserRecord "staff-leave-submission-race-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Leave Submit" "Race"
                today <- utctDay <$> getCurrentTime
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withUserAndCurrentVenue worker venue.id do
                        callActionWithParams CreateLeaveRequestAction
                            [ ("startDate", cs (tshow (addDays 1 today)))
                            , ("endDate", cs (tshow (addDays 2 today)))
                            , ("notes", "Removal race")
                            ]
                    ]

                lefts results `shouldSatisfy` null
                leaveRequests <- query @LeaveRequest
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                map (inputValue . (.status)) leaveRequests `shouldNotContain` (["pending"] :: [Text])

        it "serializes removal against pending unavailability approval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Leave Review Race Venue"
                admin <- createUserRecord "staff-leave-review-race-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Leave Review" "Race"
                today <- utctDay <$> getCurrentTime
                leaveRequest <- createLeaveRequestRecord venue staff (addDays 1 today) (addDays 2 today) LeaveRequestStatusEnumPending
                ensureTestUserHasPasskey admin

                results <- runConcurrentStaffActionList
                    [ withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (RemoveStaffAction staff.id)
                    , withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callAction (ApproveLeaveRequestAction leaveRequest.id)
                    ]

                lefts results `shouldSatisfy` null
                archivedStaff <- fetch staff.id
                archivedStaff.archivedAt `shouldSatisfy` isJust
                let archivedAt = fromMaybe (error "Expected removed staff archival") archivedStaff.archivedAt
                finalLeaveRequest <- fetch leaveRequest.id
                inputValue finalLeaveRequest.status `shouldSatisfy` (`elem` (["approved", "denied"] :: [Text]))
                when (inputValue finalLeaveRequest.status == ("approved" :: Text)) do
                    finalLeaveRequest.updatedAt `shouldSatisfy` (<= archivedAt)

        it "rejects self-removal by a venue admin" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Self Removal Rejection Venue"
                admin <- createUserRecord "staff-self-removal-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue (Just admin) "Self" "Admin"

                editResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (EditStaffAction staff.id)
                editResponse `responseBodyShouldNotContain` "data-staff-removal-panel"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                unchangedStaff <- fetch staff.id
                unchangedStaff.isActive `shouldBe` True
                unchangedStaff.archivedAt `shouldBe` Nothing

        it "preserves materialized timesheets and sealed payroll history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Payroll Preservation Venue"
                admin <- createUserRecord "staff-payroll-preservation-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Payroll" "History"
                today <- utctDay <$> getCurrentTime
                approvedEntry <- createApprovedTimesheetEntryRecord venue staff admin today
                let calculationId = fromMaybe (error "Expected sealed pay calculation") approvedEntry.activePayCalculationId

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction staff.id)

                response `responseStatusShouldBe` status302
                retainedEntry <- fetch approvedEntry.id
                retainedEntry.isApproved `shouldBe` True
                retainedEntry.deletedAt `shouldBe` Nothing
                retainedEntry.activePayCalculationId `shouldBe` Just calculationId
                retainedCalculation <- fetch calculationId
                retainedCalculation.sealedAt `shouldSatisfy` isJust

        it "removes pay-invalid staff but rejects cross-venue staff ids" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Pay Invalid Removal Venue"
                otherVenue <- createVenueWithConfig "Cross Venue Removal Target"
                admin <- createUserRecord "pay-invalid-removal-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                payInvalidStaff <- createStaffRecord venue Nothing "Pay" "Invalid"
                    >>= updateRecord
                        . set #payAssignmentMode LegacyUnresolved
                        . set #defaultAwardLevelId Nothing
                        . set #importedXeroPayItemId Nothing
                otherStaff <- createStaffRecord otherVenue Nothing "Other" "Venue"

                removalResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction payInvalidStaff.id)
                removalResponse `responseStatusShouldBe` status302
                removedPayInvalidStaff <- fetch payInvalidStaff.id
                removedPayInvalidStaff.archivedAt `shouldSatisfy` isJust

                tamperedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (RemoveStaffAction otherStaff.id)
                tamperedResponse `responseStatusShouldBe` status403
                preservedOtherStaff <- fetch otherStaff.id
                preservedOtherStaff.isActive `shouldBe` True
                preservedOtherStaff.archivedAt `shouldBe` Nothing

        it "explains why venue roles are unavailable for unlinked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Unlinked Staff Role Venue"
                admin <- createUserRecord "unlinked-staff-role-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Trial" "Role"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff Role"
                response `responseBodyShouldContain` "can be assigned after this staff profile is linked to a user account"
                response `responseBodyShouldNotContain` "<select name=\"venueRole\""

        it "lets venue admins view and update a linked staff member venue role" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Role Venue"
                admin <- createUserRecord "staff-role-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                workerUser <- createUserRecord "staff-role-worker@example.com" "staff" True
                membership <- createVenueMembershipRecord venue workerUser Worker
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                staff <- createStaffRecord venue (Just workerUser) "Role" "Target"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff Role"
                response `responseBodyShouldContain` "<select name=\"venueRole\""
                response `responseBodyShouldContain` "<option value=\"worker\" selected"
                response `responseBodyShouldContain` "<option value=\"supervisor\""

                updateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Role")
                        , ("lastName", "Target")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "casual")
                        , ("payRateSelection", "")
                        , ("venueRole", "manager")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                updateResponse `responseStatusShouldBe` status302
                updatedMembership <- fetch membership.id
                inputValue updatedMembership.venueRole `shouldBe` ("manager" :: Text)
                auditEvent <- query @AuditEvent |> filterWhere (#targetId, unpackId membership.id) |> fetchOne
                auditEvent.eventType `shouldBe` "venue_role_changed"

        it "uses effective admin limits and hides credential controls while impersonating" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonated Staff Governance Venue"
                founder <- createUserRecordWithPlatformRole "staff-governance-founder@example.com" "staff" (Just SuperAdmin) True
                effectiveAdmin <- createUserRecord "staff-governance-admin@example.com" "staff" True
                targetUser <- createUserRecord "staff-governance-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue effectiveAdmin VenueAdmin
                targetMembership <- createVenueMembershipRecord venue targetUser Worker
                _ <- createStaffRecord venue (Just effectiveAdmin) "Effective" "Admin"
                targetStaff <- createStaffRecord venue (Just targetUser) "Role" "Target"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                (editResponse, updateResponse) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue effectiveAdmin.id))]
                    editResponse <- callActionWithParams (EditStaffAction targetStaff.id) [("weekOffset", "0")]
                    updateResponse <- callActionWithParams (UpdateStaffAction targetStaff.id)
                        [ ("section", "profile")
                        , ("firstName", "Role")
                        , ("lastName", "Target")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "casual")
                        , ("payRateSelection", "")
                        , ("venueRole", "venue_owner")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]
                    pure (editResponse, updateResponse)

                editResponse `responseStatusShouldBe` status200
                editResponse `responseBodyShouldNotContain` "<option value=\"venue_owner\""
                editResponse `responseBodyShouldNotContain` "Email passkey setup"
                editResponse `responseBodyShouldNotContain` "Email recovery link"
                editResponse `responseBodyShouldNotContain` "Email password reset"
                updateResponse `responseStatusShouldBe` status200
                preservedMembership <- fetch targetMembership.id
                preservedMembership.venueRole `shouldBe` Worker

        it "shows active imported Xero pay items in the staff pay override dropdown" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Imported Pay Item Venue"
                admin <- createUserRecord "staff-imported-pay-items-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <- createPayLevelRecordWithRates venue "Level Staff" 45.00 4.50 9.00 1 1.25 1.50
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Imported Staff Rate" "imported-staff-rate" 55.25

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldContain` (cs ("<option value=\"xero:" <> inputValue importedPayItem.id <> "\""))
                response `responseBodyShouldContain` "Xero imported rates"
                response `responseBodyShouldContain` "Imported Staff Rate"
                response `responseBodyShouldContain` "55.25/hr"
                responseBodyText <- responseBody response
                (cs responseBodyText :: String) `shouldContainInOrder` ["Award rates", "Level Staff", "Xero imported rates", "Imported Staff Rate"]

                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                updateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("xero:" <> tshow importedPayItem.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]
                updateResponse `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.defaultAwardLevelId `shouldBe` Nothing
                updatedStaff.importedXeroPayItemId `shouldBe` Just importedPayItem.id
                updatedStaff.payAssignmentMode `shouldBe` XeroRate

        it "hides archived imported Xero pay items from the staff pay override dropdown" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Archived Imported Pay Item Venue"
                admin <- createUserRecord "staff-archived-imported-pay-items-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Archived Staff Rate" "archived-staff-rate" 55.25
                now <- getCurrentTime
                _ <- importedPayItem
                    |> set #archivedAt (Just now)
                    |> set #archivedByUserId (Just (unpackId admin.id))
                    |> set #archiveReason (Just ("Test archive" :: Text))
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldNotContain` "Archived Staff Rate"

        it "renders staff login access and temporarily hides RSA upload in the staff edit modal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Access Modal Venue"
                admin <- createUserRecord "staff-access-admin@example.com" "admin" True
                worker <- createUserRecord "staff-access-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Access" "Worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-in access"
                response `responseBodyShouldContain` "staff-access-worker@example.com"
                response `responseBodyShouldContain` "Email passkey setup"
                response `responseBodyShouldContain` "Email recovery link"
                response `responseBodyShouldContain` "Email password reset"
                response `responseBodyShouldNotContain` "id=\"staff-profile-rsa\""
                response `responseBodyShouldNotContain` "Upload a Responsible Service of Alcohol statement of attainment."
                response `responseBodyShouldNotContain` "Upload and scan PDF"
                response `responseBodyShouldNotContain` "action=\"/ScanStaffDocument\""

        it "ignores staff pay fields submitted by non-admin managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-pay-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                payLevel <- createPayLevelRecord venue "Level 2"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("award:" <> tshow payLevel.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.employmentBasis `shouldBe` Casual
                updatedStaff.defaultAwardLevelId `shouldBe` Nothing

testEmailRuntime :: EmailDeliveryRuntime
testEmailRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail = \_ -> pure ()
        }

runConcurrentStaffActionList :: [IO result] -> IO [Either SomeException result]
runConcurrentStaffActionList actions = do
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

shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    go haystack needles
    where
        go _ [] = pure ()
        go remaining (needle : rest) =
            case findNeedle needle remaining of
                Nothing -> expectationFailure "Expected to find text in order"
                Just afterNeedle -> go afterNeedle rest

        findNeedle needle value =
            case List.dropWhile (not . List.isPrefixOf needle) (List.tails value) of
                []        -> Nothing
                match : _ -> Just (drop (length needle) match)
