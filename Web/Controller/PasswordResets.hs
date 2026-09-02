module Web.Controller.PasswordResets where

import Application.AccountSecurityEmail.Email (fetchEligibleAccountSecurityRecipient,
                                               passwordResetTokenAuthorityIsCurrent)
import Application.Helper.Audit
import Application.Helper.EmailVerification (issueEmailVerificationWithCooldown)
import Application.Helper.PasswordResetTokens
import Application.PasswordReset.Mutations (withPasswordResetCompletionLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.PasswordResets.Edit
import Web.View.PasswordResets.New

instance Controller PasswordResetsController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@NewPasswordResetRequestAction = runBepis currentAction BepisFormAction do
        render NewView

    action currentAction@CreatePasswordResetRequestAction = runBepis currentAction BepisMutationAction do
        let submittedEmail = Text.strip (paramOrDefault @Text "" "email")
        when (not (Text.null submittedEmail) && Text.length submittedEmail <= 254) do
            maybeUser <- query @User
                |> filterWhereCaseInsensitive (#email, submittedEmail)
                |> fetchOneOrNothing
            forM_ maybeUser requestAccountRecovery
        setSuccessMessage genericPasswordResetRequestMessage
        redirectTo NewPasswordResetRequestAction

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
                                        |> set #failedLoginAttempts 0
                                        |> set #lockedAt Nothing
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

requestAccountRecovery :: (?modelContext :: ModelContext) => User -> IO ()
requestAccountRecovery user
    | isJust user.deactivatedAt = pure ()
    | user.platformRole == Just SuperAdmin = pure ()
    | otherwise = do
        maybeVenueId <- fetchSelfServiceRecoveryVenueId user
        forM_ maybeVenueId \venueId ->
            if isNothing user.emailVerifiedAt
                then void (issueEmailVerificationWithCooldown user)
                else void (issuePasswordResetTokenWithCooldown user venueId)

fetchSelfServiceRecoveryVenueId :: (?modelContext :: ModelContext) => User -> IO (Maybe (Id Venue))
fetchSelfServiceRecoveryVenueId user = do
    memberships <- query @VenueMembership
        |> filterWhere (#userId, unpackId user.id)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #createdAt
        |> fetch
    firstActiveVenue memberships
  where
    firstActiveVenue [] = pure Nothing
    firstActiveVenue (membership : remaining) = do
        maybeVenue <- query @Venue
            |> filterWhere (#id, Id membership.venueId)
            |> filterWhere (#status, Active)
            |> filterWhere (#closedAt, Nothing)
            |> fetchOneOrNothing
        case maybeVenue of
            Just venue -> pure (Just venue.id)
            Nothing    -> firstActiveVenue remaining

genericPasswordResetRequestMessage :: Text
genericPasswordResetRequestMessage =
    "If an eligible account matches that email, a recovery message will be queued shortly."

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
invalidPasswordResetLink = do
    setErrorMessage "This password reset link is invalid or has expired."
    redirectTo NewSessionAction
    error "unreachable"
