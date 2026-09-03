module Test.NotFoundRecoverySpec where

import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import Data.Attoparsec.ByteString (parseOnly)
import IHP.Controller.NotFound (buildNotFoundResponse)
import IHP.Prelude
import IHP.RouterSupport (FrontController (router))
import Network.HTTP.Types (methodGet, methodPost)
import Network.HTTP.Types.Header (hAccept)
import Network.HTTP.Types.Status (status404)
import qualified Network.Wai as Wai
import Network.Wai.Test
import Test.Hspec
import Web.Controller.Static (isStaleBrowserPageRequest)
import Web.FrontController ()
import Web.Types (WebApplication (..))

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

        it "routes an unknown stale browser path into application recovery" do
            let ?application = WebApplication
            let ?request = defaultRequest
                    { Wai.rawPathInfo = "/thing"
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "document")]
                    }
            let ?respond = error "route parser must not execute the response"
            let parsedRoute = parseOnly (router @WebApplication []) "/thing" :: Either String Wai.Application

            case parsedRoute of
                Right _ -> pure ()
                Left parseFailure -> expectationFailure ("Expected /thing to reach recovery route, but routing failed: " <> parseFailure)

        it "leaves unknown static asset paths to IHP's static server" do
            let ?application = WebApplication
            let ?request = defaultRequest
                    { Wai.rawPathInfo = "/css/missing.css"
                    , Wai.requestHeaders = [(hAccept, "text/css,*/*")]
                    }
            let ?respond = error "route parser must not execute the response"
            let parsedRoute = parseOnly (router @WebApplication []) "/css/missing.css" :: Either String Wai.Application

            case parsedRoute of
                Left _ -> pure ()
                Right _ -> expectationFailure "Expected a static asset path to bypass application recovery"

        it "redirects browser page requests but preserves JSON and non-GET 404s" do
            let browserRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "document")]
                    }
            let jsonRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "application/json")]
                    }
            let postRequest = browserRequest { Wai.requestMethod = methodPost }
            let htmxRequest = browserRequest
                    { Wai.requestHeaders = ("HX-Request", "true") : Wai.requestHeaders browserRequest
                    }

            isStaleBrowserPageRequest browserRequest `shouldBe` True
            isStaleBrowserPageRequest jsonRequest `shouldBe` False
            isStaleBrowserPageRequest postRequest `shouldBe` False
            isStaleBrowserPageRequest htmxRequest `shouldBe` False
  where
    app _ respond = buildNotFoundResponse >>= respond
    contains needle body = needle `ByteString.isInfixOf` LazyByteString.toStrict body
