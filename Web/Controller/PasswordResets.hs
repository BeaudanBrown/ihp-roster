module Web.Controller.PasswordResets where

import Application.AccountSecurityEmail.Email (fetchEligibleAccountSecurityRecipient,
                                               passwordResetTokenAuthorityIsCurrent)
import Application.Helper.Audit
import Application.Helper.PasswordResetTokens
import Application.PasswordReset.Mutations (withPasswordResetCompletionLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.PasswordResets.Edit

instance Controller PasswordResetsController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@NewPasswordResetAction = runBepis currentAction BepisFormAction do
        rawToken <- passwordResetTokenParamOrInvalid
        findActivePasswordResetToken rawToken >>= \case
            Nothing -> invalidPasswordResetLink
            Just resetToken -> do
                targetUser <- fetchActivePasswordResetTarget resetToken
                case targetUser of
                    Nothing -> invalidPasswordResetLink
                    Just user -> render EditView { targetEmail = user.email, .. }

    action currentAction@UpdatePasswordResetAction = runBepis currentAction BepisMutationAction do
        rawToken <- passwordResetTokenParamOrInvalid
        resetToken <- findActivePasswordResetToken rawToken >>= maybe invalidPasswordResetLink pure
        let password = paramOrDefault @Text "" "password"
        let passwordConfirmation = paramOrDefault @Text "" "passwordConfirmation"
        case validatePasswordSubmission password passwordConfirmation of
            Just errorMessage -> do
                targetUser <- fetchActivePasswordResetTarget resetToken
                case targetUser of
                    Nothing -> invalidPasswordResetLink
                    Just user -> do
                        setErrorMessage errorMessage
                        render EditView { targetEmail = user.email, .. }
            Nothing -> do
                maybeCompleted <- withPasswordResetCompletionLock resetToken.userId (unpackId resetToken.id) do
                    activePasswordResetTokenById resetToken.id >>= \case
                        Nothing -> pure False
                        Just lockedToken -> do
                            fetchActivePasswordResetTarget lockedToken >>= \case
                                Nothing -> pure False
                                Just targetUser -> do
                                    passwordHash <- hashPassword password
                                    now <- getCurrentTime
                                    updatedUser <- targetUser
                                        |> set #passwordHash passwordHash
                                        |> incrementField #sessionVersion
                                        |> updateRecord
                                    _ <- lockedToken
                                        |> set #consumedAt (Just now)
                                        |> set #deliveryTokenCiphertext Nothing
                                        |> updateRecord
                                    void $
                                        recordAuditEvent
                                            lockedToken.venueId
                                            (unpackId targetUser.id)
                                            PasswordResetCompletedAudit
                                            "users"
                                            (unpackId targetUser.id)
                                            (Aeson.object
                                                [ "requestedByUserId" Aeson..= lockedToken.requestedByUserId
                                                , "sessionVersion" Aeson..= updatedUser.sessionVersion
                                                ]
                                            )
                                            WebAuditSource
                                    pure True
                if fromMaybe False maybeCompleted
                    then do
                        setSuccessMessage "Password reset. Sign in with your new password."
                        redirectTo NewSessionAction
                    else invalidPasswordResetLink

fetchActivePasswordResetTarget :: (?modelContext :: ModelContext) => PasswordResetToken -> IO (Maybe User)
fetchActivePasswordResetTarget resetToken = do
    maybeUser <- fetchEligibleAccountSecurityRecipient resetToken.userId resetToken.sentToEmail
    authorityIsCurrent <- passwordResetTokenAuthorityIsCurrent resetToken
    pure (if authorityIsCurrent then maybeUser else Nothing)

validatePasswordSubmission :: Text -> Text -> Maybe Text
validatePasswordSubmission password passwordConfirmation
    | Text.null password = Just "Password is required."
    | Text.length password > 256 = Just "Password must be 256 characters or fewer."
    | password /= passwordConfirmation = Just "Passwords don't match."
    | otherwise = Nothing

passwordResetTokenParamOrInvalid :: (?context :: ControllerContext, ?request :: Request) => IO Text
passwordResetTokenParamOrInvalid =
    maybe invalidPasswordResetLink pure (paramOrNothing @Text "token")

invalidPasswordResetLink :: (?context :: ControllerContext, ?request :: Request) => IO a
invalidPasswordResetLink =
    terminateAfterIhpResponseControl do
        setErrorMessage "This password reset link is invalid or has expired."
        redirectTo NewSessionAction
