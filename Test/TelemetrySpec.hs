module Test.TelemetrySpec where

import Application.Helper.Telemetry (diagnosticHeaderValue)
import Application.Helper.Telemetry.Semantic
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString.Char8
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Telemetry" do
        it "accepts bounded diagnostic identifiers" do
            diagnosticHeaderValue "run-123_ABC.def:step/4" `shouldBe` Just "run-123_ABC.def:step/4"
            diagnosticHeaderValue (ByteString.Char8.replicate 96 'a') `shouldBe` Just (cs (replicate 96 'a' :: String))

        it "rejects oversized or free-form diagnostic headers" do
            diagnosticHeaderValue (ByteString.Char8.replicate 97 'a') `shouldBe` Nothing
            diagnosticHeaderValue "run with spaces" `shouldBe` Nothing
            diagnosticHeaderValue "line\nbreak" `shouldBe` Nothing

        it "rejects invalid UTF-8" do
            diagnosticHeaderValue (ByteString.pack [0xff, 0xfe]) `shouldBe` Nothing

        it "bounds worker attempts and exposes final retry state" do
            boundedAttempt 10 0 `shouldBe` 1
            boundedAttempt 10 99 `shouldBe` 10
            jobRetryState 10 9 `shouldBe` RetryPossible
            jobRetryState 10 10 `shouldBe` FinalAttempt
            jobRetryState 1 1 `shouldBe` FinalAttempt
            boundedRetryNumber (-10) `shouldBe` 0
            boundedRetryNumber 200 `shouldBe` 100
            nextBoundedRetryNumber (maxBound :: Int) `shouldBe` 100
            retryNumberAtLimit 99 `shouldBe` False
            retryNumberAtLimit 100 `shouldBe` True

        it "projects only bounded HTTP method and status classes" do
            telemetryHttpMethod "GET" `shouldBe` "GET"
            telemetryHttpMethod "TRACE" `shouldBe` "OTHER"
            telemetryHttpMethod (ByteString.pack [0xff]) `shouldBe` "OTHER"
            httpStatusClass 204 `shouldBe` "2xx"
            httpStatusClass 429 `shouldBe` "4xx"
            httpStatusClass 700 `shouldBe` "invalid"

        it "keeps semantic spans wired at every production boundary" do
            let boundaries =
                    [ ("Application/Async/Registry.hs", "withJobTelemetrySpan")
                    , ("Application/Billing/Stripe.hs", "withProviderTelemetrySpan")
                    , ("Application/EmailDelivery.hs", "withProviderTelemetrySpan")
                    , ("Application/FwcMapd/Client.hs", "withProviderTelemetrySpan")
                    , ("Application/Helper/Xero.hs", "withProviderTelemetrySpan")
                    , ("Application/Helper/Export/Service.hs", "withExportTelemetrySpan")
                    , ("Web/Controller/LiveUpdates.hs", "withLiveUpdateTelemetrySpan")
                    ]
            forM_ boundaries \(path, call) -> do
                source <- TextIO.readFile path
                source `shouldSatisfy` Text.isInfixOf call
