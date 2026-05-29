module Test.LiveSurfaceRegistrySpec where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..), LiveUpdateScope (..), LiveUpdateWireFragment (..))
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.LiveSurfaceRegistry

tests :: Spec
tests = do
    describe "Live surface registry dependency planning" do
        it "plans context-free billing, invites, and support targets from dependencies" do
            let venueId = fromWords 1 0 0 0
            let scopes =
                    [ BillingScope venueId
                    , AdminVenueConfigScope venueId
                    , AdminInvitesScope venueId
                    , SupportPlatformScope
                    ]
            let resources =
                    Set.fromList
                        [ BillingResource venueId
                        , AdminVenueSettingsResource venueId
                        , AdminInvitesResource venueId
                        , SupportAwardRatesResource
                        ]

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext resources scopes)
                `shouldBe` Set.fromList
                    [ (BillingScope venueId, [BillingStatusFragment])
                    , (AdminVenueConfigScope venueId, [AdminVenueConfigFragment])
                    , (AdminInvitesScope venueId, [AdminInvitesFragment])
                    , (SupportPlatformScope, [SupportAwardRatesSectionFragment])
                    ]

        it "plans Xero fragments from fragment-specific dependencies" do
            let venueId = fromWords 2 0 0 0
            let scopes = [AdminXeroScope venueId]

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.singleton (XeroPayItemsResource venueId)) scopes)
                `shouldBe` Set.singleton (AdminXeroScope venueId, [AdminXeroFragment])

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.singleton (XeroTimesheetsResource venueId)) scopes)
                `shouldBe` Set.singleton (AdminXeroScope venueId, [AdminXeroFragment, AdminXeroTimesheetsFragment])

        it "plans timesheet day fragments from week, day, and venue-config dependencies" do
            let venueId = fromWords 3 0 0 0
            let scope = TimesheetWeekScope venueId 4

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.singleton (TimesheetDayResource venueId 4 2)) [scope])
                `shouldBe` Set.singleton (scope, [TimesheetDaySectionFragment 2])

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.singleton (TimesheetWeekResource venueId 4)) [scope])
                `shouldBe` Set.singleton (scope, [TimesheetToolbarFragment, TimesheetDayColumnsFragment])

            targetSummary (planRegisteredLiveSurfaceInvalidationsWithoutContext (Set.singleton (TimesheetWeekBoundaryConfigResource venueId)) [scope])
                `shouldBe` Set.singleton (scope, [TimesheetToolbarFragment, TimesheetDayColumnsFragment])

        it "ignores resources that do not match the subscribed scope" do
            let venueId = fromWords 4 0 0 0
            let otherVenueId = fromWords 5 0 0 0

            planRegisteredLiveSurfaceInvalidationsWithoutContext
                (Set.singleton (BillingResource otherVenueId))
                [BillingScope venueId]
                `shouldBe` []

targetSummary :: [LiveSurfaceInvalidationTarget] -> Set.Set (LiveUpdateScope, [LiveFragmentKey])
targetSummary targets =
    Set.fromList
        [ (target.targetScope, map (.fragmentKey) target.targetFragments)
        | target <- targets
        ]
