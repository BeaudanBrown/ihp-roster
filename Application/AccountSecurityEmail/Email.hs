module Application.AccountSecurityEmail.Email
    ( AccountSecurityMail (..)
    , AccountSecurityMailProjection (..)
    , completeAccountSecurityEmail
    , fetchEligibleAccountSecurityRecipient
    , loadAccountSecurityMail
    , passkeySetupTokenAuthorityIsCurrent
    , passwordResetTokenAuthorityIsCurrent
    ) where

import Application.AccountSecurityEmail.TokenCipher
import Application.AccountSecurityEmail.Types
import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.Users.EmailVerification
import Web.Mail.Users.PasskeySetupLink
import Web.Mail.Users.PasswordReset
import Web.Routes ()
import Web.Types

data AccountSecurityMail
    = VerificationDelivery !EmailVerificationMail
    | PasswordResetDelivery !PasswordResetMail
    | PasskeySetupDelivery !PasskeySetupLinkMail

data AccountSecurityMailProjection
    = AccountSecurityMailReady !AccountSecurityMail
    | AccountSecurityMailSkipped !Text

loadAccountSecurityMail ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO AccountSecurityMailProjection
loadAccountSecurityMail mailKind recipientAccountId recipientAddress domainReferenceId maybeVenueId settings appBaseUrl
    | mailKind == emailVerificationMailKind =
        loadEmailVerificationMail recipientAccountId recipientAddress domainReferenceId maybeVenueId settings appBaseUrl
    | mailKind == passwordResetMailKind =
        loadPasswordResetMail recipientAccountId recipientAddress domainReferenceId maybeVenueId settings appBaseUrl
    | mailKind == passkeySetupMailKind =
        loadPasskeySetupMail recipientAccountId recipientAddress domainReferenceId maybeVenueId settings appBaseUrl
    | otherwise = pure (AccountSecurityMailSkipped "unknown_account_security_mail_kind")

loadEmailVerificationMail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO AccountSecurityMailProjection
loadEmailVerificationMail recipientAccountId recipientAddress tokenId maybeVenueId settings appBaseUrl
    | isJust maybeVenueId = pure (AccountSecurityMailSkipped "venue_reference_mismatch")
    | otherwise = do
        maybeToken <- fetchOneOrNothing (Id tokenId :: Id EmailVerificationToken)
        case maybeToken of
            Nothing -> pure (AccountSecurityMailSkipped "domain_reference_missing")
            Just token -> do
                eligibility <- accountAndTokenEligibility recipientAccountId recipientAddress token.userId token.sentToEmail token.consumedAt token.expiresAt
                case eligibility of
                    Just reason -> pure (AccountSecurityMailSkipped reason)
                    Nothing -> do
                        user <- fetch (Id token.userId :: Id User)
                        if isJust user.emailVerifiedAt
                            then pure (AccountSecurityMailSkipped "email_already_verified")
                            else
                                pure $
                                    AccountSecurityMailReady $
                                        VerificationDelivery
                                            EmailVerificationMail
                                                { recipientAddress
                                                , verificationUrl = appBaseUrl <> appendQueryParams (pathTo VerifyEmailAction) [("token", token.token)]
                                                , fromAddress = settings.mailFromAddress
                                                , replyToAddress = settings.mailReplyToAddress
                                                , supportEmail = settings.mailSupportEmail
                                                }

loadPasswordResetMail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO AccountSecurityMailProjection
loadPasswordResetMail recipientAccountId recipientAddress tokenId maybeVenueId settings appBaseUrl = do
    maybeToken <- fetchOneOrNothing (Id tokenId :: Id PasswordResetToken)
    case maybeToken of
        Nothing -> pure (AccountSecurityMailSkipped "domain_reference_missing")
        Just token
            | maybeVenueId /= Just token.venueId -> pure (AccountSecurityMailSkipped "venue_reference_mismatch")
            | otherwise -> do
                eligibility <- accountAndTokenEligibility recipientAccountId recipientAddress token.userId token.sentToEmail token.consumedAt token.expiresAt
                authorityIsCurrent <- passwordResetTokenAuthorityIsCurrent token
                case eligibility <|> (if authorityIsCurrent then Nothing else Just "recipient_authority_obsolete") of
                    Just reason -> pure (AccountSecurityMailSkipped reason)
                    Nothing ->
                        projectEncryptedToken token.deliveryTokenCiphertext \rawToken ->
                            AccountSecurityMailReady $
                                PasswordResetDelivery
                                    PasswordResetMail
                                        { recipientAddress
                                        , resetUrl = appBaseUrl <> appendQueryParams (pathTo NewPasswordResetAction) [("token", rawToken)]
                                        , fromAddress = settings.mailFromAddress
                                        , replyToAddress = settings.mailReplyToAddress
                                        , supportEmail = settings.mailSupportEmail
                                        , initiatedByAccountHolder = token.requestedByUserId == Just token.userId
                                        }

