module Test.NotFoundRecoverySpec where

import Application.Helper.BrowserFailure (browserFailurePageMiddleware,
                                          isBrowserPageRequest)
import Data.Attoparsec.ByteString (parseOnly)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import IHP.Controller.NotFound (buildNotFoundResponse)
import IHP.Prelude
import IHP.RouterSupport (FrontController (router))
import Network.HTTP.Types (methodGet, methodPost)
import Network.HTTP.Types.Header (hAccept, hCacheControl, hContentEncoding,
                                  hContentLength, hContentType)
import Network.HTTP.Types.Status (status400, status403, status404, status422,
                                  status500, status502)
import qualified Network.Wai as Wai
import Network.Wai.Test
import Test.Hspec
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

        it "replaces an unexpected browser-page failure with a self-contained Bepis recovery page" do
            let browserRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "document")]
                    }
            response <- runSession (request browserRequest) (browserFailurePageMiddleware (failureApp status500 "IHP failure"))

            simpleStatus response `shouldBe` status500
            simpleBody response `shouldSatisfy` contains "Something went wrong"
            simpleBody response `shouldSatisfy` contains "Return to Bepis"
            simpleBody response `shouldNotSatisfy` contains "IHP failure"

        it "uses status-specific recovery copy without changing failure statuses" do
            let browserRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "document")]
                    }
            forM_
                [ (status400, "This link or request is invalid")
                , (status403, "have access to this page")
                , (status404, "This page is no longer available")
                , (status502, "Something went wrong")
                ]
                \(status, expectedCopy) -> do
                    response <- runSession (request browserRequest) (browserFailurePageMiddleware (failureApp status "original response"))
                    simpleStatus response `shouldBe` status
                    simpleBody response `shouldSatisfy` contains expectedCopy

        it "preserves non-page and controlled validation responses" do
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
            let cssRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "style")]
                    }
            let sourceMapRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "*/*")]
                    }

            forM_
                [ (jsonRequest, status500)
                , (postRequest, status500)
                , (htmxRequest, status500)
                , (cssRequest, status404)
                , (sourceMapRequest, status404)
                , (browserRequest, status422)
                ]
                \(requestUnderTest, status) -> do
                    response <- runSession (request requestUnderTest) (browserFailurePageMiddleware (failureApp status "original response"))
                    simpleStatus response `shouldBe` status
                    simpleBody response `shouldBe` "original response"

            isBrowserPageRequest browserRequest `shouldBe` True
            isBrowserPageRequest jsonRequest `shouldBe` False
            isBrowserPageRequest postRequest `shouldBe` False
            isBrowserPageRequest htmxRequest `shouldBe` False
            isBrowserPageRequest cssRequest `shouldBe` False
            isBrowserPageRequest sourceMapRequest `shouldBe` False

        it "removes stale entity headers while retaining safe response context" do
            let browserRequest = defaultRequest
                    { Wai.requestMethod = methodGet
                    , Wai.requestHeaders = [(hAccept, "text/html"), ("Sec-Fetch-Dest", "document")]
                    }
            let originalHeaders =
                    [ (hContentType, "text/plain")
                    , (hContentLength, "4")
                    , (hContentEncoding, "gzip")
                    , (hCacheControl, "public")
                    , ("Set-Cookie", "session=retained")
                    , ("X-Request-Id", "request-123")
                    ]
            let originalApp _ respond = respond (Wai.responseLBS status500 originalHeaders "fail")
            response <- runSession (request browserRequest) (browserFailurePageMiddleware originalApp)

            lookup hContentType (simpleHeaders response) `shouldBe` Just "text/html; charset=utf-8"
            lookup hContentLength (simpleHeaders response) `shouldBe` Nothing
            lookup hContentEncoding (simpleHeaders response) `shouldBe` Nothing
            lookup hCacheControl (simpleHeaders response) `shouldBe` Just "no-store"
            lookup "Set-Cookie" (simpleHeaders response) `shouldBe` Just "session=retained"
            lookup "X-Request-Id" (simpleHeaders response) `shouldBe` Just "request-123"
  where
    app _ respond = buildNotFoundResponse >>= respond
    failureApp status body _ respond = respond (Wai.responseLBS status [(hContentType, "text/html")] body)
    contains needle body = needle `ByteString.isInfixOf` LazyByteString.toStrict body
