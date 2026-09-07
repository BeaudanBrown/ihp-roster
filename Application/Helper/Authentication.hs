module Application.Helper.Authentication (authenticationMiddleware) where

import Application.Helper.ControllerAccess (clearCurrentUserPasskeyVerification)
import Application.Helper.ControllerContext (currentVenueSessionKey)
import Application.Helper.Impersonation (clearImpersonationReturnFallback, effectiveUserSessionKey, impersonationSessionIdSessionKey)
import Application.Helper.SessionVersion (authenticatedSessionVersionIsCurrent, clearAuthenticatedSessionVersion)
import qualified Control.Exception.Safe as Exception
import qualified Data.Text.IO as TextIO
import qualified Data.Vault.Lazy as Vault
import Generated.Types
import IHP.ControllerPrelude
import IHP.LoginSupport.Helper.Controller (sessionKey)
import IHP.LoginSupport.Middleware (authMiddlewareWith, userIdMiddleware, currentUserVaultKey, currentUserIdVaultKey, lookupAuthVault)
import IHP.Controller.Session (lookupSessionVault)
import qualified Network.Wai as Wai
import Web.Types ()

-- IHP runs this after session/model-context middleware, including for WebSockets.
-- Catch only the user fetch, never the downstream application/response. Failed
-- fetches become anonymous without logging query text, cookie data or exceptions.
-- Version validation and cookie clearing happen BEFORE handing off the request:
-- deleting a cookie alone cannot revoke IHP's already loaded immutable vault user.
authenticationMiddleware :: Wai.Middleware
authenticationMiddleware =
    userIdMiddleware (sessionKey @User)
        . authMiddlewareWith currentUserVaultKey loadUser
        . validateAuthenticatedRequest

loadUser :: Wai.Request -> IO (Maybe User)
loadUser request = do
    let ?modelContext = request.modelContext
    case lookupAuthVault currentUserIdVaultKey request of
        Nothing -> pure Nothing
        Just userId -> do
            result <- Exception.tryAny (fetchOneOrNothing (Id userId :: Id User))
            case result of
                Right user -> pure user
                Left _ -> do
                    TextIO.putStrLn "auth_init_failure"
                    pure Nothing

validateAuthenticatedRequest :: Wai.Middleware
validateAuthenticatedRequest app request respond = do
    let ?request = request
    let ?context = request
    rawUser <- case lookupSessionVault request of
        Nothing -> pure Nothing
        Just (lookupSession, _) -> lookupSession (sessionKey @User)
    valid <- case currentUserOrNothing @User of
        Nothing -> pure (rawUser == Nothing || rawUser == Just "")
        Just _ -> authenticatedSessionVersionIsCurrent
    if valid
        then app request respond
        else do
            deleteSession (sessionKey @User)
            clearAuthenticatedSessionVersion
            clearCurrentUserPasskeyVerification
            deleteSession currentVenueSessionKey
            deleteSession effectiveUserSessionKey
            deleteSession impersonationSessionIdSessionKey
            clearImpersonationReturnFallback
            let anonymousRequest = request
                    { Wai.vault = Vault.insert currentUserVaultKey Nothing
                        (Vault.insert currentUserIdVaultKey Nothing request.vault)
                    }
            app anonymousRequest respond
