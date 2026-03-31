module Test.Controller.DashboardSpec where

import Application.Helper.LiveDemo
import Application.Helper.LiveUpdate
import Config
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Generated.Types
import IHP.Controller.RequestContext (RequestContext (..))
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Web.Controller.Dashboard ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll (mockContextNoDatabase WebApplication config) do
    before_ resetDashboardState do
        describe "DashboardController" do
            it "redirects unauthenticated users to the login page" $ withContext do
                response <- callAction DashboardAction
                response `responseStatusShouldBe` status302

            it "renders the live demo shell for authenticated users" $ withContext do
                user <- createTestUser
                response <- withUser user do
                    callAction DashboardAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "dashboard-live-shell"
                response `responseBodyShouldContain` "Live Update Demo"
                response `responseBodyShouldContain` "dashboard-live-demo-fragment"
                response `responseBodyShouldContain` "data-live-fragment-defer-until-blur"
                response `responseBodyShouldContain` "Open Runtime Dialog"

            it "returns the live demo fragment for HTMX refreshes" $ withContext do
                user <- createTestUser
                response <- withUser user do
                    callAction ShowDashboardLiveDemoContentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "dashboard-live-demo-fragment"
                response `responseBodyShouldContain` "Live count: 0"
                response `responseBodyShouldContain` "dashboard-live-demo-notes"

            it "returns the runtime demo dialog fragment for HTMX requests" $ withContext do
                user <- createTestUser
                response <- withUser user do
                    let currentRequest = ?context.request
                    let requestWithHtmx =
                            currentRequest
                                { requestHeaders = ("HX-Request", "true") : currentRequest.requestHeaders
                                }
                    let ?context = ?context { request = requestWithHtmx }
                    callAction ShowDashboardRuntimeDemoAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Runtime Rehydration Demo"
                response `responseBodyShouldContain` "dashboard-runtime-demo-date"
                response `responseBodyShouldContain` "dashboard-runtime-demo-time-field"

            it "increments the live demo and bumps the live update version" $ withContext do
                user <- createTestUser
                response <- withUser user do
                    callAction IncrementDashboardLiveDemoAction

                response `responseStatusShouldBe` status302
                currentLiveUpdateVersion "dashboard-live-demo" `shouldReturn` 1

resetDashboardState :: IO ()
resetDashboardState = do
    resetDashboardLiveDemoCount
    resetLiveUpdateScope "dashboard-live-demo"

createTestUser :: (?modelContext :: ModelContext) => IO User
createTestUser = do
    uuid <- UUIDv4.nextRandom
    let email = "dashboard-spec-" <> UUID.toText uuid <> "@example.com"
    newRecord @User
        |> set #email email
        |> set #passwordHash "test-password-hash"
        |> createRecord