loadPasskeySetupMail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO AccountSecurityMailProjection
loadPasskeySetupMail recipientAccountId recipientAddress tokenId maybeVenueId settings appBaseUrl = do
    maybeToken <- fetchOneOrNothing (Id tokenId :: Id PasskeySetupToken)
    case maybeToken of
        Nothing -> pure (AccountSecurityMailSkipped "domain_reference_missing")
        Just token
            | maybeVenueId /= token.venueId -> pure (AccountSecurityMailSkipped "venue_reference_mismatch")
            | otherwise -> do
                eligibility <- accountAndTokenEligibility recipientAccountId recipientAddress token.userId token.sentToEmail token.consumedAt token.expiresAt
                let maybePurpose = passkeySetupTokenPurposeFromText token.purpose
                authorityIsCurrent <- passkeySetupTokenAuthorityIsCurrent token
                case eligibility <|> (if authorityIsCurrent then Nothing else Just "recipient_authority_obsolete") of
                    Just reason -> pure (AccountSecurityMailSkipped reason)
                    Nothing -> case maybePurpose of
                        Nothing -> pure (AccountSecurityMailSkipped "invalid_passkey_setup_purpose")
                        Just purpose ->
                            projectEncryptedToken token.deliveryTokenCiphertext \rawToken ->
                                AccountSecurityMailReady $
                                    PasskeySetupDelivery
                                        PasskeySetupLinkMail
                                            { recipientAddress
                                            , setupUrl = appBaseUrl <> appendQueryParams (pathTo NewPasskeySetupAction) [("token", rawToken)]
                                            , fromAddress = settings.mailFromAddress
                                            , replyToAddress = settings.mailReplyToAddress
                                            , supportEmail = settings.mailSupportEmail
                                            , purposeLabel = passkeySetupTokenPurposeEmailLabel purpose
                                            }

accountAndTokenEligibility ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Text ->
    Maybe UTCTime ->
    UTCTime ->
    IO (Maybe Text)
accountAndTokenEligibility recipientAccountId recipientAddress userId sentToEmail consumedAt expiresAt = do
    now <- getCurrentTime
    if recipientAccountId /= userId
        then pure (Just "recipient_account_mismatch")
        else if recipientAddress /= sentToEmail
            then pure (Just "recipient_snapshot_mismatch")
            else if isJust consumedAt
                then pure (Just "token_consumed")
                else if expiresAt <= now
                    then pure (Just "token_expired")
                    else do
                        maybeUser <- fetchOneOrNothing (Id userId :: Id User)
                        pure case maybeUser of
                            Nothing -> Just "recipient_account_missing"
                            Just user
                                | isJust user.deactivatedAt -> Just "recipient_account_deactivated"
                                | user.email /= sentToEmail -> Just "recipient_email_changed"
                                | otherwise -> Nothing

