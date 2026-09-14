module Application.Helper.PasswordResetTokens
    ( activePasswordResetTokenById
    , findActivePasswordResetToken
    , issuePasswordResetToken
    , issuePasswordResetTokenWith
    , issuePasswordResetTokenWithCooldown
    , passwordResetTokenLifetime
    ) where

import Application.AccountSecurityEmail.Enqueue (enqueuePasswordResetDelivery)
import Application.AccountSecurityEmail.TokenCipher (encryptAccountSecurityDeliveryToken)
import Application.AccountSecurityEmail.Types (accountRecoveryRequestCooldown,
                                               accountRecoveryTokenLifetime)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.OpaqueToken (generateOpaqueToken, hashOpaqueToken)
import Application.PasswordReset.Mutations (withPasswordResetUserLock)
import Control.Monad (void)
import Web.Controller.Prelude

passwordResetTokenLifetime :: NominalDiffTime
passwordResetTokenLifetime = accountRecoveryTokenLifetime

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
    deliveryTokenCiphertext <- encryptAccountSecurityDeliveryToken rawToken
    now <- getCurrentTime
    maybeToken <- withPasswordResetUserLock (unpackId targetUser.id) do
        issuePasswordResetTokenInCurrentTransaction targetUser requestedByUserId venueId afterIssue rawToken deliveryTokenCiphertext now
    case maybeToken of
        Just token -> pure (token, rawToken)
        Nothing -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Password reset target disappeared while issuing token"

issuePasswordResetTokenWithCooldown ::
    (?modelContext :: ModelContext) =>
    User ->
    Id Venue ->
    IO (Maybe (PasswordResetToken, Text))
issuePasswordResetTokenWithCooldown targetUser venueId = do
    rawToken <- generateOpaqueToken
    deliveryTokenCiphertext <- encryptAccountSecurityDeliveryToken rawToken
    now <- getCurrentTime
    maybeIssued <- withPasswordResetUserLock (unpackId targetUser.id) do
        latestToken <- query @PasswordResetToken
            |> filterWhere (#userId, unpackId targetUser.id)
            |> orderByDesc #createdAt
            |> limit 1
            |> fetchOneOrNothing
        case latestToken of
            Just token | diffUTCTime now token.createdAt < accountRecoveryRequestCooldown -> pure Nothing
            _ -> do
                token <- issuePasswordResetTokenInCurrentTransaction targetUser targetUser.id venueId (const (pure ())) rawToken deliveryTokenCiphertext now
                pure (Just (token, rawToken))
    pure (join maybeIssued)

issuePasswordResetTokenInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    User ->
    Id User ->
    Id Venue ->
    (PasswordResetToken -> IO ()) ->
    Text ->
    Text ->
    UTCTime ->
    IO PasswordResetToken
issuePasswordResetTokenInCurrentTransaction targetUser requestedByUserId venueId afterIssue rawToken deliveryTokenCiphertext now = do
    existingTokens <- query @PasswordResetToken
        |> filterWhere (#userId, unpackId targetUser.id)
        |> filterWhere (#consumedAt, Nothing)
        |> fetch
    forM_ existingTokens \token ->
        token
            |> set #consumedAt (Just now)
            |> set #deliveryTokenCiphertext Nothing
            |> updateRecordDiscardResult
    token <- newRecord @PasswordResetToken
        |> set #userId (unpackId targetUser.id)
        |> set #requestedByUserId (Just (unpackId requestedByUserId))
        |> set #venueId (unpackId venueId)
        |> set #tokenHash (hashOpaqueToken rawToken)
        |> set #deliveryTokenCiphertext (Just deliveryTokenCiphertext)
        |> set #sentToEmail targetUser.email
        |> set #expiresAt (addUTCTime passwordResetTokenLifetime now)
        |> createRecord
    afterIssue token
    void (enqueuePasswordResetDelivery token)
    pure token

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
