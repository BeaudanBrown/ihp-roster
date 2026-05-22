module Test.LiveResourceInvalidationSpec where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateBroadcastResult (..),
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment (..))
import IHP.Prelude
import qualified Data.Set as Set
import Data.UUID (fromWords)
import Test.Hspec
import Web.LiveResourceInvalidation
import Web.LiveSurfaceRegistry (LiveSurfaceInvalidationTarget (..))

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

        it "renders live invalidation profile counts for timing diagnostics" do
            let venueId = fromWords 1 0 0 0
            let scope = BillingScope venueId
            let fragment =
                    LiveUpdateWireFragment
                        { fragmentKey = BillingStatusFragment
                        , targetId = "billing-status"
                        , url = "/ShowBillingStatusFragment"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
            let target = LiveSurfaceInvalidationTarget scope [fragment]
            let broadcastResult =
                    LiveUpdateBroadcastResult
                        { broadcastVersion = 3
                        , broadcastSubscriberCount = 7
                        , broadcastFragmentCount = 1
                        , broadcastRefetchFragmentCount = 1
                        , broadcastCoalescedFragmentCount = 0
                        , broadcastDroppedSubscriptions = 0
                        }
            let profile =
                    liveInvalidationProfile
                        "billing.update"
                        12.34
                        (Set.fromList [BillingResource venueId])
                        [scope]
                        (Set.fromList [BillingResource venueId])
                        [scope]
                        [scope]
                        [target]
                        [broadcastResult]
                        LiveInvalidationStageDurations
                            { observeDurationMs = 0.1
                            , activeDurationMs = 0.2
                            , expandDurationMs = 0.3
                            , candidateDurationMs = 0.4
                            , planDurationMs = 0.5
                            , broadcastDurationMs = 0.6
                            }

            renderLiveInvalidationProfile profile
                `shouldBe` "label=billing.update touched=1 active_scopes=1 expanded=1 candidate_scopes=1 planning_scopes=1 targets=1 target_fragments=1 broadcasts=1 subscribers=7 total_ms=12.3 observe_ms=0.1 active_ms=0.2 expand_ms=0.3 candidate_ms=0.4 plan_ms=0.5 broadcast_ms=0.6"
