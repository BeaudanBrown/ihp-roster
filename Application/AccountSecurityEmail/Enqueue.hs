module Application.AccountSecurityEmail.Enqueue
    ( enqueueEmailVerificationDelivery
    , enqueuePasskeySetupDelivery
    , enqueuePasswordResetDelivery
    ) where

import Application.AccountSecurityEmail.Types
import Application.EmailDelivery.Enqueue
import Generated.Types
import IHP.ControllerPrelude

enqueueEmailVerificationDelivery ::
    (?modelContext :: ModelContext) =>
    EmailVerificationToken ->
    User ->
    IO EmailDeliveryEnqueueResult
enqueueEmailVerificationDelivery token user =
    enqueueEmailDeliveryWithStatus
        EmailDeliveryRequest
            { mailKind = emailVerificationMailKind
            , recipientAccountId = unpackId user.id
            , recipientAddress = token.sentToEmail
            , domainReferenceTable = "email_verification_tokens"
            , domainReferenceId = unpackId token.id
            , semanticEventKey = "email-verification-token:" <> tshow token.id
            , requestedByUserId = Just (unpackId user.id)
            , venueId = Nothing
            }

enqueuePasswordResetDelivery ::
    (?modelContext :: ModelContext) =>
    PasswordResetToken ->
    IO EmailDeliveryEnqueueResult
enqueuePasswordResetDelivery token =
    enqueueEmailDeliveryWithStatus
        EmailDeliveryRequest
            { mailKind = passwordResetMailKind
            , recipientAccountId = token.userId
            , recipientAddress = token.sentToEmail
            , domainReferenceTable = "password_reset_tokens"
            , domainReferenceId = unpackId token.id
            , semanticEventKey = "password-reset-token:" <> tshow token.id
            , requestedByUserId = token.requestedByUserId
            , venueId = Just token.venueId
            }

enqueuePasskeySetupDelivery ::
    (?modelContext :: ModelContext) =>
    PasskeySetupToken ->
    IO EmailDeliveryEnqueueResult
enqueuePasskeySetupDelivery token =
    enqueueEmailDeliveryWithStatus
        EmailDeliveryRequest
            { mailKind = passkeySetupMailKind
            , recipientAccountId = token.userId
            , recipientAddress = token.sentToEmail
            , domainReferenceTable = "passkey_setup_tokens"
            , domainReferenceId = unpackId token.id
            , semanticEventKey = "passkey-setup-token:" <> tshow token.id
            , requestedByUserId = token.requestedByUserId
            , venueId = token.venueId
            }
