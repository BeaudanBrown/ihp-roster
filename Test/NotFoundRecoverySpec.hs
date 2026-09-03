module Test.NotFoundRecoverySpec where

import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import IHP.Controller.NotFound (buildNotFoundResponse)
import IHP.Prelude
import Network.HTTP.Types.Status (status404)
import qualified Network.Wai as Wai
import Network.Wai.Test
import Test.Hspec

tests :: Spec
tests =
    describe "Not-found recovery" do
        it "keeps a 404 response while returning browser users to the application entry point" do
            response <- runSession (request defaultRequest) app

            simpleStatus response `shouldBe` status404
            simpleBody response `shouldSatisfy` contains "window.location.replace(\"/\")"
            simpleBody response `shouldSatisfy` contains "url=/"
            simpleBody response `shouldSatisfy` contains "Return to Bepis"
            simpleBody response `shouldNotSatisfy` contains "Action not found"
  where
    app _ respond = buildNotFoundResponse >>= respond
    contains needle body = needle `ByteString.isInfixOf` LazyByteString.toStrict body
