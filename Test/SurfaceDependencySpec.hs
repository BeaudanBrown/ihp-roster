module Test.SurfaceDependencySpec where

import Application.Helper.FrontendContract.Surface.DependencyPlanner (planFrontendSurfaceInvalidation)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..))
import Application.Helper.LiveUpdate (actorLiveFragmentsRefreshKeys)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Support.LiveUpdates (supportCandidateMountedFragments,
                                        supportSurfaceScope)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Set as Set
import Data.UUID (fromWords)
import Generated.Types (RosterDay, RosterGroup)
import IHP.ControllerPrelude (pathTo)
import IHP.ModelSupport.Types (Id' (..))
import IHP.Prelude
import Test.Hspec
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Billing.FrontendSurface (BillingCheckoutReturnState (..),
                                    BillingScopeValue (..),
                                    billingCandidateMountedFragments,
                                    billingSurfaceScope)
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsCandidateMountedFragments,
                                          leaveRequestsSurfaceFragmentKeys,
                                          leaveRequestsSurfaceImpl,
                                          leaveRequestsSurfaceScope)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceScope)
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterMountedFragmentForProjection)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))
import Web.Routes ()
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidationsWithoutContext)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceScope)
import Web.Types

tests :: Spec
tests = do
    describe "generated FrontendSurface resource dependencies" do
        it "selects affected timesheet fragments from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True Nothing
            let candidates = timesheetsCandidateMountedFragments scopeValue mountState
            let affectedByDay = planFrontendSurfaceInvalidation (Set.fromList [timesheetDayResource venueId 2 4]) (timesheetsSurfaceScope scopeValue) candidates
            let affectedByWeek = planFrontendSurfaceInvalidation (Set.fromList [timesheetWeekResource venueId 2]) (timesheetsSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByDay `shouldBe` ["timesheet-day-section-4"]
            map (.mountedFragmentTargetId) affectedByWeek `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"]

        it "uses the same dependency planner for actor-local resource refreshes" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True Nothing
            let scope = timesheetsSurfaceScope scopeValue
            let candidates = timesheetsCandidateMountedFragments scopeValue mountState
            let fragmentKeys = actorLiveFragmentsRefreshKeys scope (Set.fromList [timesheetDayResource venueId 2 4]) candidates

            fragmentKeys `shouldBe` [timesheetDaySectionLiveFragment 4]

        it "selects parameterized leave section fragments from generated dependencies" do
            let venueId = fromWords 10 0 0 0
            let scopeValue = LeaveRequestsScopeValue venueId
            let candidates = leaveRequestsCandidateMountedFragments scopeValue
            let affectedByPending = planFrontendSurfaceInvalidation (Set.fromList [leaveRequestsSectionResource venueId "pending"]) (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedByApproved = planFrontendSurfaceInvalidation (Set.fromList [leaveRequestsSectionResource venueId "approved"]) (leaveRequestsSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByPending `shouldBe` ["leave-pending-count", "leave-pending-list"]
            map (.mountedFragmentTargetId) affectedByApproved `shouldBe` ["leave-approved-count", "leave-approved-list"]

        it "derives subscription keys from the exact local mounted-fragment set" do
            let scopeValue = LeaveRequestsScopeValue (fromWords 10 0 0 0)
            let impl = leaveRequestsSurfaceImpl scopeValue
            let candidates = leaveRequestsCandidateMountedFragments scopeValue
            let expectedKeys = map (Aeson.toJSON . surfaceFragmentKeyToWire) (leaveRequestsSurfaceFragmentKeys candidates)
            let subscriptionKeys = impl.surfaceImplMountConfig.mountSubscription >>= AesonTypes.parseMaybe (Aeson.withObject "FrontendSurfaceLiveSubscription" (Aeson..: "resyncFragments"))

            subscriptionKeys `shouldBe` Just expectedKeys

        it "plans affected semantic fragment keys from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = timesheetWeekLiveScope venueId 2
            let subscription = liveTestSubscription scope [timesheetDaySectionLiveFragment 4]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [timesheetDayResource venueId 2 4]) [subscription]

            map targetFragments targets
                `shouldBe` [[timesheetDaySectionLiveFragment 4]]

        it "keeps generated dependency planning precise across surface resources" do
            let venueId = fromWords 2 0 0 0
            let adminScope = adminXeroLiveScope venueId
            let supportScope = supportPlatformLiveScope
            let subscriptions =
                    [ liveTestSubscription adminScope [adminXeroShellLiveFragment]
                    , liveTestSubscription supportScope [supportAwardRatesSectionLiveFragment]
                    ]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [xeroConnectionResource venueId]) subscriptions

            map targetFragments targets `shouldBe` [[adminXeroShellLiveFragment]]

        it "keeps the retained Admin Xero refetch descriptor local to the mount" do
            let mountedFragments = [AdminSurface.adminXeroShellFragment]

            AdminSurface.adminSurfaceFragmentKeys mountedFragments `shouldBe` [adminXeroShellLiveFragment]
            map (.mountedFragmentTargetId) mountedFragments `shouldBe` ["admin-xero-fragment"]
            map (.mountedFragmentUrl) mountedFragments `shouldBe` [pathTo ShowadminXeroShellLiveFragmentAction]

        it "maps only Xero connection changes to the retained shell" do
            let venueId = fromWords 3 0 0 0
            let scope = adminXeroLiveScope venueId
            let fragmentKeys = AdminSurface.adminSurfaceFragmentKeys [AdminSurface.adminXeroShellFragment]
            let subscription = liveTestSubscription scope fragmentKeys
            let plannedFor resource = map (.targetFragments) (planSurfaceInvalidationsWithoutContext (Set.fromList [resource venueId]) [subscription])

            plannedFor xeroConnectionResource `shouldBe` [[adminXeroShellLiveFragment]]
            plannedFor xeroMappingsResource `shouldBe` []
            plannedFor xeroPayItemsResource `shouldBe` []
            plannedFor xeroTimesheetsResource `shouldBe` []

        it "declares exact roster projection fragment targets for mounted refetches" do
            let venueId = fromWords 7 0 0 0
            let rosterGroupId = Id (fromWords 8 0 0 0) :: Id RosterGroup
            let rosterDayId = Id (fromWords 9 0 0 0) :: Id RosterDay
            let scope = RosterWeekScopeValue venueId rosterGroupId 3 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 2)] }
            let candidates = rosterCandidateMountedFragments scope plan
            map (.mountedFragmentTargetId) candidates
                `shouldBe`
                    [ "roster-content"
                    , "roster-grid-toolbar"
                    , "roster-grid-frame"
                    , "roster-day-columns"
                    , "roster-day-rail"
                    , "roster-wage-rail"
                    , "roster-slots-grid"
                    , "roster-staff-panel-fragment"
                    , "roster-staff-self-service-leave-form-fragment"
                    , "roster-day-section-" <> tshow rosterDayId
                    , "roster-row-" <> tshow rosterDayId <> "-2"
                    ]
            let selectedMountedFragments = map (rosterMountedFragmentForProjection scope) [RosterProjectionGridToolbar, RosterProjectionDaySection (fromWords 9 0 0 0), RosterProjectionRow (fromWords 9 0 0 0) 2]
            map (.mountedFragmentTargetId) selectedMountedFragments
                `shouldBe`
                    [ "roster-grid-toolbar"
                    , "roster-day-section-" <> tshow rosterDayId
                    , "roster-row-" <> tshow rosterDayId <> "-2"
                    ]

        it "selects support fragments through generated dependencies" do
            let awardRatesFragments = planFrontendSurfaceInvalidation (Set.fromList [supportAwardRatesResource]) supportSurfaceScope supportCandidateMountedFragments
            let publicHolidayFragments = planFrontendSurfaceInvalidation (Set.fromList [supportPublicHolidaysResource]) supportSurfaceScope supportCandidateMountedFragments

            map (.mountedFragmentTargetId) awardRatesFragments `shouldBe` ["support-award-rates-section"]
            map (.mountedFragmentTargetId) publicHolidayFragments `shouldBe` ["support-public-holidays-section"]

        it "selects billing fragments through generated dependencies" do
            let venueId = fromWords 6 0 0 0
            let scopeValue = BillingScopeValue venueId
            let checkoutState = BillingCheckoutReturnState False Nothing
            let fragments = planFrontendSurfaceInvalidation (Set.fromList [billingResource venueId]) (billingSurfaceScope scopeValue) (billingCandidateMountedFragments checkoutState)

            map (.mountedFragmentTargetId) fragments `shouldBe` ["billing-status-fragment"]

        it "selects profile fragments through generated staff-backed dependencies" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scopeValue = ProfileScopeValue venueId staffId
            let candidates = profileCandidateMountedFragments scopeValue
            let affectedByProfile = planFrontendSurfaceInvalidation (Set.fromList [staffProfileResource staffId]) (profileSurfaceScope scopeValue) candidates
            let affectedByRsa = planFrontendSurfaceInvalidation (Set.fromList [staffRsaDocumentsResource staffId]) (profileSurfaceScope scopeValue) candidates
            let affectedByLeave = planFrontendSurfaceInvalidation (Set.fromList [staffLeaveRequestsResource staffId]) (profileSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByProfile `shouldBe` ["profile-details"]
            map (.mountedFragmentTargetId) affectedByRsa `shouldBe` ["profile-rsa"]
            map (.mountedFragmentTargetId) affectedByLeave `shouldBe` ["profile-leave"]

liveTestSubscription :: SurfaceScope -> [SurfaceFragmentKey] -> SurfaceSubscription
liveTestSubscription scope fragmentKeys =
    SurfaceSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = surfaceScopeKey scope
        , subscriptionFragmentKeys = fragmentKeys
        }
