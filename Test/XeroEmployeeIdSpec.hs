module Test.XeroEmployeeIdSpec where

import Application.Helper.NominalText
import Application.Xero.EmployeeId
import Data.Either (isLeft)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "XeroEmployeeId" do
        it "round-trips provider-owned identifiers unchanged" do
            let parsed = parseXeroEmployeeId "employee-a"
            fmap xeroEmployeeIdText parsed `shouldBe` Right "employee-a"
            (parsed >>= (parseNominalText . renderNominalText)) `shouldBe` parsed
            fmap xeroEmployeeIdText (parseXeroEmployeeId " provider-owned ") `shouldBe` Right " provider-owned "
        it "keeps explicit mapping selection sentinels unchanged" do
            renderNominalText XeroEmployeeUnmapped `shouldBe` "unmapped"
            parseNominalText "unmapped" `shouldBe` Right XeroEmployeeUnmapped
            renderNominalText XeroEmployeeNotApplicable `shouldBe` "not_applicable"
            parseNominalText "not_applicable" `shouldBe` Right XeroEmployeeNotApplicable
        it "rejects empty and reserved raw employee identifiers" do
            parseXeroEmployeeId "" `shouldSatisfy` isLeft
            parseXeroEmployeeId "not_applicable" `shouldSatisfy` isLeft
            parseXeroEmployeeId "unmapped" `shouldSatisfy` isLeft
