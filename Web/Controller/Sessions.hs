module Web.Controller.Sessions where

import Application.Helper.EmailVerification (findActiveVerificationTokenByToken,
                                             sendEmailVerification)
import Control.Monad (void)
import qualified IHP.AuthSupport.Lockable as Lockable
import IHP.AuthSupport.Authentication (verifyPassword)
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Web.Controller.Prelude
import Web.View.Sessions.New

pendingVerificationEmailSessionKey :: ByteString
pendingVerificationEmailSessionKey = "pendingVerificationEmail"

instance Controller SessionsController where
    action NewSessionAction = do
        let alreadyLoggedIn = isJust (currentUserOrNothing @User)
        when alreadyLoggedIn (redirectToPath (Sessions.afterLoginRedirectPath @User))

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
                        setErrorMessage "User is locked"
                        redirectTo NewSessionAction

                    if verifyPassword user (param @Text "password")
                        then do
                            Sessions.beforeLogin user
                            LoginSupport.login user
                            _ <- user
                                |> set #failedLoginAttempts 0
                                |> updateRecord
                            redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
                            redirectToPath (fromMaybe (Sessions.afterLoginRedirectPath @User) redirectUrl)
                        else do
                            setErrorMessage "Invalid Credentials"
                            user' <- user
                                |> incrementField #failedLoginAttempts
                                |> updateRecord
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
                setSuccessMessage "Email verified. You can sign in now."
                redirectTo NewSessionAction

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

    beforeLogout _ =
        deleteSession currentVenueSessionKey