fetchEligibleAccountSecurityRecipient ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    IO (Maybe User)
fetchEligibleAccountSecurityRecipient userId sentToEmail =
    query @User
        |> filterWhere (#id, Id userId)
        |> filterWhere (#deactivatedAt, Nothing)
        |> filterWhere (#email, sentToEmail)
        |> fetchOneOrNothing

passwordResetTokenAuthorityIsCurrent ::
    (?modelContext :: ModelContext) =>
    PasswordResetToken ->
    IO Bool
passwordResetTokenAuthorityIsCurrent token
    | token.requestedByUserId == Just token.userId =
        selfPasswordResetAuthorityIsCurrent token.userId token.venueId
    | otherwise =
        staffCredentialAuthorityIsCurrent token.userId token.requestedByUserId token.venueId

selfPasswordResetAuthorityIsCurrent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    IO Bool
selfPasswordResetAuthorityIsCurrent userId venueId = do
    maybeUser <- fetchOneOrNothing (Id userId :: Id User)
    venueIsActive <- query @Venue
        |> filterWhere (#id, Id venueId)
        |> filterWhere (#closedAt, Nothing)
        |> fetchExists
    membershipIsActive <- activeVenueMembershipExists venueId userId Nothing
    pure case maybeUser of
        Just user -> isNothing user.deactivatedAt && user.platformRole /= Just SuperAdmin && venueIsActive && membershipIsActive
        Nothing   -> False

passkeySetupTokenAuthorityIsCurrent ::
    (?modelContext :: ModelContext) =>
    PasskeySetupToken ->
    IO Bool
passkeySetupTokenAuthorityIsCurrent token =
    case passkeySetupTokenPurposeFromText token.purpose of
        Just SelfNewDevicePasskeySetup -> pure (token.requestedByUserId == Just token.userId)
        Just _ -> maybe (pure False) (staffCredentialAuthorityIsCurrent token.userId token.requestedByUserId) token.venueId
        Nothing -> pure False

staffCredentialAuthorityIsCurrent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Maybe UUID ->
    UUID ->
    IO Bool
staffCredentialAuthorityIsCurrent targetUserId maybeRequesterId venueId = do
    venueIsActive <-
        query @Venue
            |> filterWhere (#id, Id venueId)
            |> filterWhere (#closedAt, Nothing)
            |> fetchExists
    targetIsCurrent <- activeVenueMembershipExists venueId targetUserId Nothing
    requesterIsCurrent <- case maybeRequesterId of
        Nothing -> pure False
        Just requesterId -> do
            maybeRequester <- fetchOneOrNothing (Id requesterId :: Id User)
            case maybeRequester of
                Just requester
                    | isNothing requester.deactivatedAt && requester.platformRole == Just SuperAdmin -> pure True
                    | isNothing requester.deactivatedAt -> activeVenueMembershipExists venueId requesterId (Just [VenueAdmin, VenueOwner])
                _ -> pure False
    pure (venueIsActive && targetIsCurrent && requesterIsCurrent)

activeVenueMembershipExists ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    Maybe [VenueRoleEnum] ->
    IO Bool
activeVenueMembershipExists venueId userId maybeRoles = do
    let baseQuery =
            query @VenueMembership
                |> filterWhere (#venueId, venueId)
                |> filterWhere (#userId, userId)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
    case maybeRoles of
        Nothing -> baseQuery |> fetchExists
        Just roles -> baseQuery |> filterWhereIn (#venueRole, roles) |> fetchExists

projectEncryptedToken ::
    Maybe Text ->
    (Text -> AccountSecurityMailProjection) ->
    IO AccountSecurityMailProjection
projectEncryptedToken maybeCiphertext buildProjection =
    case maybeCiphertext of
        Nothing -> pure (AccountSecurityMailSkipped "delivery_secret_unavailable")
        Just ciphertext ->
            decryptAccountSecurityDeliveryToken ciphertext >>= \case
                Left _ -> pure (AccountSecurityMailSkipped "delivery_secret_unavailable")
                Right rawToken -> pure (buildProjection rawToken)

completeAccountSecurityEmail ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    IO ()
completeAccountSecurityEmail mailKind tokenId
    | mailKind == passwordResetMailKind =
        clearPasswordResetDeliverySecret tokenId
    | mailKind == passkeySetupMailKind =
        clearPasskeySetupDeliverySecret tokenId
    | otherwise = pure ()

clearPasswordResetDeliverySecret :: (?modelContext :: ModelContext) => UUID -> IO ()
clearPasswordResetDeliverySecret tokenId = do
    maybeToken <- fetchOneOrNothing (Id tokenId :: Id PasswordResetToken)
    forM_ maybeToken \token ->
        token
            |> set #deliveryTokenCiphertext Nothing
            |> updateRecordDiscardResult

clearPasskeySetupDeliverySecret :: (?modelContext :: ModelContext) => UUID -> IO ()
clearPasskeySetupDeliverySecret tokenId = do
    maybeToken <- fetchOneOrNothing (Id tokenId :: Id PasskeySetupToken)
    forM_ maybeToken \token ->
        token
            |> set #deliveryTokenCiphertext Nothing
            |> updateRecordDiscardResult
