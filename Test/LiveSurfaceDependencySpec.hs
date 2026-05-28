module Test.LiveSurfaceDependencySpec where

import Application.Helper.LiveResource
import Application.Helper.LiveSurface (TypedLiveSurfaceDefinition (..), typedLiveSurfaceAffectedFragments, typedSurfaceDependsOn)
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Controller.Context (ControllerContext)
import IHP.Prelude
import Test.Hspec
import Application.Support.LiveUpdates (SupportLiveFragment (..),
                                        supportLiveSurfaceDefinition)
import Web.Billing.LiveUpdates (BillingLiveFragment (..),
                                BillingSurfaceKey (..),
                                billingLiveSurfaceDefinition)
import Web.Profiles.LiveUpdates (ProfileContentFragment (..),
                                 ProfileContentSurfaceKey (..),
                                 ProfileLeaveSurfaceKey (..),
                                 profileContentLiveSurfaceDefinition,
                                 profileLeaveRequestsFragment,
                                 profileLeaveRequestsLiveSurfaceDefinition)
import Web.Timesheets.Projection (TimesheetProjectionFragment (..),
                                  TimesheetProjectionRequest (..),
                                  timesheetLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesFragment,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.VenueSettings (adminVenueSettingsFragment,
                                     adminVenueSettingsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinitionForVenue,
                            adminXeroPayItemsFragment,
                            adminXeroShellFragment,
                            adminXeroStaffMappingsFragment,
                            adminXeroTimesheetsFragment)

tests :: Spec
tests = do
    describe "Live surface resource dependencies" do
        it "declares timesheet week and day dependencies" do
            let venueId = fromWords 1 0 0 0
            let definition = timesheetLiveSurfaceDefinitionForVenue venueId
            let request = TimesheetProjectionRequest 2 True True Nothing

            typedSurfaceDependsOn definition request TimesheetProjectionPage
                `shouldBe` [TimesheetWeekResource venueId 2]
            typedSurfaceDependsOn definition request (TimesheetProjectionDaySection 4)
                `shouldBe` [TimesheetWeekResource venueId 2, TimesheetDayResource venueId 2 4]

        it "selects affected fragments from typed dependencies" do
            let venueId = fromWords 1 0 0 0
            let definition = timesheetLiveSurfaceDefinitionForVenue venueId
            let request = TimesheetProjectionRequest 2 True True Nothing
            let candidates = [TimesheetProjectionPage, TimesheetProjectionDaySection 4, TimesheetProjectionDaySection 5]

            typedLiveSurfaceAffectedFragments definition request (Set.fromList [TimesheetDayResource venueId 2 4]) candidates
                `shouldBe` [TimesheetProjectionDaySection 4]
            typedLiveSurfaceAffectedFragments definition request (Set.fromList [TimesheetWeekResource venueId 2]) candidates
                `shouldBe` candidates

        it "declares support dependencies by support fragment" do
            typedSurfaceDependsOn supportLiveSurfaceDefinition () SupportAwardRatesLiveFragment
                `shouldBe` [SupportAwardRatesResource]
            typedSurfaceDependsOn supportLiveSurfaceDefinition () SupportPublicHolidaysLiveFragment
                `shouldBe` [SupportPublicHolidaysResource]

        it "declares admin Xero dependencies by fragment" do
            let venueId = fromWords 2 0 0 0
            let definition = adminXeroLiveSurfaceDefinitionForVenue venueId
            let shellDependencies = Set.fromList (typedSurfaceDependsOn definition () adminXeroShellFragment)

            shellDependencies
                `shouldBe` Set.fromList
                    [ XeroConnectionResource venueId
                    , XeroMappingsResource venueId
                    , XeroPayItemsResource venueId
                    , XeroTimesheetsResource venueId
                    ]
            typedSurfaceDependsOn definition () adminXeroStaffMappingsFragment
                `shouldBe` [XeroMappingsResource venueId]
            typedSurfaceDependsOn definition () adminXeroPayItemsFragment
                `shouldBe` [XeroPayItemsResource venueId]
            typedSurfaceDependsOn definition () adminXeroTimesheetsFragment
                `shouldBe` [XeroTimesheetsResource venueId]

        it "declares billing dependencies for billing status fragments" do
            let venueId = fromWords 6 0 0 0
            let key = BillingSurfaceKey venueId

            typedSurfaceDependsOn billingLiveSurfaceDefinition key BillingStatusLiveFragment
                `shouldBe` [BillingResource venueId]

        it "declares profile dependencies by staff-backed section" do
            let ?context = error "profile dependency test does not use controller context" :: ControllerContext
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let contentKey = ProfileContentSurfaceKey venueId staffId "profile"
            let leaveKey = ProfileLeaveSurfaceKey venueId staffId

            typedSurfaceDependsOn profileContentLiveSurfaceDefinition contentKey ProfileDetailsContentFragment
                `shouldBe` [StaffProfileResource staffId, StaffPreferencesResource staffId]
            typedSurfaceDependsOn profileContentLiveSurfaceDefinition contentKey ProfileRsaContentFragment
                `shouldBe` [StaffRsaDocumentsResource staffId]
            typedSurfaceDependsOn profileLeaveRequestsLiveSurfaceDefinition leaveKey profileLeaveRequestsFragment
                `shouldBe` [StaffLeaveRequestsResource staffId]

        it "declares admin venue config dependencies for venue-scoped settings surfaces" do
            let venueId = fromWords 7 0 0 0
            let definition = adminVenueSettingsLiveSurfaceDefinitionForVenue venueId

            typedSurfaceDependsOn definition () adminVenueSettingsFragment
                `shouldBe` [AdminVenueConfigResource venueId]

        it "declares admin invitation dependencies for venue-scoped invite surfaces" do
            let venueId = fromWords 3 0 0 0
            let definition = adminInvitesLiveSurfaceDefinitionForVenue venueId
            let key = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }

            typedSurfaceDependsOn definition key adminInvitesFragment
                `shouldBe` [AdminInvitesResource venueId]
