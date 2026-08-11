module Test.SurfaceDependencySpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.FrontendContract.Surface.Billing.Resource
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue (..))
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..),
                                                            frontendSurfaceMountConfigJson)
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Live as SelfServiceLeaveLive
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
import Data.Time.Calendar (addDays)
import Data.UUID (fromWords)
import Generated.Types (RosterDay, RosterGroup, User)
import IHP.ControllerPrelude (pathTo)
import IHP.ModelSupport.Types (Id' (..))
import IHP.Prelude
import Test.Hspec
import Test.Support (testAnchorForOffset)
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Billing.FrontendSurface (BillingCheckoutReturnState (..),
                                    BillingScopeValue (..),
                                    billingCandidateMountedFragments,
                                    billingSurfaceScope)
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          SelfServiceLeaveScopeValue (..),
                                          leaveRequestsCandidateMountedFragments,
                                          leaveRequestsSurfaceImpl,
                                          leaveRequestsSurfaceScope,
                                          selfServiceLeaveSurfaceImpl,
                                          selfServiceLeaveSurfaceScope)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceScope,
                                     staffCandidateMountedFragments,
                                     staffSurfaceScope)
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
    describe "shared self-service leave Surface" do
        it "mounts the same form fragment contract in Profile and roster contexts" do
            let venueId = fromWords 1 0 0 0
            let staffId = fromWords 2 0 0 0
            let scope = SelfServiceLeaveScopeValue venueId staffId
            let profileMount = (selfServiceLeaveSurfaceImpl "profile" True scope).surfaceImplMountConfig
            let rosterMount = (selfServiceLeaveSurfaceImpl "roster" False scope).surfaceImplMountConfig

            profileMount.mountKey `shouldBe` "profile"
            rosterMount.mountKey `shouldBe` "roster"
            map (.mountedFragmentKey) profileMount.mountFragments
                `shouldBe`
                    [ SelfServiceLeaveLive.visibleUnavailabilityBlackoutsLiveFragment
                    , SelfServiceLeaveLive.selfServiceLeaveFormLiveFragment
                    , SelfServiceLeaveLive.selfServiceLeaveHistoryLiveFragment
                    ]
            map (.mountedFragmentKey) rosterMount.mountFragments
                `shouldBe`
                    [ SelfServiceLeaveLive.visibleUnavailabilityBlackoutsLiveFragment
                    , SelfServiceLeaveLive.selfServiceLeaveFormLiveFragment
                    ]
            map (.mountedFragmentTargetId) (take 2 profileMount.mountFragments)
                `shouldBe` map (.mountedFragmentTargetId) rosterMount.mountFragments

    describe "generated FrontendSurface resource dependencies" do
        it "selects affected timesheet fragments from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2)) 1
            let mountState = TimesheetsMountStateValue Nothing
            let candidates = timesheetsCandidateMountedFragments scopeValue mountState
            let affectedByDay = planMountedFragments (Set.fromList [timesheetDayResource venueId (addDays 4 (testAnchorForOffset 2))]) (timesheetsSurfaceScope scopeValue) candidates
            let affectedByWeek = planMountedFragments (Set.fromList [timesheetWeekResource venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2))]) (timesheetsSurfaceScope scopeValue) candidates

            map (.mountedFragmentTargetId) affectedByDay `shouldBe` ["timesheet-day-section-2025-01-24"]
            map (.mountedFragmentTargetId) affectedByWeek `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns", "timesheet-side-panel-content"]

        it "coalesces actor mount keys through the same dependency plan as passive subscriptions" do
            let venueId = fromWords 1 0 0 0
            let scopeValue = TimesheetWeekScopeValue venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2)) 1
            let mountState = TimesheetsMountStateValue Nothing
            let scope = timesheetsSurfaceScope scopeValue
            let mountedFragments = timesheetsCandidateMountedFragments scopeValue mountState
            let duplicatedMount = mountedFragments <> mountedFragments
            let resources = Set.fromList [timesheetDayResource venueId (addDays 4 (testAnchorForOffset 2))]
            let actorFragmentKeys = actorLiveFragmentsRefreshKeys scope resources duplicatedMount
            let passiveTargets =
                    planSurfaceInvalidationsWithoutContext
                        resources
                        [liveTestSubscription scope (timesheetsSurfaceFragmentKeys duplicatedMount)]

            actorFragmentKeys `shouldBe` concatMap (.targetFragments) passiveTargets
            actorFragmentKeys `shouldBe` [TimesheetsLive.timesheetDaySectionLiveFragment (addDays 4 (testAnchorForOffset 2))]

        it "selects parameterized leave section fragments from generated dependencies" do
            let venueId = fromWords 10 0 0 0
            let scopeValue = LeaveRequestsScopeValue venueId
            let candidates = leaveRequestsCandidateMountedFragments scopeValue
            let blackoutResources = Set.fromList [unavailabilityBlackoutsResource venueId]
            let warningResources = Set.fromList [leaveAvailabilityWarningsResource venueId]
            let pendingResources = Set.fromList [leaveRequestsSectionResource venueId LeavePendingSection]
            let approvedResources = Set.fromList [leaveRequestsSectionResource venueId LeaveApprovedSection]
            let sidePanelAndBlackoutResources = Set.fromList [unavailabilityBlackoutsResource venueId, leaveAvailabilityWarningsResource venueId]
            let affectedByBlackouts = planMountedFragments blackoutResources (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedByWarnings = planMountedFragments warningResources (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedByPending = planMountedFragments pendingResources (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedByApproved = planMountedFragments approvedResources (leaveRequestsSurfaceScope scopeValue) candidates
            let affectedBySidePanelAndBlackouts = planMountedFragments sidePanelAndBlackoutResources (leaveRequestsSurfaceScope scopeValue) candidates

            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) blackoutResources candidates
                `shouldBe` passiveFragmentKeys blackoutResources (leaveRequestsSurfaceScope scopeValue) candidates
            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) warningResources candidates
                `shouldBe` passiveFragmentKeys warningResources (leaveRequestsSurfaceScope scopeValue) candidates
            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) pendingResources candidates
                `shouldBe` passiveFragmentKeys pendingResources (leaveRequestsSurfaceScope scopeValue) candidates
            actorLiveFragmentsRefreshKeys (leaveRequestsSurfaceScope scopeValue) approvedResources candidates
                `shouldBe` passiveFragmentKeys approvedResources (leaveRequestsSurfaceScope scopeValue) candidates
            map (.mountedFragmentTargetId) affectedByBlackouts `shouldBe` ["unavailability-blackouts"]
            map (.mountedFragmentTargetId) affectedByWarnings `shouldBe` ["leave-side-panel-content", "leave-availability-warnings"]
            map (.mountedFragmentTargetId) affectedByPending `shouldBe` ["leave-pending-count", "leave-pending-list"]
            map (.mountedFragmentTargetId) affectedByApproved `shouldBe` ["leave-approved-count", "leave-approved-list"]
            map (.mountedFragmentTargetId) affectedBySidePanelAndBlackouts `shouldBe` ["leave-side-panel-content", "leave-availability-warnings"]

        it "keeps subscription scope singular and executable descriptors local" do
            let scopeValue = LeaveRequestsScopeValue (fromWords 10 0 0 0)
            let configJson = frontendSurfaceMountConfigJson (leaveRequestsSurfaceImpl scopeValue).surfaceImplMountConfig

            Text.count "\"fragmentKey\":" configJson `shouldBe` 11
            configJson `shouldSatisfy` Text.isInfixOf "\"subscription\":{"
            configJson `shouldSatisfy` Text.isInfixOf "\"renderedDependencyWatermark\":"
            configJson `shouldSatisfy` Text.isInfixOf "\"scope\":{"
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"resyncFragments\"")
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"mountState\"")
            configJson `shouldSatisfy` (not . Text.isInfixOf "\"loadPolicy\"")

        it "plans affected semantic fragment keys from generated dependencies" do
            let venueId = fromWords 1 0 0 0
            let scope = TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2)) 1
            let subscription = liveTestSubscription scope [TimesheetsLive.timesheetDaySectionLiveFragment (addDays 4 (testAnchorForOffset 2))]
            let targets = planSurfaceInvalidationsWithoutContext (Set.fromList [timesheetDayResource venueId (addDays 4 (testAnchorForOffset 2))]) [subscription]

            map targetFragments targets
                `shouldBe` [[TimesheetsLive.timesheetDaySectionLiveFragment (addDays 4 (testAnchorForOffset 2))]]

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

        it "keeps Admin Xero reconnect/resync descriptors local to the authorized mount" do
            let venueId = fromWords 3 0 0 0
            let scope = AdminSurface.AdminVenueScopeValue venueId Nothing
            let mountedFragments = (AdminSurface.adminXeroSurfaceImpl scope).surfaceImplMountConfig.mountFragments
            let waitMount = AdminSurface.adminXeroTimesheetPreparationWaitSurfaceImpl scope
            let waitFragments = waitMount.surfaceImplMountConfig.mountFragments

            AdminSurface.adminXeroFragmentKeys mountedFragments
                `shouldBe` [AdminLive.adminXeroShellLiveFragment, AdminLive.adminXeroReferenceSyncLiveFragment]
            map (.mountedFragmentTargetId) mountedFragments
                `shouldBe` ["admin-xero-fragment", "admin-xero-reference-sync-fragment"]
            map (.mountedFragmentUrl) mountedFragments
                `shouldBe` [pathTo ShowadminXeroShellLiveFragmentAction, pathTo ShowadminXeroReferenceSyncLiveFragmentAction]
            (AdminSurface.adminXeroSurfaceImpl scope).surfaceImplMountConfig.mountSubscription `shouldSatisfy` isJust
            AdminSurface.adminXeroFragmentKeys waitFragments
                `shouldBe` [AdminLive.adminXeroTimesheetPreparationWaitLiveFragment]
            map (.mountedFragmentTargetId) waitFragments
                `shouldBe` ["admin-xero-timesheet-preparation-wait-fragment"]
            map (.mountedFragmentUrl) waitFragments
                `shouldBe` [pathTo ShowadminXeroTimesheetPreparationWaitLiveFragmentAction]
            waitMount.surfaceImplMountConfig.mountSubscription `shouldSatisfy` isJust

        it "maps Xero connection and reference-sync state changes to separate fragments" do
            let venueId = fromWords 3 0 0 0
            let scope = AdminLive.adminXeroLiveScope venueId
            let otherVenueId = fromWords 4 0 0 0
            let otherScope = AdminLive.adminXeroLiveScope otherVenueId
            let fragmentKeys = AdminSurface.adminXeroFragmentKeys [AdminSurface.adminXeroShellFragment, AdminSurface.adminXeroReferenceSyncFragment, AdminSurface.adminXeroTimesheetPreparationWaitFragment]
            let subscriptions = [liveTestSubscription scope fragmentKeys, liveTestSubscription otherScope fragmentKeys]
            let targetsFor resource = planSurfaceInvalidationsWithoutContext (Set.fromList [resource venueId]) subscriptions
            let plannedFor resource = map (.targetFragments) (targetsFor resource)

            plannedFor xeroConnectionResource `shouldBe` [[AdminLive.adminXeroShellLiveFragment]]
            plannedFor xeroReferenceSyncStateResource
                `shouldBe` [[AdminLive.adminXeroReferenceSyncLiveFragment, AdminLive.adminXeroTimesheetPreparationWaitLiveFragment]]
            map (.targetScope) (targetsFor xeroReferenceSyncStateResource) `shouldBe` [scope]
            plannedFor adminShiftTypesResource `shouldBe` []
            plannedFor billingResource `shouldBe` []
            plannedFor timesheetWeekBoundaryConfigResource `shouldBe` []

        it "declares exact roster projection fragment targets for mounted refetches" do
            let venueId = fromWords 7 0 0 0
            let rosterGroupId = Id (fromWords 8 0 0 0) :: Id RosterGroup
            let rosterDayId = Id (fromWords 9 0 0 0) :: Id RosterDay
            let scope = RosterWeekScopeValue venueId rosterGroupId 3 (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 2)], rosterMountedTemplateUserId = Nothing }
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

        it "selects the private template library fragment for library and owner-draft changes" do
            let venueId = fromWords 21 0 0 0
            let rosterGroupUuid = fromWords 22 0 0 0
            let userUuid = fromWords 23 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let userId = Id userUuid :: Id User
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 3 (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [], rosterMountedTemplateUserId = Just userId }
            let candidates = rosterCandidateMountedFragments scopeValue plan

            passiveFragmentKeys (Set.singleton (rosterTemplateLibraryResource rosterGroupUuid)) (rosterSurfaceScope scopeValue) candidates
                `shouldBe` [RosterLive.rosterTemplateLibraryLiveFragment userUuid]
            passiveFragmentKeys (Set.singleton (rosterTemplateDraftResource userUuid)) (rosterSurfaceScope scopeValue) candidates
                `shouldBe` [RosterLive.rosterTemplateLibraryLiveFragment userUuid]

        it "normalizes roster wrapper containment without replacing the grid scroll owner" do
            let venueId = fromWords 7 0 0 0
            let rosterGroupUuid = fromWords 8 0 0 0
            let rosterDayUuid = fromWords 9 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let rosterDayId = Id rosterDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 3 (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3)) 1 Nothing
            let scope = rosterSurfaceScope scopeValue
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 2)], rosterMountedTemplateUserId = Nothing }
            let resources = Set.fromList
                    [ rosterWeekResource rosterGroupUuid (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3))
                    , rosterDayResource rosterDayUuid
                    ]

            passiveFragmentKeys resources scope (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterGridToolbarLiveFragment
                    , RosterLive.rosterDayColumnsLiveFragment
                    , RosterLive.rosterDayRailLiveFragment
                    , RosterLive.rosterWageRailLiveFragment
                    , RosterLive.rosterStaffPanelLiveFragment
                    , RosterLive.rosterDaySectionLiveFragment rosterDayUuid
                    ]

        it "selects the slots scroll owner only for slots-structure changes" do
            let venueId = fromWords 10 0 0 0
            let rosterGroupUuid = fromWords 11 0 0 0
            let rosterDayUuid = fromWords 12 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let rosterDayId = Id rosterDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 4 (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 0)], rosterMountedTemplateUserId = Nothing }
            let resources = Set.fromList
                    [ rosterWeekResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    , rosterSlotsStructureResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    ]

            passiveFragmentKeys resources (rosterSurfaceScope scopeValue) (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterGridToolbarLiveFragment
                    , RosterLive.rosterDayColumnsLiveFragment
                    , RosterLive.rosterDayRailLiveFragment
                    , RosterLive.rosterWageRailLiveFragment
                    , RosterLive.rosterSlotsGridLiveFragment
                    , RosterLive.rosterStaffPanelLiveFragment
                    ]

        it "selects the slots scroll owner for broad slots-content changes" do
            let venueId = fromWords 13 0 0 0
            let rosterGroupUuid = fromWords 14 0 0 0
            let rosterDayUuid = fromWords 15 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let rosterDayId = Id rosterDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 4 (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 0)], rosterMountedTemplateUserId = Nothing }
            let resources = Set.fromList
                    [ rosterWeekResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    , rosterSlotsContentResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    ]

            passiveFragmentKeys resources (rosterSurfaceScope scopeValue) (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterGridToolbarLiveFragment
                    , RosterLive.rosterDayColumnsLiveFragment
                    , RosterLive.rosterDayRailLiveFragment
                    , RosterLive.rosterWageRailLiveFragment
                    , RosterLive.rosterSlotsGridLiveFragment
                    , RosterLive.rosterStaffPanelLiveFragment
                    ]

        it "selects structural roster wrappers only for structural week changes" do
            let venueId = fromWords 11 0 0 0
            let rosterGroupUuid = fromWords 12 0 0 0
            let rosterDayUuid = fromWords 13 0 0 0
            let rosterGroupId = Id rosterGroupUuid :: Id RosterGroup
            let rosterDayId = Id rosterDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 4 (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 0)], rosterMountedTemplateUserId = Nothing }
            let resources = Set.fromList
                    [ rosterWeekResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    , rosterWeekStructureResource rosterGroupUuid (testAnchorForOffset 4) (addDays 7 (testAnchorForOffset 4))
                    ]

            passiveFragmentKeys resources (rosterSurfaceScope scopeValue) (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterContentLiveFragment
                    , RosterLive.rosterStaffPanelLiveFragment
                    ]

        it "keeps a parameterized child when the selected ancestor is a different instance" do
            let venueId = fromWords 17 0 0 0
            let rosterGroupId = Id (fromWords 18 0 0 0) :: Id RosterGroup
            let ancestorDayUuid = fromWords 19 0 0 0
            let childDayUuid = fromWords 20 0 0 0
            let ancestorDayId = Id ancestorDayUuid :: Id RosterDay
            let childDayId = Id childDayUuid :: Id RosterDay
            let scopeValue = RosterWeekScopeValue venueId rosterGroupId 3 (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3)) 1 Nothing
            let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [ancestorDayId], rosterMountedRows = [(childDayId, 2)], rosterMountedTemplateUserId = Nothing }

            passiveFragmentKeys
                (Set.fromList [rosterDayResource ancestorDayUuid, rosterDayResource childDayUuid])
                (rosterSurfaceScope scopeValue)
                (rosterCandidateMountedFragments scopeValue plan)
                `shouldBe`
                    [ RosterLive.rosterDaySectionLiveFragment ancestorDayUuid
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
            let checkoutState = BillingCheckoutReturnState False Nothing Nothing
            let fragments = planMountedFragments (Set.fromList [billingResource venueId]) (billingSurfaceScope scopeValue) (billingCandidateMountedFragments checkoutState)

            map (.mountedFragmentTargetId) fragments `shouldBe` ["billing-status-fragment"]

        it "selects profile fragments through generated staff-backed dependencies" do
            let venueId = fromWords 4 0 0 0
            let staffId = fromWords 5 0 0 0
            let scopeValue = ProfileScopeValue venueId staffId
            let candidates = profileCandidateMountedFragments scopeValue
            let affectedByProfile = planMountedFragments (Set.fromList [staffProfileResource staffId]) (profileSurfaceScope scopeValue) candidates
            let affectedStaffBlackoutFragments = planMountedFragments (Set.fromList [unavailabilityBlackoutsResource venueId]) (staffSurfaceScope scopeValue) (staffCandidateMountedFragments scopeValue)
            let leaveResources = Set.fromList [staffLeaveRequestsResource staffId]
            let blackoutResources = Set.fromList [unavailabilityBlackoutsResource venueId]
            let affectedProfileFragments = planMountedFragments leaveResources (profileSurfaceScope scopeValue) candidates
            let selfServiceScope = SelfServiceLeaveScopeValue venueId staffId
            let selfServiceMount = (selfServiceLeaveSurfaceImpl "profile" True selfServiceScope).surfaceImplMountConfig
            let affectedSelfServiceFragments = planMountedFragments leaveResources (selfServiceLeaveSurfaceScope selfServiceScope) selfServiceMount.mountFragments
            let affectedSelfServiceBlackoutFragments = planMountedFragments blackoutResources (selfServiceLeaveSurfaceScope selfServiceScope) selfServiceMount.mountFragments

            map (.mountedFragmentTargetId) affectedByProfile `shouldBe` ["profile-details"]
            map (.mountedFragmentTargetId) affectedStaffBlackoutFragments `shouldBe` ["staff-visible-unavailability-blackouts"]
            affectedProfileFragments `shouldBe` []
            map (.mountedFragmentTargetId) affectedSelfServiceFragments
                `shouldBe` ["self-service-leave-history-fragment"]
            map (.mountedFragmentTargetId) affectedSelfServiceBlackoutFragments
                `shouldBe` ["visible-unavailability-blackouts-fragment"]

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
        , subscriptionRenderedDependencyWatermark = 0
        }
