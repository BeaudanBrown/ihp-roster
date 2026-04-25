module Test.Controller.StaticSpec where

import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status

import Config
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

import Generated.Types
import IHP.ControllerPrelude
import Network.Wai
import Web.Controller.Static ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "StaticController" do
        it "renders the welcome page for unauthenticated users" $ withContext do
            response <- callAction WelcomeAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Bepis"
            response `responseBodyShouldContain` "Sign In"
            response `responseBodyShouldNotContain` "Request Access"
            response `responseBodyShouldContain` "js-passkey-first-login"
            response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyAuthentication\""
            response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyAuthentication\""
            response `responseBodyShouldContain` "data-fallback-url=\"/NewSession\""

        it "redirects authenticated users to the roster week view" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "welcome-auth@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUser user do
                    callAction WelcomeAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
