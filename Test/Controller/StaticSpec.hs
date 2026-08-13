module Test.Controller.StaticSpec where

import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status

import Config
import Control.Exception (bracket, bracket_)
import qualified Data.Text.IO as TextIO
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import IHP.ViewSupport (liveReloadWebsocketUrl)
import Test.Hspec
import Test.Support

import Generated.Types
import IHP.ControllerPrelude
import Network.Wai
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.IO (hClose, openTempFile)
import Web.Controller.Static ()
import Web.FrontController ()
import Web.Routes
import Web.Types
import Web.View.Layout (developmentLiveReloadWebsocketUrlForHost)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "StaticController" do
        it "renders the welcome page for unauthenticated users" $ withContext do
            response <- callAction WelcomeAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Bepis"
            response `responseBodyShouldContain` "Sign In"
            response `responseBodyShouldContain` "href=\"/NewSession\""
            response `responseBodyShouldNotContain` "Request Access"
            response `responseBodyShouldNotContain` "js-passkey-first-login"
            response `responseBodyShouldNotContain` "/BeginPasskeyAuthentication"
            response `responseBodyShouldNotContain` "/FinishPasskeyAuthentication"
            response `responseBodyShouldContain` "Billing and support information"

        it "routes public dev livereload through the HTTPS tunnel without changing localhost" \_ -> do
            let localLiveReloadUrl = "ws://localhost:8013"
            developmentLiveReloadWebsocketUrlForHost localLiveReloadUrl (Just "dev.bepis.lol")
                `shouldBe` "wss://dev.bepis.lol/__ihp-livereload"
            developmentLiveReloadWebsocketUrlForHost localLiveReloadUrl (Just "localhost:8000")
                `shouldBe` localLiveReloadUrl

        it "renders generated PWA install roles with server-owned result copy and native accessibility state" $ withContext do
            response <- callAction InstallAppAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "data-bepis-pwa-install-page=\"true\""
            response `responseBodyShouldContain` "data-bepis-pwa-install-button=\"true\""
            response `responseBodyShouldContain` "data-bepis-pwa-install-result=\"true\""
            response `responseBodyShouldContain` "data-bepis-pwa-installed-status=\"true\""
            response `responseBodyShouldContain` "data-bepis-pwa-install-result-state=\"accepted\""
            response `responseBodyShouldContain` "data-bepis-pwa-install-result-state=\"dismissed\""
            response `responseBodyShouldContain` "data-bepis-pwa-install-result-state=\"failed\""
            response `responseBodyShouldContain` "Installation accepted. Bepis will appear on your device when installation completes."
            response `responseBodyShouldContain` "Installation was not completed. You can use the browser menu to try again."
            response `responseBodyShouldContain` "Installation could not start. Use the browser menu to install Bepis."
            response `responseBodyShouldContain` "Bepis is installed on this device."
            response `responseBodyShouldContain` "role=\"status\""
            response `responseBodyShouldContain` "aria-live=\"polite\""
            response `responseBodyShouldContain` "hidden=\"hidden\""
            response `responseBodyShouldNotContain` "data-pwa-install"
            response `responseBodyShouldNotContain` "data-pwa-installed-status"

        it "renders the public billing support page without authentication" $ withContext do
            response <- callAction PublicBillingSupportAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Venue operations software for hospitality teams"
            response `responseBodyShouldContain` "Operated by Bepis PTY LTD"
            response `responseBodyShouldContain` "support@bepis.lol"
            response `responseBodyShouldContain` "Customer Terms"
            response `responseBodyShouldContain` "Privacy"
            response `responseBodyShouldContain` "Refunds and Disputes"
            response `responseBodyShouldContain` "Cancellation"
            response `responseBodyShouldContain` "AUD 100 per venue per month"
            response `responseBodyShouldContain` "Stripe-hosted Checkout"
            response `responseBodyShouldContain` "Stripe-hosted Customer Portal"
            response `responseBodyShouldContain` "/LegalTerms"
            response `responseBodyShouldContain` "/LegalPrivacy"
            response `responseBodyShouldContain` "/LegalRefundsDisputes"
            response `responseBodyShouldContain` "/LegalCancellation"

        it "renders public legal documents without authentication" $ withContext do
            terms <- callAction LegalTermsAction
            terms `responseStatusShouldBe` status200
            terms `responseBodyShouldContain` "Bepis PTY LTD customer terms"
            terms `responseBodyShouldContain` "Last updated: 8 May 2026"
            terms `responseBodyShouldContain` "ACN 697 629 208"
            terms `responseBodyShouldContain` "Fair Work Commission Modern Awards Pay Database"
            terms `responseBodyShouldContain` "support@bepis.lol"

            privacy <- callAction LegalPrivacyAction
            privacy `responseStatusShouldBe` status200
            privacy `responseBodyShouldContain` "Bepis PTY LTD privacy policy"
            privacy `responseBodyShouldContain` "Payment method details are handled by Stripe-hosted billing pages"
            privacy `responseBodyShouldContain` "Xero when a customer enables Xero integrations"
            privacy `responseBodyShouldContain` "destroy, de-identify, or put it beyond use"

            refunds <- callAction LegalRefundsDisputesAction
            refunds `responseStatusShouldBe` status200
            refunds `responseBodyShouldContain` "refund and dispute policy"
            refunds `responseBodyShouldContain` "within 5 business days"
            refunds `responseBodyShouldContain` "not automatic for change of mind"
            refunds `responseBodyShouldContain` "physical return processes do not apply"

            cancellation <- callAction LegalCancellationAction
            cancellation `responseStatusShouldBe` status200
            cancellation `responseBodyShouldContain` "cancellation policy"
            cancellation `responseBodyShouldContain` "Stripe Customer Portal"
            cancellation `responseBodyShouldContain` "continues until the end of the current paid subscription period"

        it "renders configured legal document files" $ withContext do
            withTempLegalDocument "Injected privacy policy for Bepis PTY LTD.\n\nContact support@bepis.lol." \privacyPath ->
                withEnv "BEPIS_LEGAL_PRIVACY_FILE" (Just privacyPath) do
                    response <- callAction LegalPrivacyAction
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "Injected privacy policy for Bepis PTY LTD."
                    response `responseBodyShouldContain` "Contact support@bepis.lol."

        it "redirects authenticated users to the roster week view" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "welcome-auth@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUser user do
                    callAction WelcomeAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "keeps the public billing support page available to authenticated users" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue Public Support"
                user <- createUserRecord "public-support-auth@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUser user do
                    callAction PublicBillingSupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "support@bepis.lol"

