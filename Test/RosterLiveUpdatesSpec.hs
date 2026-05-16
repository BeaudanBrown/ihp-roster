module Test.RosterLiveUpdatesSpec where

import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import qualified Data.UUID as UUID
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.LiveUpdates (coalesceRosterWeekFragmentRefs)
import Web.RosterWeeks.Projection (buildRosterRowFragmentRef)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))

tests :: Spec
tests = beforeAll testContext do
    describe "RosterWeek LiveUpdates" do
        it "collapses hot roster row bursts to larger safe fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster live update coalescing"
                rosterGroup <- ensureVenueDefaultRosterGroup venue
                withControllerTestContext do
                    let rosterGroupId = get #id rosterGroup
                    let firstDayId = expectUuid "22222222-2222-2222-2222-222222222222"
                    let secondDayId = expectUuid "55555555-5555-5555-5555-555555555555"
                    let thirdDayId = expectUuid "66666666-6666-6666-6666-666666666666"
                    let fourthDayId = expectUuid "77777777-7777-7777-7777-777777777777"
                    let hotRowBurst =
                            [ buildRosterRowFragmentRef rosterGroupId 0 firstDayId rowIndex
                            | rowIndex <- [0, 1, 2]
                            ]
                    let multiDayBurst =
                            concat
                                [ [ buildRosterRowFragmentRef rosterGroupId 0 dayId rowIndex
                                  | rowIndex <- [0, 1, 2]
                                  ]
                                | dayId <- [firstDayId, secondDayId, thirdDayId, fourthDayId]
                                ]

                    coalesceRosterWeekFragmentRefs rosterGroupId 0 hotRowBurst
                        `shouldBe` [RosterProjectionDaySection firstDayId]
                    coalesceRosterWeekFragmentRefs rosterGroupId 0 multiDayBurst
                        `shouldBe` [RosterProjectionContent]

expectUuid :: Text -> UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
