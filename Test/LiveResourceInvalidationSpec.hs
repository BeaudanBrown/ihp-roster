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
        it "expands leave-calendar resources only to active roster week resources" do
            let venueId = fromWords 1 0 0 0
            let otherVenueId = fromWords 2 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let otherRosterGroupId = fromWords 5 0 0 0
            let activeScopes = [(venueId, rosterGroupId, 0), (otherVenueId, otherRosterGroupId, 0)]

            expandLiveResourcesWithoutContext activeScopes (Set.singleton (LeaveCalendarResource venueId 0))
                `shouldBe` Set.fromList
                    [ LeaveCalendarResource venueId 0
                    , RosterWeekResource rosterGroupId 0
                    ]

        it "does not expand leave-calendar resources to cold roster weeks" do
            let venueId = fromWords 1 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let activeScopes = [(venueId, rosterGroupId, 1)]

            expandLiveResourcesWithoutContext activeScopes (Set.singleton (LeaveCalendarResource venueId 0))
                `shouldBe` Set.singleton (LeaveCalendarResource venueId 0)

        it "leaves direct resources for dependency-derived live surface matching" do
            let venueId = fromWords 1 0 0 0
            let staffId = fromWords 3 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let directResources =
                    Set.fromList
                        [ LeaveRequestsResource venueId
                        , StaffLeaveRequestsResource staffId
                        , RosterWeekResource rosterGroupId 0
                        , TimesheetWeekResource venueId 0
                        , TimesheetDayResource venueId 0 2
                        , StaffRsaDocumentsResource staffId
                        , AdminInvitesResource venueId
                        , AdminRosterGroupsResource venueId
                        , AdminShiftTypesResource venueId
                        , AdminStaffComplianceResource venueId
                        , AdminExportsResource venueId
                        , BillingResource venueId
                        , SupportAwardRatesResource
                        , SupportPublicHolidaysResource
                        , XeroConnectionResource venueId
                        , XeroMappingsResource venueId
                        , XeroPayItemsResource venueId
                        , XeroTimesheetsResource venueId
                        ]

            expandLiveResourcesWithoutContext [] directResources
                `shouldBe` directResources
