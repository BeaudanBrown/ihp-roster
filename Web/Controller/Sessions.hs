module Web.Controller.Sessions where

import Application.AccountSecurityEmail.Email (fetchEligibleAccountSecurityRecipient)
import Application.AccountSecurityEmail.Mutations (withEmailVerificationTokenLock)
import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import Application.Helper.EmailVerification (findActiveVerificationTokenByToken,
                                             issueEmailVerification)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeySetupPromptMode (..),
                                                            passkeySetupPromptModeValue)
import Application.Helper.Profiling (isRequestProfilingEnabled,
                                     profileActionSpan)
import Application.Helper.SessionVersion (clearAuthenticatedSessionVersion,
                                          markAuthenticatedSessionVersion)
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
            accessDeniedUnless (not currentUserIsImpersonating)
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
                                        LoginBlockedAudit
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
                                            LoginSucceededAudit
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
                                let passkeySetupPromptMode =
                                        if passkeyCount == 0
                                            then PasskeyFirstPasskey
                                            else PasskeyAdditionalDevice
                                setSession passkeySetupPromptSessionKey (passkeySetupPromptModeValue passkeySetupPromptMode)
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
                                            LoginFailedAudit
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

    action currentAction@DeleteSessionAction = runBepis currentAction BepisMutationAction do
        void (exitCurrentImpersonation "logout")
        Sessions.deleteSessionAction @User

    action currentAction@VerifyEmailAction = runBepis currentAction BepisMutationAction do
        accessDeniedUnless (not currentUserIsImpersonating)
        let verificationTokenValue = param @Text "token"
        findActiveVerificationTokenByToken verificationTokenValue >>= \case
            Nothing -> do
                setErrorMessage "That verification link is invalid or has expired."
                redirectTo NewSessionAction
            Just verificationToken -> do
                maybeVerifiedUser <- withEmailVerificationTokenLock (unpackId verificationToken.id) do
                    lockedToken <-
                        query @EmailVerificationToken
                            |> filterWhere (#id, verificationToken.id)
                            |> filterWhere (#consumedAt, Nothing)
                            |> filterWhereFuture #expiresAt
                            |> fetchOneOrNothing
                    case lockedToken of
                        Nothing -> pure Nothing
                        Just activeToken ->
                            fetchEligibleAccountSecurityRecipient activeToken.userId activeToken.sentToEmail >>= \case
                                Nothing -> pure Nothing
                                Just user -> do
                                    now <- getCurrentTime
                                    verifiedUser <-
                                        user
                                            |> set #emailVerifiedAt (Just now)
                                            |> updateRecord
                                    activeToken
                                        |> set #consumedAt (Just now)
                                        |> updateRecordDiscardResult
                                    pure (Just verifiedUser)
                case join maybeVerifiedUser of
                    Nothing -> do
                        setErrorMessage "That verification link is invalid or has expired."
                        redirectTo NewSessionAction
                    Just verifiedUser -> do
                        Sessions.beforeLogin verifiedUser
                        LoginSupport.login verifiedUser
                        setSuccessMessage "Email verified."
                        redirectTo EditProfileAction

    action currentAction@ResendVerificationAction = runBepis currentAction BepisMutationAction do
        accessDeniedUnless (not currentUserIsImpersonating)
        let submittedEmail = param @Text "email"
        maybeUser <-
            query @User
                |> filterWhereCaseInsensitive (#email, submittedEmail)
                |> fetchOneOrNothing
        case maybeUser of
            Just user | isNothing user.emailVerifiedAt -> do
                void (issueEmailVerification user)
                setSuccessMessage "Verification email queued and should arrive shortly."
            _ ->
                setSuccessMessage "If that account exists and still needs verification, a new email has been queued."
        setSession pendingVerificationEmailSessionKey submittedEmail
        redirectTo NewSessionAction

instance Sessions.SessionsControllerConfig User where
    afterLoginRedirectPath = "/RosterWeeks"

    beforeLogin user = do
        markAuthenticatedSessionVersion user
        deleteSession effectiveUserSessionKey
        deleteSession impersonationSessionIdSessionKey
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
        deleteSession effectiveUserSessionKey
        deleteSession impersonationSessionIdSessionKey
        clearAuthenticatedSessionVersion
        clearCurrentUserPasskeyVerification

defaultLoginRedirectPath :: (?modelContext :: ModelContext) => User -> IO Text
defaultLoginRedirectPath user = do
    maybeVenueContext <- resolveVenueContextForUser Nothing user
    pure
        if user.platformRole == Just (SuperAdmin) && isNothing maybeVenueContext
            then pathTo SupportAction
            else Sessions.afterLoginRedirectPath @User

markProfilingSessionPasskeyVerifiedIfSeeded :: (?context :: ControllerContext) => User -> Int -> IO ()
markProfilingSessionPasskeyVerifiedIfSeeded user passkeyCount = do
    profilingEnabled <- liftIO isRequestProfilingEnabled
    when (profilingEnabled && passkeyCount > 0) do
        markUserPasskeyVerified user.id
