module Web.Controller.Sessions where

import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import Application.Helper.EmailVerification (findActiveVerificationTokenByToken,
                                             sendEmailVerification)
import Application.Helper.Profiling (isRequestProfilingEnabled,
                                     profileActionSpan)
import Control.Exception (evaluate)
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
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@NewSessionAction = runBepis currentAction BepisPageAction do
        case currentUserOrNothing @User of
            Just user -> do
                redirectPath <- defaultLoginRedirectPath user
                redirectToPath redirectPath
            Nothing -> pure ()

        let user = newRecord @User
        pendingVerificationEmail <- getSessionAndClear pendingVerificationEmailSessionKey
        render NewView { .. }

    action currentAction@CreateSessionAction =
        runBepis currentAction BepisMutationAction $ profileActionSpan "auth.password_login" do
            let submittedEmail = param @Text "email"
            profileActionSpan "auth.password_login.find_user"
                ( query @User
                    |> filterWhereCaseInsensitive (#email, submittedEmail)
                    |> fetchOneOrNothing
                )
                >>= \case
                    Just user -> do
                        isLocked <- profileActionSpan "auth.password_login.check_lock" (Lockable.isLocked user)
                        when isLocked do
                            profileActionSpan "auth.password_login.audit_blocked" $
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

                        passwordMatches <- profileActionSpan "auth.password_login.verify_password" (evaluate (verifyPassword user (param @Text "password")))
                        if passwordMatches
                            then do
                                profileActionSpan "auth.password_login.before_login" (Sessions.beforeLogin user)
                                profileActionSpan "auth.password_login.create_session" (LoginSupport.login user)
                                clearCurrentUserPasskeyVerification
                                _ <- profileActionSpan "auth.password_login.reset_failed_attempts" $
                                    user
                                        |> set #failedLoginAttempts 0
                                        |> updateRecord
                                profileActionSpan "auth.password_login.audit_succeeded" $
                                    void $
                                        recordUserAuthenticationAuditEvent
                                            user
                                            "login_succeeded"
                                            (Aeson.object
                                                [ "authMethod" Aeson..= ("password" :: Text)
                                                , "email" Aeson..= submittedEmail
                                                ]
                                            )
                                passkeyCount <- profileActionSpan "auth.password_login.fetch_passkey_count" $
                                    query @Passkey
                                        |> filterWhere (#userId, unpackId (get #id user))
                                        |> fetchCount
                                markProfilingSessionPasskeyVerifiedIfSeeded user passkeyCount
                                setSession passkeySetupPromptSessionKey
                                    if passkeyCount == 0
                                        then ("first-passkey" :: Text)
                                        else ("additional-device" :: Text)
                                redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
                                defaultRedirectPath <- profileActionSpan "auth.password_login.default_redirect" (defaultLoginRedirectPath user)
                                redirectToPath (fromMaybe defaultRedirectPath redirectUrl)
                            else do
                                setErrorMessage "Invalid Credentials"
                                user' <- profileActionSpan "auth.password_login.increment_failed_attempts" $
                                    user
                                        |> incrementField #failedLoginAttempts
                                        |> updateRecord
                                profileActionSpan "auth.password_login.audit_failed" $
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
                                    profileActionSpan "auth.password_login.lock_user" (Lockable.lock user')
                                    pure ()
                                redirectTo NewSessionAction
                    Nothing -> do
                        setErrorMessage "Invalid Credentials"
                        redirectTo NewSessionAction

    action currentAction@DeleteSessionAction = runBepis currentAction BepisMutationAction (Sessions.deleteSessionAction @User)

    action currentAction@VerifyEmailAction = runBepis currentAction BepisMutationAction do
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

    action currentAction@ResendVerificationAction = runBepis currentAction BepisMutationAction do
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
