module Web.Controller.E2ETest where

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Network.HTTP.Types.Status (status403, status404, status409)
import qualified System.Environment as Environment
import Web.Controller.Prelude

e2eTestMutationSpec :: BepisMutationSpec
e2eTestMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisRealtimeNotApplicable
    , scopePolicy = BepisCurrentUserScope
    }

instance Controller E2ETestController where
    beforeAction = bepisBeforeAction BepisAuthenticatedController do
        annotateTelemetryAction
        ensureIsUser

    action currentAction@MarkE2EPasskeyVerifiedAction = bepisJsonMutationAction currentAction e2eTestMutationSpec do
        ensureE2ETestEndpointEnabled
        ensureE2ETestToken
        hasPasskey <- currentUserHasPasskey
        unless hasPasskey do
            renderJsonWithStatusCode status409 (Aeson.object ["error" Aeson..= ("Current user has no passkey" :: Text)])
        markCurrentUserPasskeyVerified
        renderJson (Aeson.object ["ok" Aeson..= True])

ensureE2ETestEndpointEnabled :: (?request :: Request) => IO ()
ensureE2ETestEndpointEnabled = do
    enabled <- liftIO (Environment.lookupEnv "IHP_ROSTER_E2E")
    unless (enabled == Just "1") do
        renderJsonWithStatusCode status404 (Aeson.object ["error" Aeson..= ("Not found" :: Text)])

ensureE2ETestToken :: (?request :: Request) => IO ()
ensureE2ETestToken = do
    expectedToken <- fmap (fmap (Text.strip . cs)) (liftIO (Environment.lookupEnv "E2E_TEST_TOKEN"))
    let submittedToken = Text.strip . cs <$> getHeader "X-E2E-Test-Token"
    unless (maybe False (not . Text.null) expectedToken && submittedToken == expectedToken) do
        renderJsonWithStatusCode status403 (Aeson.object ["error" Aeson..= ("Invalid E2E test token" :: Text)])
