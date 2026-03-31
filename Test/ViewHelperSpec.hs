module Test.ViewHelperSpec where

import Application.Helper.View
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "View helpers" do
    describe "storageTimeToDisplayLabel" do
        it "formats stored HH:MM values into human-readable labels" do
            storageTimeToDisplayLabel "06:00" `shouldBe` "6:00 AM"
            storageTimeToDisplayLabel "13:15" `shouldBe` "1:15 PM"
            storageTimeToDisplayLabel "23:45" `shouldBe` "11:45 PM"

        it "passes through invalid values unchanged" do
            storageTimeToDisplayLabel "not-a-time" `shouldBe` "not-a-time"
            storageTimeToDisplayLabel "" `shouldBe` ""
