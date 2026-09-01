module Test.BoundaryUtilitiesSpec where

import Application.Helper.OpaqueToken (hashOpaqueToken)
import Application.Helper.PasskeyRecoveryCodes (hashRecoveryCode)
import Test.Hspec

tests :: Spec
tests = do
    describe "boundary utility encodings" do
        it "retains lowercase SHA-256 opaque-token encoding" do
            hashOpaqueToken "abc"
                `shouldBe` "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

        it "retains lowercase SHA-256 normalized recovery-code encoding" do
            hashRecoveryCode "abcd-efgh-ijkl-mnop"
                `shouldBe` "e7e8b89c2721d290cc5f55425491ecd6831355e91063f20b39c22f9ec6a71f91"