withTempLegalDocument :: Text -> (String -> IO a) -> IO a
withTempLegalDocument value action =
    bracket setup cleanup \(path, _) -> action path
    where
        setup = do
            (path, handle) <- openTempFile "/tmp" "bepis-legal"
            TextIO.hPutStr handle value
            hClose handle
            pure (path, handle)

        cleanup (path, _) =
            Directory.removeFile path

withEnv :: String -> Maybe String -> IO a -> IO a
withEnv name value action =
    bracket_ setup restore action
    where
        setup = do
            previous <- Environment.lookupEnv name
            Environment.setEnv ("__PREVIOUS_" <> name) (fromMaybe "" previous)
            Environment.setEnv ("__HAD_PREVIOUS_" <> name) (if isJust previous then "1" else "0")
            apply value

        restore = do
            hadPrevious <- Environment.lookupEnv ("__HAD_PREVIOUS_" <> name)
            previous <- Environment.lookupEnv ("__PREVIOUS_" <> name)
            case (hadPrevious, previous) of
                (Just "1", Just oldValue) -> Environment.setEnv name oldValue
                _                         -> Environment.unsetEnv name
            Environment.unsetEnv ("__PREVIOUS_" <> name)
            Environment.unsetEnv ("__HAD_PREVIOUS_" <> name)

        apply Nothing      = Environment.unsetEnv name
        apply (Just value) = Environment.setEnv name value
