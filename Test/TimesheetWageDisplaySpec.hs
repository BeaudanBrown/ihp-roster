module Test.TimesheetWageDisplaySpec where

import Generated.Types
import IHP.Prelude
import Test.Hspec
import Web.Timesheets.WageEstimates

tests :: Spec
tests = describe "Timesheet wage display authority" do
    it "keeps Worker, Supervisor, and Manager estimates personal in either Manager mode" do
        forM_ [Worker, Supervisor, Manager] \role ->
            forM_ [False, True] \managerMode ->
                timesheetPayAudienceFor False (Just role) managerMode True
                    `shouldBe` Just PersonalPayAudience

    it "grants venue estimates only to Admin and Owner while Manager mode is on" do
        forM_ [VenueAdmin, VenueOwner] \role -> do
            timesheetPayAudienceFor False (Just role) True True
                `shouldBe` Just ManagementPayAudience
            timesheetPayAudienceFor False (Just role) False True
                `shouldBe` Just PersonalPayAudience

    it "uses support authority only outside impersonation and requires linked Staff otherwise" do
        timesheetPayAudienceFor True Nothing True False
            `shouldBe` Just ManagementPayAudience
        timesheetPayAudienceFor False (Just Worker) False True
            `shouldBe` Just PersonalPayAudience
        timesheetPayAudienceFor False (Just Worker) False False
            `shouldBe` Nothing
