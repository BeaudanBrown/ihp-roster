module Test.LiveSurfaceDependencySpec where

import Application.Helper.FrontendSurface.DependencyPlanner (planFrontendSurfaceInvalidation)
import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Support.LiveUpdates (supportCandidateMountedFragments,
                                        supportLiveUpdateScope)
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.Billing.FrontendSurface (BillingScopeValue (..),
                                    billingCandidateMountedFragments,
                                    billingLiveUpdateScope)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileLiveUpdateScope)
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidationsWithoutContext)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsLiveUpdateScope)

tests :: Spec
tests = do
    describe "generated FrontendSurface resource dependencies" do
        it "selects affected timesheet fragments from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True Nothing
            let candidates = timesheetsCandidateMountedFragments scopeValue mountState
            let affectedByDay = planFrontendSurfaceInvalidation (Set.fromList [timesheetDayResource venueId 2 4]) (timesheetsLiveUpdateScope scopeValue) candidates
            let affectedByWeek = planFrontendSurfaceInvalidation (Set.fromList [timesheetWeekResource venueId 2]) (timesheetsLiveUpdateScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByDay `shouldBe` ["timesheet-day-section-4"]
            map (.mountedFragmentTargetId) affectedByWeek `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"]

        it "plans affected wire fragments from generated dependencies" do
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

        it "selects support fragments through generated dependencies" do
            let awardRatesFragments = planFrontendSurfaceInvalidation (Set.fromList [supportAwardRatesResource]) supportLiveUpdateScope supportCandidateMountedFragments
            let publicHolidayFragments = planFrontendSurfaceInvalidation (Set.fromList [supportPublicHolidaysResource]) supportLiveUpdateScope supportCandidateMountedFragments

            map (.mountedFragmentTargetId) awardRatesFragments `shouldBe` ["support-award-rates-section"]
            map (.mountedFragmentTargetId) publicHolidayFragments `shouldBe` ["support-public-holidays-section"]

        it "selects billing fragments through generated dependencies" do
            let venueId = fromWords 6 0 0 0
            let scopeValue = BillingScopeValue venueId
            let fragments = planFrontendSurfaceInvalidation (Set.fromList [billingResource venueId]) (billingLiveUpdateScope scopeValue) (billingCandidateMountedFragments "/ShowbillingStatusLiveFragment")

            map (.mountedFragmentTargetId) fragments `shouldBe` ["billing-status-fragment"]

        it "selects profile fragments through generated staff-backed dependencies" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scopeValue = ProfileScopeValue venueId staffId
            let candidates = profileCandidateMountedFragments scopeValue
            let affectedByProfile = planFrontendSurfaceInvalidation (Set.fromList [staffProfileResource staffId]) (profileLiveUpdateScope scopeValue) candidates
            let affectedByRsa = planFrontendSurfaceInvalidation (Set.fromList [staffRsaDocumentsResource staffId]) (profileLiveUpdateScope scopeValue) candidates
            let affectedByLeave = planFrontendSurfaceInvalidation (Set.fromList [staffLeaveRequestsResource staffId]) (profileLiveUpdateScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByProfile `shouldBe` ["profile-details"]
            map (.mountedFragmentTargetId) affectedByRsa `shouldBe` ["profile-rsa"]
            map (.mountedFragmentTargetId) affectedByLeave `shouldBe` ["profile-leave"]

liveTestSubscription :: LiveUpdateScope -> [LiveUpdateWireFragment] -> LiveUpdateSubscription
liveTestSubscription scope fragments =
    LiveUpdateSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = liveUpdateScopeKey scope
        , subscriptionMountedFragments = fragments
        }
