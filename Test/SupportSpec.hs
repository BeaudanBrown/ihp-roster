module Test.SupportSpec where

import Config
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "Test.Support" do
        it "restores the founder bootstrap login after a clean DB reset" $ withContext do
            withCleanDb do
                founder <- query @User
                    |> filterWhere (#email, bootstrapFounderEmail)
                    |> fetchOne
                membership <- query @VenueMembership
                    |> filterWhere (#userId, unpackId founder.id)
                    |> fetchOne
                staff <- query @Staff
                    |> filterWhere (#userId, Just (unpackId founder.id))
                    |> fetchOne
                venueCount <- query @Venue |> fetchCount
                venueConfigCount <- query @VenueConfig |> fetchCount

                founder.email `shouldBe` bootstrapFounderEmail
                venueCount `shouldBe` 1
                venueConfigCount `shouldBe` 1
                inputValue membership.venueRole `shouldBe` "venue_owner"
                staff.firstName `shouldBe` "Beau"
