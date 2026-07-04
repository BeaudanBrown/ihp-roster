module Test.LiveSurfaceDependencySpec where

import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveSurface (typedSurfaceDependsOn)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Support.LiveUpdates (supportAffectedMountedFragments,
                                        supportFragmentDependencies)
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.Billing.FrontendSurface (BillingScopeValue (..),
                                    billingAffectedMountedFragments,
                                    billingFragmentDependencies)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileAffectedMountedFragments,
                                     profileFragmentDependencies)
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidationsWithoutContext)
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
                `shouldBe` [timesheetWeekResource venueId 2, timesheetWeekBoundaryConfigResource venueId]
            timesheetsFragmentDependencies scope TimesheetSurfaceDayColumns
                `shouldBe` [timesheetWeekResource venueId 2, timesheetWeekBoundaryConfigResource venueId]
            timesheetsFragmentDependencies scope (TimesheetSurfaceDaySection 4)
                `shouldBe`
                    [ timesheetDayResource venueId 2 4
                    , timesheetWeekBoundaryConfigResource venueId
                    ]

        it "selects affected fragments from typed dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True Nothing

            map (.mountedFragmentTargetId) (timesheetsAffectedMountedFragments scope mountState (Set.fromList [timesheetDayResource venueId 2 4]))
                `shouldBe` ["timesheet-day-section-4"]
            map (.mountedFragmentTargetId) (timesheetsAffectedMountedFragments scope mountState (Set.fromList [timesheetWeekResource venueId 2]))
                `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"]

        it "plans affected fragments from generated FrontendSurface dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = timesheetWeekLiveScope venueId 2
            let subscription = liveTestSubscription scope [LiveUpdateWireFragment (timesheetDaySectionLiveFragment 4) "timesheet-day-section-4" "/ShowTimesheetDaySectionFragment?weekOffset=2&dayOffset=4&showApproved=true&showAllStaff=true" False NoProtection]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [timesheetDayResource venueId 2 4]) [subscription]

            map targetFragments targets
                `shouldBe` [[LiveUpdateWireFragment (timesheetDaySectionLiveFragment 4) "timesheet-day-section-4" "/ShowTimesheetDaySectionFragment?weekOffset=2&dayOffset=4&showApproved=true&showAllStaff=true" False NoProtection]]

        it "keeps generated dependency planning precise across surface resources" do
            let venueId = fromWords 2 0 0 0
            let adminScope = adminXeroLiveScope venueId
            let supportScope = supportPlatformLiveScope
            let subscriptions =
                    [ liveTestSubscription adminScope
                        [ LiveUpdateWireFragment adminXeroShellLiveFragment "admin-xero-shell" "/admin/xero" False NoProtection
                        , LiveUpdateWireFragment adminXeroStaffMappingsLiveFragment "admin-xero-staff-mappings" "/admin/xero/staff" False NoProtection
                        , LiveUpdateWireFragment adminXeroPayItemsLiveFragment "admin-xero-pay-items" "/admin/xero/pay-items" False NoProtection
                        , LiveUpdateWireFragment adminXeroTimesheetsLiveFragment "admin-xero-timesheets" "/admin/xero/timesheets" False NoProtection
                        ]
                    , liveTestSubscription supportScope
                        [ LiveUpdateWireFragment supportAwardRatesSectionLiveFragment "support-award-rates" "/support/award-rates" False NoProtection
                        ]
                    ]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [xeroPayItemsResource venueId]) subscriptions

            map (map fragmentKey . targetFragments) targets `shouldBe` [[adminXeroPayItemsLiveFragment]]

        it "declares support dependencies by support fragment" do
            let awardRatesFragments = supportAffectedMountedFragments (Set.fromList [supportAwardRatesResource])
            let publicHolidayFragments = supportAffectedMountedFragments (Set.fromList [supportPublicHolidaysResource])

            concatMap supportFragmentDependencies awardRatesFragments `shouldBe` [supportAwardRatesResource]
            concatMap supportFragmentDependencies publicHolidayFragments `shouldBe` [supportPublicHolidaysResource]

        it "declares admin Xero dependencies by fragment" do
            let venueId = fromWords 2 0 0 0
            let definition = adminXeroLiveSurfaceDefinitionForVenue venueId
            let shellDependencies = Set.fromList (typedSurfaceDependsOn definition () adminXeroShellFragment)

            shellDependencies
                `shouldBe` Set.fromList
                    [ xeroConnectionResource venueId
                    , xeroMappingsResource venueId
                    , xeroPayItemsResource venueId
                    , xeroTimesheetsResource venueId
                    ]
            typedSurfaceDependsOn definition () adminXeroStaffMappingsFragment
                `shouldBe` [xeroMappingsResource venueId]
            typedSurfaceDependsOn definition () adminXeroPayItemsFragment
                `shouldBe` [xeroPayItemsResource venueId]
            typedSurfaceDependsOn definition () adminXeroTimesheetsFragment
                `shouldBe` [xeroTimesheetsResource venueId]

        it "declares billing dependencies for billing status fragments" do
            let venueId = fromWords 6 0 0 0
            let scope = BillingScopeValue venueId
            let fragments = billingAffectedMountedFragments scope (Set.fromList [billingResource venueId])

            concatMap (billingFragmentDependencies scope) fragments `shouldBe` [billingResource venueId]

        it "declares profile dependencies by staff-backed section" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scope = ProfileScopeValue venueId staffId
            let affectedByProfile = profileAffectedMountedFragments scope (Set.fromList [staffProfileResource staffId])
            let affectedByRsa = profileAffectedMountedFragments scope (Set.fromList [staffRsaDocumentsResource staffId])
            let affectedByLeave = profileAffectedMountedFragments scope (Set.fromList [staffLeaveRequestsResource staffId])

            concatMap (profileFragmentDependencies scope) affectedByProfile
                `shouldBe` [staffProfileResource staffId, staffPreferencesResource staffId]
            concatMap (profileFragmentDependencies scope) affectedByRsa
                `shouldBe` [staffRsaDocumentsResource staffId]
            concatMap (profileFragmentDependencies scope) affectedByLeave
                `shouldBe` [staffLeaveRequestsResource staffId]

        it "declares admin venue settings dependencies for venue-scoped settings surfaces" do
            let venueId = fromWords 7 0 0 0
            let definition = adminVenueSettingsLiveSurfaceDefinitionForVenue venueId

            typedSurfaceDependsOn definition () adminVenueSettingsFragment
                `shouldBe` [adminVenueSettingsResource venueId]

        it "declares admin invitation dependencies for venue-scoped invite surfaces" do
            let venueId = fromWords 3 0 0 0
            let definition = adminInvitesLiveSurfaceDefinitionForVenue venueId
            let key = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }

            typedSurfaceDependsOn definition key adminInvitesFragment
                `shouldBe` [adminInvitesResource venueId]

liveTestSubscription :: LiveUpdateScope -> [LiveUpdateWireFragment] -> LiveUpdateSubscription
liveTestSubscription scope fragments =
    LiveUpdateSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = liveUpdateScopeKey scope
        , subscriptionMountedFragments = fragments
        }
