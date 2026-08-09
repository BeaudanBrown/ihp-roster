module Application.Helper.PasswordResetTokens
    ( activePasswordResetTokenById
    , findActivePasswordResetToken
    , issuePasswordResetToken
    , issuePasswordResetTokenWith
    , passwordResetTokenLifetime
    , sendPasswordResetTokenEmail
    ) where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Application.Helper.OpaqueToken (generateOpaqueToken, hashOpaqueToken)
import Application.Helper.Url (appendQueryParams)
import Application.PasswordReset.Mutations (withPasswordResetUserLock)
import IHP.EnvVar
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.PasswordReset
import Web.Types

passwordResetTokenLifetime :: NominalDiffTime
passwordResetTokenLifetime = 60 * 60

issuePasswordResetToken ::
    (?modelContext :: ModelContext) =>
    User ->
    Id User ->
    Id Venue ->
    IO (PasswordResetToken, Text)
issuePasswordResetToken targetUser requestedByUserId venueId =
    issuePasswordResetTokenWith targetUser requestedByUserId venueId (const (pure ()))

issuePasswordResetTokenWith ::
    (?modelContext :: ModelContext) =>
    User ->
    Id User ->
    Id Venue ->
    (PasswordResetToken -> IO ()) ->
    IO (PasswordResetToken, Text)
issuePasswordResetTokenWith targetUser requestedByUserId venueId afterIssue = do
    rawToken <- generateOpaqueToken
    now <- getCurrentTime
    maybeToken <- withPasswordResetUserLock (unpackId targetUser.id) do
        existingTokens <- query @PasswordResetToken
            |> filterWhere (#userId, unpackId targetUser.id)
            |> filterWhere (#consumedAt, Nothing)
            |> fetch
        forM_ existingTokens \token ->
            token
                |> set #consumedAt (Just now)
                |> updateRecordDiscardResult
        token <- newRecord @PasswordResetToken
            |> set #userId (unpackId targetUser.id)
            |> set #requestedByUserId (Just (unpackId requestedByUserId))
            |> set #venueId (unpackId venueId)
            |> set #tokenHash (hashOpaqueToken rawToken)
            |> set #sentToEmail targetUser.email
            |> set #expiresAt (addUTCTime passwordResetTokenLifetime now)
            |> createRecord
        afterIssue token
        pure token
    case maybeToken of
        Just token -> pure (token, rawToken)
        Nothing -> error "Password reset target disappeared while issuing token"

sendPasswordResetTokenEmail ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    User ->
    Text ->
    IO ()
sendPasswordResetTokenEmail targetUser rawToken = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    let resetUrl = appBaseUrl <> appendQueryParams (pathTo NewPasswordResetAction) [("token", rawToken)]
    unless emailDeliveryDisabled do
        sendMail PasswordResetMail
            { user = targetUser
            , resetUrl
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }

findActivePasswordResetToken :: (?modelContext :: ModelContext) => Text -> IO (Maybe PasswordResetToken)
findActivePasswordResetToken rawToken =
    query @PasswordResetToken
        |> filterWhere (#tokenHash, hashOpaqueToken rawToken)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

activePasswordResetTokenById :: (?modelContext :: ModelContext) => Id PasswordResetToken -> IO (Maybe PasswordResetToken)
activePasswordResetTokenById tokenId =
    query @PasswordResetToken
        |> filterWhere (#id, tokenId)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing
