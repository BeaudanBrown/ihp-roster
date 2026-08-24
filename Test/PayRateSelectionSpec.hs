module Test.PayRateSelectionSpec where

import Application.Helper.NominalText
import Application.PayRateSelection
import Data.UUID (nil)
import Generated.Types
import IHP.HSX.QQ ()
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = do
    describe "PayRateSelection nominal wire domains" do
        it "keeps staff wire values unchanged" do
            renderNominalText StaffPayRateRosterOnly `shouldBe` ""
            renderNominalText StaffPayRateLegacyUnresolved `shouldBe` "legacy-unresolved"
            renderNominalText (StaffPayRateAward (Id nil :: Id AwardLevel)) `shouldBe` "award:00000000-0000-0000-0000-000000000000"
            renderNominalText (StaffPayRateXero (Id nil :: Id XeroImportedPayItem)) `shouldBe` "xero:00000000-0000-0000-0000-000000000000"
        it "keeps shift-type wire values unchanged" do
            renderNominalText ShiftTypePayRateDefault `shouldBe` ""
            renderNominalText ShiftTypePayRateRosterOnly `shouldBe` "roster-only"
        it "round-trips each context without interchange" do
            parseNominalText (renderNominalText (StaffPayRateAward (Id nil))) `shouldBe` Right (StaffPayRateAward (Id nil))
            parseNominalText (renderNominalText (ShiftTypePayRateXero (Id nil))) `shouldBe` Right (ShiftTypePayRateXero (Id nil))
