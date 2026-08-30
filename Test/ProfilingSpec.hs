module Test.ProfilingSpec where

import Application.Helper.Profiling (profilingMiddleware)
import Control.Exception (bracket)
import qualified Data.ByteString.Char8 as ByteString
import IHP.Prelude
import Network.HTTP.Types.Header (HeaderName, ResponseHeaders)
import Network.HTTP.Types.Status
import qualified Network.Wai as Wai
import Network.Wai.Test
import qualified System.Environment as Environment
import Test.Hspec

tests :: Spec
tests =
    describe "Profiling" do
        it "does not emit profiling headers by default" do
            withEnv "IHP_ROSTER_PROFILING" Nothing do
                response <- runProfiledRequest (Wai.responseLBS status200 [("Content-Type", "text/plain")] "ok")

                simpleHeaders response `shouldNotSatisfy` hasHeader "Server-Timing"
                simpleHeaders response `shouldNotSatisfy` hasHeader "X-Request-Id"

        it "emits Server-Timing and request ids from middleware when enabled" do
            withEnv "IHP_ROSTER_PROFILING" (Just "1") do
                response <- runProfiledRequest (Wai.responseLBS status200 [("Content-Type", "text/plain")] "ok")

                lookup "X-Request-Id" (simpleHeaders response) `shouldSatisfy` maybe False (not . null)
                lookup "Server-Timing" (simpleHeaders response) `shouldSatisfy` maybe False (ByteString.isInfixOf "app_total;dur=")
                simpleHeaders response `shouldNotSatisfy` hasHeader "X-Profile-Counters"
                simpleHeaders response `shouldNotSatisfy` hasHeader "X-Profile-Response-Bytes"

        it "emits profiling headers for non-HTML response shapes" do
            withEnv "IHP_ROSTER_PROFILING" (Just "1") do
                redirectResponse <- runProfiledRequest (Wai.responseLBS status302 [("Location", "/RosterWeeks")] "")
                jsonResponse <- runProfiledRequest (Wai.responseLBS status200 [("Content-Type", "application/json")] "{}")

                lookup "Server-Timing" (simpleHeaders redirectResponse) `shouldSatisfy` maybe False (ByteString.isInfixOf "app_total;dur=")
                lookup "Server-Timing" (simpleHeaders jsonResponse) `shouldSatisfy` maybe False (ByteString.isInfixOf "app_total;dur=")

runProfiledRequest :: Wai.Response -> IO SResponse
runProfiledRequest response =
    runSession (request defaultRequest) app
    where
        app =
            profilingMiddleware \_ respond ->
                respond response

hasHeader :: HeaderName -> ResponseHeaders -> Bool
hasHeader name =
    any ((== name) . fst)

withEnv :: String -> Maybe String -> IO a -> IO a
withEnv name value action =
    bracket setup restore (const action)
    where
        setup = do
            previous <- Environment.lookupEnv name
            apply value
            pure previous

        restore previous =
            apply previous

        apply Nothing      = Environment.unsetEnv name
        apply (Just value) = Environment.setEnv name value
