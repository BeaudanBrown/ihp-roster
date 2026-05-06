module Web.Controller.Sessions where

import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import Application.Helper.EmailVerification (findActiveVerificationTokenByToken,
                                             sendEmailVerification)
import Application.Helper.Profiling (isRequestProfilingEnabled)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import IHP.AuthSupport.Authentication (verifyPassword)
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.AuthSupport.Lockable as Lockable
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Web.Controller.Prelude
import Web.View.Sessions.New

pendingVerificationEmailSessionKey :: ByteString
pendingVerificationEmailSessionKey = "pendingVerificationEmail"

passkeySetupPromptSessionKey :: ByteString
passkeySetupPromptSessionKey = "passkeySetupPrompt"

instance Controller SessionsController where
    action NewSessionAction = do
        case currentUserOrNothing @User of
            Just user -> do
                redirectPath <- defaultLoginRedirectPath user
                redirectToPath redirectPath
            Nothing -> pure ()

        let user = newRecord @User
        pendingVerificationEmail <- getSessionAndClear pendingVerificationEmailSessionKey
        render NewView { .. }

    action CreateSessionAction = do
        let submittedEmail = param @Text "email"
        query @User
            |> filterWhereCaseInsensitive (#email, submittedEmail)
            |> fetchOneOrNothing
            >>= \case
                Just user -> do
                    isLocked <- Lockable.isLocked user
                    when isLocked do
                        void $
                            recordUserAuthenticationAuditEvent
                                user
                                "login_blocked"
                                (Aeson.object
                                    [ "authMethod" Aeson..= ("password" :: Text)
                                    , "email" Aeson..= submittedEmail
                                    , "reason" Aeson..= ("locked" :: Text)
                                    ]
                                )
                        setErrorMessage "User is locked"
                        redirectTo NewSessionAction

                    if verifyPassword user (param @Text "password")
                        then do
                            Sessions.beforeLogin user
                            LoginSupport.login user
                            clearCurrentUserPasskeyVerification
                            _ <- user
                                |> set #failedLoginAttempts 0
                                |> updateRecord
                            void $
                                recordUserAuthenticationAuditEvent
                                    user
                                    "login_succeeded"
                                    (Aeson.object
                                        [ "authMethod" Aeson..= ("password" :: Text)
                                        , "email" Aeson..= submittedEmail
                                        ]
                                    )
                            passkeyCount <-
                                query @Passkey
                                    |> filterWhere (#userId, unpackId (get #id user))
                                    |> fetchCount
                            markProfilingSessionPasskeyVerifiedIfSeeded user passkeyCount
                            setSession passkeySetupPromptSessionKey
                                if passkeyCount == 0
                                    then ("first-passkey" :: Text)
                                    else ("additional-device" :: Text)
                            redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
                            defaultRedirectPath <- defaultLoginRedirectPath user
                            redirectToPath (fromMaybe defaultRedirectPath redirectUrl)
                        else do
                            setErrorMessage "Invalid Credentials"
                            user' <- user
                                |> incrementField #failedLoginAttempts
                                |> updateRecord
                            void $
                                recordUserAuthenticationAuditEvent
                                    user'
                                    "login_failed"
                                    (Aeson.object
                                        [ "authMethod" Aeson..= ("password" :: Text)
                                        , "email" Aeson..= submittedEmail
                                        , "failedLoginAttempts" Aeson..= user'.failedLoginAttempts
                                        ]
                                    )
                            when (user'.failedLoginAttempts >= Sessions.maxFailedLoginAttempts user') do
                                Lockable.lock user'
                                pure ()
                            redirectTo NewSessionAction
                Nothing -> do
                    setErrorMessage "Invalid Credentials"
                    redirectTo NewSessionAction

    action DeleteSessionAction = Sessions.deleteSessionAction @User

    action VerifyEmailAction = do
        let verificationTokenValue = param @Text "token"
        findActiveVerificationTokenByToken verificationTokenValue >>= \case
            Nothing -> do
                setErrorMessage "That verification link is invalid or has expired."
                redirectTo NewSessionAction
            Just verificationToken -> do
                now <- getCurrentTime
                user <- fetch (Id verificationToken.userId :: Id User)
                withTransaction do
                    void $
                        user
                            |> set #emailVerifiedAt (Just now)
                            |> updateRecord
                    void $
                        verificationToken
                            |> set #consumedAt (Just now)
                            |> updateRecord
                let verifiedUser = user |> set #emailVerifiedAt (Just now)
                Sessions.beforeLogin verifiedUser
                LoginSupport.login verifiedUser
                setSuccessMessage "Email verified."
                redirectTo EditProfileAction

    action ResendVerificationAction = do
        let submittedEmail = param @Text "email"
        maybeUser <-
            query @User
                |> filterWhereCaseInsensitive (#email, submittedEmail)
                |> fetchOneOrNothing
        case maybeUser of
            Just user | isNothing user.emailVerifiedAt -> do
                void (sendEmailVerification user)
                setSuccessMessage "Verification email sent."
            _ ->
                setSuccessMessage "If that account exists and still needs verification, a new email has been sent."
        setSession pendingVerificationEmailSessionKey submittedEmail
        redirectTo NewSessionAction

instance Sessions.SessionsControllerConfig User where
    afterLoginRedirectPath = "/RosterWeeks"

    beforeLogin user = do
        when (isNothing user.emailVerifiedAt) do
            setSession pendingVerificationEmailSessionKey user.email
            setErrorMessage "Verify your email before signing in."
            redirectTo NewSessionAction

        maybeVenueContext <- resolveVenueContextForUser Nothing user
        case maybeVenueContext of
            Just (_, venue, _) -> setSession currentVenueSessionKey (get #id venue)
            Nothing -> deleteSession currentVenueSessionKey

    beforeLogout _ = do
        deleteSession currentVenueSessionKey
        clearCurrentUserPasskeyVerification

defaultLoginRedirectPath :: (?modelContext :: ModelContext) => User -> IO Text
defaultLoginRedirectPath user = do
    maybeVenueContext <- resolveVenueContextForUser Nothing user
    pure
        if user.platformRole == Just (platformRoleToEnum SuperAdminRole) && isNothing maybeVenueContext
            then pathTo SupportAction
            else Sessions.afterLoginRedirectPath @User

markProfilingSessionPasskeyVerifiedIfSeeded :: (?context :: ControllerContext) => User -> Int -> IO ()
markProfilingSessionPasskeyVerifiedIfSeeded user passkeyCount = do
    profilingEnabled <- liftIO isRequestProfilingEnabled
    when (profilingEnabled && passkeyCount > 0) do
        markUserPasskeyVerified user.id
