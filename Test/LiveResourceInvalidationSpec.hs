module Test.LiveResourceInvalidationSpec where

import Application.Helper.LiveResource
import IHP.Prelude
import qualified Data.Set as Set
import Data.UUID (fromWords)
import Test.Hspec
import Web.LiveResourceInvalidation

tests :: Spec
tests = do
    describe "Live resource invalidation planning" do
        it "plans leave, profile leave, and active roster invalidations from touched resources" do
            let venueId = fromWords 1 0 0 0
            let otherVenueId = fromWords 2 0 0 0
            let staffId = fromWords 3 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let otherRosterGroupId = fromWords 5 0 0 0
            let activeScopes = [(venueId, rosterGroupId, 0), (otherVenueId, otherRosterGroupId, 0)]
            let resources = Set.fromList [LeaveRequestsResource venueId, StaffLeaveRequestsResource staffId, LeaveCalendarResource venueId 0]

            planLiveInvalidationsForResources activeScopes resources
                `shouldBe` Set.fromList
                    [ InvalidateLeaveRequests
                    , InvalidateProfileLeaveRequests staffId
                    , InvalidateRosterWeek rosterGroupId 0
                    ]

        it "does not invalidate cold roster weeks for leave-calendar resources" do
            let venueId = fromWords 1 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let activeScopes = [(venueId, rosterGroupId, 1)]

            planLiveInvalidationsForResources activeScopes (Set.singleton (LeaveCalendarResource venueId 0))
                `shouldBe` Set.empty

        it "plans direct roster week invalidations from roster week resources" do
            let rosterGroupId = fromWords 4 0 0 0

            planLiveInvalidationsForResources [] (Set.singleton (RosterWeekResource rosterGroupId 0))
                `shouldBe` Set.singleton (InvalidateRosterWeek rosterGroupId 0)

        it "plans admin and Xero invalidations from admin resources" do
            let venueId = fromWords 1 0 0 0
            let resources = Set.fromList [AdminInvitesResource venueId, AdminRosterGroupsResource venueId, AdminShiftTypesResource venueId, XeroPayItemsResource venueId]

            planLiveInvalidationsForResources [] resources
                `shouldBe` Set.fromList
                    [ InvalidateAdminInvites venueId
                    , InvalidateAdminRosterGroups venueId
                    , InvalidateAdminShiftTypes venueId
                    , InvalidateXeroPayItems venueId
                    ]

        it "plans timesheet invalidations from timesheet resources" do
            let venueId = fromWords 1 0 0 0

            planLiveInvalidationsForResources [] (Set.singleton (TimesheetWeekResource venueId 0))
                `shouldBe` Set.singleton (InvalidateTimesheetWeek venueId 0)
            planLiveInvalidationsForResources [] (Set.fromList [TimesheetWeekResource venueId 0, TimesheetDayResource venueId 0 2])
                `shouldBe` Set.singleton (InvalidateTimesheetDay venueId 0 2)

        it "plans profile and roster invalidations from staff resources" do
            let staffId = fromWords 3 0 0 0

            planLiveInvalidationsForResources [] (Set.fromList [StaffProfileResource staffId, StaffPreferencesResource staffId, StaffPayProfileResource staffId])
                `shouldBe` Set.fromList
                    [ InvalidateProfileContent staffId "profile"
                    , InvalidateRosterWeeksForStaff staffId
                    , InvalidateAdminXeroForStaff staffId
                    ]

        it "plans RSA profile and admin compliance invalidations from staff document resources" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0

            planLiveInvalidationsForResources [] (Set.fromList [StaffRsaDocumentsResource staffId, AdminStaffComplianceResource venueId])
                `shouldBe` Set.fromList
                    [ InvalidateProfileContent staffId "rsa"
                    , InvalidateAdminStaffCompliance venueId
                    ]
