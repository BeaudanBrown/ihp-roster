module Test.RosterWageDisplaySpec where

import Generated.Types
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.WageEstimates

tests :: Spec
tests = describe "Roster expected pay authority" do
    it "keeps Worker, Supervisor, and Manager estimates personal in either Manager mode" do
        forM_ [Worker, Supervisor, Manager] \role ->
            forM_ [False, True] \managerMode ->
                rosterPayAudienceFor False (Just role) managerMode True
                    `shouldBe` Just PersonalRosterPayAudience

    it "uses venue scope for Admin and Owner only while Manager mode is on" do
        forM_ [VenueAdmin, VenueOwner] \role -> do
            rosterPayAudienceFor False (Just role) True True
                `shouldBe` Just ManagementRosterPayAudience
            rosterPayAudienceFor False (Just role) False True
                `shouldBe` Just PersonalRosterPayAudience

    it "retains unimpersonated support scope and rejects actors without membership authority" do
        rosterPayAudienceFor True Nothing True False
            `shouldBe` Just ManagementRosterPayAudience
        rosterPayAudienceFor False Nothing False True
            `shouldBe` Nothing
        rosterPayAudienceFor False (Just Manager) False False
            `shouldBe` Nothing

    it "uses audience-specific product copy" do
        rosterPayAudienceLabel PersonalRosterPayAudience `shouldBe` "Your expected pay"
        rosterPayAudienceLabel ManagementRosterPayAudience `shouldBe` "Expected gross wages"
