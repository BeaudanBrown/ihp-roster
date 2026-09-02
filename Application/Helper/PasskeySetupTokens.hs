module Application.Helper.PasskeySetupTokens
    ( PasskeySetupTokenPurpose (..)
    , findActivePasskeySetupToken
    , issuePasskeySetupToken
    , issuePasskeySetupTokenWith
    , passkeySetupTokenLifetime
    ) where

import Application.AccountSecurityEmail.Enqueue (enqueuePasskeySetupDelivery)
import Application.AccountSecurityEmail.TokenCipher (encryptAccountSecurityDeliveryToken)
import Application.AccountSecurityEmail.Types
import Application.Helper.OpaqueToken (generateOpaqueToken, hashOpaqueToken)
import Control.Monad (void)
import Web.Controller.Prelude

passkeySetupTokenLifetime :: NominalDiffTime
passkeySetupTokenLifetime = accountRecoveryTokenLifetime

issuePasskeySetupToken ::
    (?modelContext :: ModelContext) =>
    PasskeySetupTokenPurpose ->
    User ->
    Maybe (Id User) ->
    Maybe (Id Venue) ->
    IO (PasskeySetupToken, Text)
issuePasskeySetupToken purpose targetUser requestedByUserId venueId =
    issuePasskeySetupTokenWith purpose targetUser requestedByUserId venueId (const (pure ()))

issuePasskeySetupTokenWith ::
    (?modelContext :: ModelContext) =>
    PasskeySetupTokenPurpose ->
    User ->
    Maybe (Id User) ->
    Maybe (Id Venue) ->
    (PasskeySetupToken -> IO ()) ->
    IO (PasskeySetupToken, Text)
issuePasskeySetupTokenWith purpose targetUser requestedByUserId venueId afterIssue = do
    rawToken <- generateOpaqueToken
    deliveryTokenCiphertext <- encryptAccountSecurityDeliveryToken rawToken
    now <- getCurrentTime
    let expiresAt = addUTCTime passkeySetupTokenLifetime now
    setupToken <- withTransaction do
        token <- newRecord @PasskeySetupToken
            |> set #userId (unpackId targetUser.id)
            |> set #requestedByUserId (unpackId <$> requestedByUserId)
            |> set #venueId (unpackId <$> venueId)
            |> set #tokenHash (hashOpaqueToken rawToken)
            |> set #deliveryTokenCiphertext (Just deliveryTokenCiphertext)
            |> set #purpose (passkeySetupTokenPurposeText purpose)
            |> set #sentToEmail targetUser.email
            |> set #expiresAt expiresAt
            |> createRecord
        afterIssue token
        void (enqueuePasskeySetupDelivery token)
        pure token
    pure (setupToken, rawToken)

findActivePasskeySetupToken :: (?modelContext :: ModelContext) => Text -> IO (Maybe PasskeySetupToken)
findActivePasskeySetupToken rawToken =
    query @PasskeySetupToken
        |> filterWhere (#tokenHash, hashOpaqueToken rawToken)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing
