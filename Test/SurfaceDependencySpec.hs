module Test.SurfaceDependencySpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.FrontendContract.Surface.Billing.Resource
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..),
                                                            frontendSurfaceMountConfigJson)
import qualified Application.Helper.FrontendContract.Surface.Support.Live as SupportLive
import Application.Helper.FrontendContract.Surface.Support.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as TimesheetsLive
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.LiveUpdate (actorLiveFragmentsRefreshKeys)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Support.LiveUpdates (supportCandidateMountedFragments,
                                        supportSurfaceScope)
import qualified Data.Set as Set
import qualified Data.Text as Text
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
                                          leaveRequestsSurfaceImpl,
                                          leaveRequestsSurfaceScope)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceScope)
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterMountedFragmentForProjection,
                                        rosterSurfaceScope)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))
import Web.Routes ()
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidationsWithoutContext)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceFragmentKeys,
                                       timesheetsSurfaceScope)
import Web.Types

tests :: Spec
tests = do
    describe "generated FrontendSurface resource dependencies" do
        it "selects affected timesheet fragments from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True True Nothing
            let candidates = timesheetsCandidateMountedFragments scopeValue mountState
            let affectedByDay = planMountedFragments (Set.fromList [timesheetDayResource venueId 2 4]) (timesheetsSurfaceScope scopeValue) candidates
            let affectedByWeek = planMountedFragments (Set.fromList [timesheetWeekResource venueId 2]) (timesheetsSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByDay `shouldBe` ["timesheet-day-section-4"]
            map (.mountedFragmentTargetId) affectedByWeek `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"]

        it "coalesces actor mount keys through the same dependency plan as passive subscriptions" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId 2
            let mountState = TimesheetsMountStateValue True True True Nothing
            let scope = timesheetsSurfaceScope scopeValue
            let mountedFragments = timesheetsCandidateMountedFragments scopeValue mountState
            let duplicatedMount = mountedFragments <> mountedFragments
            let resources = Set.fromList [timesheetDayResource venueId 2 4]
            let actorFragmentKeys = actorLiveFragmentsRefreshKeys scope resources duplicatedMount
            let passiveTargets =
                    planSurfaceInvalidationsWithoutContext
                        resources
                        [liveTestSubscription scope (timesheetsSurfaceFragmentKeys duplicatedMount)]

            actorFragmentKeys `shouldBe` concatMap (.targetFragments) passiveTargets
            actorFragmentKeys `shouldBe` [TimesheetsLive.timesheetDaySectionLiveFragment 4]

        it "selects parameterized leave section fragments from generated dependencies" do
            let venueId = fromWords 10 0 0 0
            let scopeValue = LeaveRequestsScopeValue venueId
            let candidates = leaveRequestsCandidateMountedFragments scopeValue
            let pendingResources = Set.fromList [leaveRequestsSectionResource venueId "pending"]
            let approvedResources = Set.fromList [leaveRequestsSectionResource venueId "approved"]
            let affectedByPending = planMountedFragments pendingResources (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedByApproved = planMountedFragments approvedResources (leaveRequestsSurfaceScope scopeValue) candidates

            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) pendingResources candidates
                `shouldBe` passiveFragmentKeys pendingResources (leaveRequestsSurfaceScope scopeValue) candidates
            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) approvedResources candidates
                `shouldBe` passiveFragmentKeys approvedResources (leaveRequestsSurfaceScope scopeValue) candidates
            map (.mountedFragmentTargetId) affectedByPending `shouldBe` ["leave-pending-count", "leave-pending-list"]
            map (.mountedFragmentTargetId) affectedByApproved `shouldBe` ["leave-approved-count", "leave-approved-list"]

        it "keeps subscription scope singular and executable descriptors local" do
            let scopeValue = LeaveRequestsScopeValue (fromWords 10 0 0 0)
            let configJson = frontendSurfaceMountConfigJson (leaveRequestsSurfaceImpl scopeValue).surfaceImplMountConfig

            Text.count "\"fragmentKey\":" configJson `shouldBe` 8
            configJson `shouldSatisfy` Text.isInfixOf "\"subscription\":{\"scope\":{"
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"resyncFragments\"")
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"mountState\"")
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"loadPolicy\"")

        it "plans affected semantic fragment keys from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetsLive.timesheetWeekLiveScope venueId 2
            let subscription = liveTestSubscription scope [TimesheetsLive.timesheetDaySectionLiveFragment 4]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [timesheetDayResource venueId 2 4]) [subscription]

            map targetFragments targets
                `shouldBe` [[TimesheetsLive.timesheetDaySectionLiveFragment 4]]

        it "keeps generated dependency planning precise across surface resources" do
            let venueId = fromWords 2 0 0 0
            let adminScope = AdminLive.adminXeroLiveScope venueId
            let supportScope = SupportLive.supportPlatformLiveScope
            let subscriptions =
                    [ liveTestSubscription adminScope [AdminLive.adminXeroShellLiveFragment]
                    , liveTestSubscription supportScope [SupportLive.supportAwardRatesLiveFragment]
                    ]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [xeroConnectionResource venueId]) subscriptions

            map targetFragments targets `shouldBe` [[AdminLive.adminXeroShellLiveFragment]]

        it "keeps the retained Admin Xero refetch descriptor local to the mount" do
            let mountedFragments = [AdminSurface.adminXeroShellFragment]

            AdminSurface.adminXeroFragmentKeys mountedFragments `shouldBe` [AdminLive.adminXeroShellLiveFragment]
            map (.mountedFragmentTargetId) mountedFragments `shouldBe` ["admin-xero-fragment"]
            map (.mountedFragmentUrl) mountedFragments `shouldBe` [pathTo ShowadminXeroShellLiveFragmentAction]

        it "maps only Xero connection changes to the retained shell" do
            let venueId = fromWords 3 0 0 0
            let scope = AdminLive.adminXeroLiveScope venueId
            let fragmentKeys = AdminSurface.adminXeroFragmentKeys [AdminSurface.adminXeroShellFragment]
            let subscription = liveTestSubscription scope fragmentKeys
            let plannedFor resource = map (.targetFragments) (planSurfaceInvalidationsWithoutContext (Set.fromList [resource venueId]) [subscription])

            plannedFor xeroConnectionResource `shouldBe` [[AdminLive.adminXeroShellLiveFragment]]
            plannedFor adminShiftTypesResource `shouldBe` []
            plannedFor billingResource `shouldBe` []
            plannedFor timesheetWeekBoundaryConfigResource `shouldBe` []

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

        it "normalizes roster wrapper containment without replacing the grid scroll owner" do
            let venueId = fromWords 7 0 0 0
            let rosterGroupUuid = fromWords 8 0 0 0
            let rosterDayUuid = fromWords 9 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let rosterDayId = Id rosterDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 3 Nothing
            let scope = rosterSurfaceScope scopeValue
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 2)] }
            let resources = Set.fromList
                    [ rosterWeekResource rosterGroupUuid 3
                    , rosterDayResource rosterDayUuid
                    ]

            passiveFragmentKeys resources scope (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterGridToolbarLiveFragment
                    , RosterLive.rosterDayColumnsLiveFragment
                    , RosterLive.rosterDayRailLiveFragment
                    , RosterLive.rosterWageRailLiveFragment
                    , RosterLive.rosterSlotsGridLiveFragment
                    , RosterLive.rosterStaffPanelLiveFragment
                    , RosterLive.rosterDaySectionLiveFragment rosterDayUuid
                    ]

        it "keeps a parameterized child when the selected ancestor is a different instance" do
            let venueId = fromWords 17 0 0 0
            let rosterGroupId = Id (fromWords 18 0 0 0) :: Id RosterGroup
            let ancestorDayUuid = fromWords 19 0 0 0
            let childDayUuid = fromWords 20 0 0 0
            let ancestorDayId = Id ancestorDayUuid :: Id RosterDay
            let childDayId = Id childDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 3 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [ancestorDayId], rosterMountedRows = [(childDayId, 2)] }

            passiveFragmentKeys
                (Set.singleton (rosterEndTimesConfigResource venueId))
                (rosterSurfaceScope scopeValue)
                (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterGridToolbarLiveFragment
                    , RosterLive.rosterDayColumnsLiveFragment
                    , RosterLive.rosterDayRailLiveFragment
                    , RosterLive.rosterWageRailLiveFragment
                    , RosterLive.rosterSlotsGridLiveFragment
                    , RosterLive.rosterDaySectionLiveFragment ancestorDayUuid
                    , RosterLive.rosterRowLiveFragment childDayUuid 2
                    ]

        it "selects support fragments through generated dependencies" do
            let awardRatesFragments = planMountedFragments (Set.fromList [supportAwardRatesResource]) supportSurfaceScope supportCandidateMountedFragments
            let publicHolidayFragments = planMountedFragments (Set.fromList [supportPublicHolidaysResource]) supportSurfaceScope supportCandidateMountedFragments

            map (.mountedFragmentTargetId) awardRatesFragments `shouldBe` ["support-award-rates"]
            map (.mountedFragmentTargetId) publicHolidayFragments `shouldBe` ["support-public-holidays"]

        it "selects billing fragments through generated dependencies" do
            let venueId = fromWords 6 0 0 0
            let scopeValue = BillingScopeValue venueId
            let checkoutState = BillingCheckoutReturnState False Nothing
            let fragments = planMountedFragments (Set.fromList [billingResource venueId]) (billingSurfaceScope scopeValue) (billingCandidateMountedFragments checkoutState)

            map (.mountedFragmentTargetId) fragments `shouldBe` ["billing-status-fragment"]

        it "selects profile fragments through generated staff-backed dependencies" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scopeValue = ProfileScopeValue venueId staffId
            let candidates = profileCandidateMountedFragments scopeValue
            let affectedByProfile = planMountedFragments (Set.fromList [staffProfileResource staffId]) (profileSurfaceScope scopeValue) candidates
            let affectedByRsa = planMountedFragments (Set.fromList [staffRsaDocumentsResource staffId]) (profileSurfaceScope scopeValue) candidates
            let affectedByLeave = planMountedFragments (Set.fromList [staffLeaveRequestsResource staffId]) (profileSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByProfile `shouldBe` ["profile-details"]
            map (.mountedFragmentTargetId) affectedByRsa `shouldBe` ["profile-rsa"]
            map (.mountedFragmentTargetId) affectedByLeave `shouldBe` ["profile-leave"]

planMountedFragments :: Set.Set SurfaceResourceValue -> SurfaceScope -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
planMountedFragments resources scope mountedFragments =
    [ mountedFragment
    | (mountedFragment, fragmentKey) <- zip mountedFragments mountedKeys
    , fragmentKey `Set.member` affectedKeys
    ]
  where
    mountedKeys = map (.mountedFragmentKey) mountedFragments
    affectedKeys = Set.fromList (actorLiveFragmentsRefreshKeys scope resources mountedFragments)

passiveFragmentKeys :: Set.Set SurfaceResourceValue -> SurfaceScope -> [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
passiveFragmentKeys resources scope mountedFragments =
    planSurfaceInvalidationsWithoutContext
        resources
        [liveTestSubscription scope (map (.mountedFragmentKey) mountedFragments)]
        |> concatMap (.targetFragments)

liveTestSubscription :: SurfaceScope -> [SurfaceFragmentKey] -> SurfaceSubscription
liveTestSubscription scope fragmentKeys =
    SurfaceSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = surfaceScopeKey scope
        , subscriptionFragmentKeys = fragmentKeys
        }
