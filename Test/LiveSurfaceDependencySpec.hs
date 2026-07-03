module Test.LiveSurfaceDependencySpec where

import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveResource
import Application.Helper.LiveSurface (typedSurfaceDependsOn)
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment (..))
import Application.Support.LiveUpdates (supportAffectedMountedFragments,
                                        supportFragmentDependencies)
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.Billing.FrontendSurface (BillingScopeValue (..),
                                    billingAffectedMountedFragments,
                                    billingFragmentDependencies)
import Web.LiveSurfaceRegistry (LiveSurfaceInvalidationTarget (..),
                                planRegisteredLiveSurfaceInvalidationsWithoutContext)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileAffectedMountedFragments,
                                     profileFragmentDependencies)
import Web.Timesheets.FrontendSurface (TimesheetSurfaceFragment (..),
                                       TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsAffectedMountedFragments,
                                       timesheetsFragmentDependencies)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesFragment,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.VenueSettings (adminVenueSettingsFragment,
                                     adminVenueSettingsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinitionForVenue,
                            adminXeroPayItemsFragment, adminXeroShellFragment,
                            adminXeroStaffMappingsFragment,
                            adminXeroTimesheetsFragment)

tests :: Spec
tests = do
    describe "Live surface resource dependencies" do
        it "declares timesheet week and day dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetWeekScopeValue venueId 2

            timesheetsFragmentDependencies scope TimesheetSurfaceToolbar
                `shouldBe` [TimesheetWeekResource venueId 2, TimesheetWeekBoundaryConfigResource venueId]
            timesheetsFragmentDependencies scope TimesheetSurfaceDayColumns
                `shouldBe` [TimesheetWeekResource venueId 2, TimesheetWeekBoundaryConfigResource venueId]
            timesheetsFragmentDependencies scope (TimesheetSurfaceDaySection 4)
                `shouldBe`
                    [ TimesheetDayResource venueId 2 4
                    , TimesheetWeekBoundaryConfigResource venueId
                    ]

        it "selects affected fragments from typed dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True Nothing

            map (.mountedFragmentTargetId) (timesheetsAffectedMountedFragments scope mountState (Set.fromList [TimesheetDayResource venueId 2 4]))
                `shouldBe` ["timesheet-day-section-4"]
            map (.mountedFragmentTargetId) (timesheetsAffectedMountedFragments scope mountState (Set.fromList [TimesheetWeekResource venueId 2]))
                `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"]

        it "plans affected fragments from generated FrontendSurface dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetWeekScope { venueId, weekOffset = 2 }
            let targets = planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.fromList [TimesheetDayResource venueId 2 4]) [scope]

            map targetFragments targets
                `shouldBe` [[LiveUpdateWireFragment (TimesheetDaySectionFragment 4) "timesheet-day-section-4" "/ShowTimesheetDaySectionFragment?weekOffset=2&dayOffset=4&showApproved=true&showAllStaff=true" False NoProtection]]

        it "keeps generated dependency planning precise across surface resources" do
            let venueId = fromWords 2 0 0 0
            let scopes = [AdminXeroScope { venueId }, SupportPlatformScope]
            let targets = planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.fromList [XeroPayItemsResource venueId]) scopes

            map (map fragmentKey . targetFragments) targets `shouldBe` [[AdminXeroPayItemsFragment]]

        it "declares support dependencies by support fragment" do
            let awardRatesFragments = supportAffectedMountedFragments (Set.fromList [SupportAwardRatesResource])
            let publicHolidayFragments = supportAffectedMountedFragments (Set.fromList [SupportPublicHolidaysResource])

            concatMap supportFragmentDependencies awardRatesFragments `shouldBe` [SupportAwardRatesResource]
            concatMap supportFragmentDependencies publicHolidayFragments `shouldBe` [SupportPublicHolidaysResource]

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
            let scope = BillingScopeValue venueId
            let fragments = billingAffectedMountedFragments scope (Set.fromList [BillingResource venueId])

            concatMap (billingFragmentDependencies scope) fragments `shouldBe` [BillingResource venueId]

        it "declares profile dependencies by staff-backed section" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scope = ProfileScopeValue venueId staffId
            let affectedByProfile = profileAffectedMountedFragments scope (Set.fromList [StaffProfileResource staffId])
            let affectedByRsa = profileAffectedMountedFragments scope (Set.fromList [StaffRsaDocumentsResource staffId])
            let affectedByLeave = profileAffectedMountedFragments scope (Set.fromList [StaffLeaveRequestsResource staffId])

            concatMap (profileFragmentDependencies scope) affectedByProfile
                `shouldBe` [StaffProfileResource staffId, StaffPreferencesResource staffId]
            concatMap (profileFragmentDependencies scope) affectedByRsa
                `shouldBe` [StaffRsaDocumentsResource staffId]
            concatMap (profileFragmentDependencies scope) affectedByLeave
                `shouldBe` [StaffLeaveRequestsResource staffId]

        it "declares admin venue settings dependencies for venue-scoped settings surfaces" do
            let venueId = fromWords 7 0 0 0
            let definition = adminVenueSettingsLiveSurfaceDefinitionForVenue venueId

            typedSurfaceDependsOn definition () adminVenueSettingsFragment
                `shouldBe` [AdminVenueSettingsResource venueId]

        it "declares admin invitation dependencies for venue-scoped invite surfaces" do
            let venueId = fromWords 3 0 0 0
            let definition = adminInvitesLiveSurfaceDefinitionForVenue venueId
            let key = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }

            typedSurfaceDependsOn definition key adminInvitesFragment
                `shouldBe` [AdminInvitesResource venueId]
