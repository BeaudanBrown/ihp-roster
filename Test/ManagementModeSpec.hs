module Test.ManagementModeSpec where

import Application.Helper.ControllerContext (ManagementModeContext (..))
import Application.Helper.ManagementMode (managementModeContextFor)
import Generated.Types (VenueRoleEnum (..))
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Manager mode policy" do
    it "defaults eligible linked managers on and follows their saved preference" do
        let enabled = managementModeContextFor False (Just Manager) True True
        enabled.managementModeEffective `shouldBe` True
        enabled.managementModeToggleVisible `shouldBe` True
        enabled.managementModeToggleEnabled `shouldBe` True

        let disabled = managementModeContextFor False (Just Manager) True False
        disabled.managementModeEffective `shouldBe` False
        disabled.managementModePreferenceEnabled `shouldBe` False

    it "keeps eligible users without active linked Staff in management scope without changing their preference" do
        let context = managementModeContextFor False (Just VenueAdmin) False False
        context.managementModeEffective `shouldBe` True
        context.managementModePreferenceEnabled `shouldBe` False
        context.managementModeToggleVisible `shouldBe` True
        context.managementModeToggleEnabled `shouldBe` False

    it "never grants management scope to worker or supervisor roles" do
        forM_ [Worker, Supervisor] \role -> do
            let context = managementModeContextFor False (Just role) False True
            context.managementModeEffective `shouldBe` False
            context.managementModeToggleVisible `shouldBe` False
            context.managementModeToggleEnabled `shouldBe` False

    it "forces only unimpersonated founder support into management scope" do
        let support = managementModeContextFor True Nothing False False
        support.managementModeEffective `shouldBe` True
        support.managementModeToggleVisible `shouldBe` False

        let impersonatedWorker = managementModeContextFor False (Just Worker) True True
        impersonatedWorker.managementModeEffective `shouldBe` False
        impersonatedWorker.managementModeToggleVisible `shouldBe` False
