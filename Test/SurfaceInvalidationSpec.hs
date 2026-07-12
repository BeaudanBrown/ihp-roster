module Test.SurfaceInvalidationSpec where

import Application.Bepis.Fact (BepisLiveFact (..), BepisLiveMechanism (..))
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.SurfaceInvalidation

tests :: Spec
tests = do
    describe "Surface resource invalidation planning" do
        it "expands roster-affecting venue config resources to active roster week resources" do
            let venueId = fromWords 1 0 0 0
            let otherVenueId = fromWords 2 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let otherRosterGroupId = fromWords 5 0 0 0
            let activeScopes = [(venueId, rosterGroupId, 0), (venueId, rosterGroupId, 1), (otherVenueId, otherRosterGroupId, 0)]

            expandSurfaceResourcesWithoutContext activeScopes (Set.singleton (rosterEndTimesConfigResource venueId))
                `shouldBe` Set.fromList
                    [ rosterEndTimesConfigResource venueId
                    , rosterWeekResource rosterGroupId 0
                    , rosterWeekResource rosterGroupId 1
                    ]
            expandSurfaceResourcesWithoutContext activeScopes (Set.singleton (rosterWeekBoundaryConfigResource venueId))
                `shouldBe` Set.fromList
                    [ rosterWeekBoundaryConfigResource venueId
                    , rosterWeekResource rosterGroupId 0
                    , rosterWeekResource rosterGroupId 1
                    ]

        it "leaves direct resources for dependency-derived live surface matching" do
            let venueId = fromWords 1 0 0 0
            let staffId = fromWords 3 0 0 0
            let rosterGroupId = fromWords 4 0 0 0
            let directResources =
                    Set.fromList
                        [ staffLeaveRequestsResource staffId
                        , rosterWeekResource rosterGroupId 0
                        , timesheetWeekResource venueId 0
                        , timesheetDayResource venueId 0 2
                        , staffRsaDocumentsResource staffId
                        , adminVenueSettingsResource venueId
                        , rosterEndTimesConfigResource venueId
                        , rosterWeekBoundaryConfigResource venueId
                        , timesheetWeekBoundaryConfigResource venueId
                        , adminInvitesResource venueId
                        , adminRosterGroupsResource venueId
                        , adminShiftTypesResource venueId
                        , adminExportsResource venueId
                        , billingResource venueId
                        , supportAwardRatesResource
                        , supportPublicHolidaysResource
                        , xeroConnectionResource venueId
                        , xeroMappingsResource venueId
                        , xeroPayItemsResource venueId
                        , xeroTimesheetsResource venueId
                        ]

            expandSurfaceResourcesWithoutContext [] directResources
                `shouldBe` directResources

        it "renders live invalidation profile counts for timing diagnostics" do
            let venueId = fromWords 1 0 0 0
            let scope = billingLiveScope venueId
            let target = SurfaceInvalidationTarget scope [billingStatusLiveFragment]
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
                        (Set.fromList [billingResource venueId])
                        [scope]
                        (Set.fromList [billingResource venueId])
                        [target]
                        [broadcastResult]
                        LiveInvalidationStageDurations
                            { observeDurationMs = 0.1
                            , activeDurationMs = 0.2
                            , expandDurationMs = 0.3
                            , planDurationMs = 0.5
                            , broadcastDurationMs = 0.6
                            }

            renderLiveInvalidationProfile profile
                `shouldBe` "label=billing.update touched=1 active_scopes=1 expanded=1 targets=1 target_fragments=1 broadcasts=1 subscribers=7 total_ms=12.3 observe_ms=0.1 active_ms=0.2 expand_ms=0.3 plan_ms=0.5 broadcast_ms=0.6"
            let liveFact = bepisLiveFactFromProfile BepisWebSocketFragmentRefetch profile
            liveFact.liveFactTargetCount `shouldBe` 1
            liveFact.liveFactTargetFragmentCount `shouldBe` 1
