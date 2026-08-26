module Application.Helper.PasswordResetTokens
    ( activePasswordResetTokenById
    , findActivePasswordResetToken
    , issuePasswordResetToken
    , issuePasswordResetTokenWith
    , passwordResetTokenLifetime
    ) where

import Application.AccountSecurityEmail.Enqueue (enqueuePasswordResetDelivery)
import Application.AccountSecurityEmail.TokenCipher (encryptAccountSecurityDeliveryToken)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.OpaqueToken (generateOpaqueToken, hashOpaqueToken)
import Application.PasswordReset.Mutations (withPasswordResetUserLock)
import Control.Monad (void)
import Web.Controller.Prelude

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
    deliveryTokenCiphertext <- encryptAccountSecurityDeliveryToken rawToken
    now <- getCurrentTime
    maybeToken <- withPasswordResetUserLock (unpackId targetUser.id) do
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
    case maybeToken of
        Just token -> pure (token, rawToken)
        Nothing -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Password reset target disappeared while issuing token"

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
