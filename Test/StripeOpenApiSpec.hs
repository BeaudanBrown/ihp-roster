module Test.StripeOpenApiSpec where

import IHP.Prelude
import System.Exit (ExitCode (ExitSuccess))
import System.Process (readProcessWithExitCode)
import Test.Hspec

tests :: Spec
tests =
    describe "StripeOpenApi" do
        it "validates the reviewed Bepis contract slice and sanitized fixtures offline" do
            (exitCode, stdoutText, stderrText) <- readProcessWithExitCode "python3" ["scripts/check-stripe-openapi-contract"] ""

            exitCode `shouldBe` ExitSuccess
            stderrText `shouldBe` ""
            stdoutText `shouldContain` "2026-06-24.dahlia"
