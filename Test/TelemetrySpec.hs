module Test.TelemetrySpec where

import Application.Helper.Telemetry (diagnosticHeaderValue)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString.Char8
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
