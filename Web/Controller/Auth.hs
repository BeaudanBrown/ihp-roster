module Web.Controller.Auth where

import Application.AccountSecurityEmail.Email (fetchEligibleAccountSecurityRecipient,
                                               passkeySetupTokenAuthorityIsCurrent)
import Application.AccountSecurityEmail.Mutations (withPasskeySetupTokenLock)
import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import qualified Application.Helper.FrontendContract.Wire.Passkey as PasskeyWire
import Application.Helper.PasskeyRecoveryCodes (issueInitialRecoveryCodeIfMissing)
import Application.Helper.Passkeys
import Application.Helper.PasskeySetupTokens
import Application.Helper.Url (appendQueryParams)
import Control.Monad (void)
import qualified Crypto.WebAuthn.Encoding.WebAuthnJson as WebAuthnJson
import Crypto.WebAuthn.Model.Types
import Crypto.WebAuthn.Operation.Authentication
import Crypto.WebAuthn.Operation.CredentialEntry (CredentialEntry (..))
import Crypto.WebAuthn.Operation.Registration
import qualified Data.Aeson as Aeson
import Data.Hourglass (timeConvert)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as Text
import Data.Time.Clock (getCurrentTime)
import qualified Data.UUID as UUID
import qualified Data.Validation as Validation
import Database.PostgreSQL.Simple.Types (Binary (Binary))
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Network.HTTP.Types.Status (Status, status400, status403, status409,
                                  status422)
import Web.Controller.Prelude
import Web.Controller.Sessions ()
import Web.View.Passkeys.NewSetup

instance Controller AuthController where
    beforeAction = bepisBeforeAction BepisPublicController do
        annotateTelemetryAction
        accessDeniedUnless (not currentUserIsImpersonating)

    action currentAction@BeginPasskeyRegistrationAction = runBepis currentAction BepisMutationAction do
        ensureIsUser
        existingPasskeys <-
            query @Passkey
                |> filterWhere (#userId, unpackId (get #id currentUser))
                |> fetch
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        when (strongAuthenticationRequired && not (null existingPasskeys)) do
            verified <- isCurrentUserPasskeyVerified
            recoveryVerified <- isCurrentUserPasskeyRecoveryVerified
            unless (verified || recoveryVerified) do
                setSession passkeyStepUpRedirectSessionKey passkeyManagementPath
                jsonRedirectError status403 "Verify with your passkey before adding another passkey." (pathTo PasskeyStepUpAction)
        challenge <- liftIO generateChallenge
        setSession registrationChallengeSessionKey (unChallenge challenge)
        setSession registrationUserIdSessionKey (inputValue (get #id currentUser))

        renderJson $
            PasskeyWire.registrationOptionsWire $
                registrationCredentialOptions
                    challenge
                    (get #id currentUser)
                    currentUser.email
                    (map passkeyCredentialDescriptor existingPasskeys)

    action currentAction@FinishPasskeyRegistrationAction = runBepis currentAction BepisMutationAction do
        ensureIsUser
        challenge <- sessionChallenge registrationChallengeSessionKey
        pendingUserId <- sessionUserId registrationUserIdSessionKey
        when (pendingUserId /= get #id currentUser) do
            clearRegistrationSession
            jsonError status422 "The pending passkey registration is invalid."

        registrationRequest <- parseWebAuthnJsonBody @PasskeyWire.PasskeyRegistrationRequest
        passkeyName <- normalizeSubmittedPasskeyName (PasskeyWire.passkeyRegistrationName registrationRequest)
        credential <- case WebAuthnJson.wjDecodeCredentialRegistration (PasskeyWire.passkeyRegistrationCredential registrationRequest) of
            Left errorMessage -> do
                clearRegistrationSession
                jsonError status422 errorMessage
            Right credential -> pure credential

        existingPasskeys <-
            query @Passkey
                |> filterWhere (#userId, unpackId (get #id currentUser))
                |> fetch
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        when (strongAuthenticationRequired && not (null existingPasskeys)) do
            verified <- isCurrentUserPasskeyVerified
            recoveryVerified <- isCurrentUserPasskeyRecoveryVerified
            unless (verified || recoveryVerified) do
                clearRegistrationSession
                setSession passkeyStepUpRedirectSessionKey passkeyManagementPath
                jsonRedirectError status403 "Verify with your passkey before adding another passkey." (pathTo PasskeyStepUpAction)
        currentDateTime <- liftIO (timeConvert <$> getCurrentTime)
        let verification =
                verifyRegistrationResponse
                    allowedOrigins
                    rpIdHashFromRequest
                    mempty
                    currentDateTime
                    (registrationCredentialOptions challenge (get #id currentUser) currentUser.email (map passkeyCredentialDescriptor existingPasskeys))
                    credential

        clearRegistrationSession
        registrationResult <- case verification of
            Validation.Failure errors -> jsonError status422 (validationErrors errors)
            Validation.Success result -> pure result

        let entry = rrEntry registrationResult
            credentialId = unCredentialId (get #ceCredentialId entry)

        credentialAlreadyExists <-
            query @Passkey
                |> filterWhere (#credentialId, Binary credentialId)
                |> fetchExists
        when credentialAlreadyExists do
            jsonError status409 "This passkey is already registered."

        _ <- createPasskeyRecord (get #id currentUser) passkeyName entry
        recoveryCode <-
            if strongAuthenticationRequired && null existingPasskeys
                then issueInitialRecoveryCodeIfMissing (get #id currentUser)
                else pure Nothing
        clearCurrentUserPasskeyRecoveryVerification
        markCurrentUserPasskeyVerified
        renderJson
            ( PasskeyWire.PasskeyRegistered
                (unpackId (get #id currentUser))
                recoveryCode
            )

    action currentAction@BeginPasskeyAuthenticationAction = runBepis currentAction BepisMutationAction do
        challenge <- liftIO generateChallenge
        setSession authenticationChallengeSessionKey (unChallenge challenge)
        renderJson $
            PasskeyWire.authenticationOptionsWire $
                authenticationCredentialOptions challenge

    action currentAction@FinishPasskeyAuthenticationAction = runBepis currentAction BepisMutationAction do
        challenge <- sessionChallenge authenticationChallengeSessionKey
        credentialPayload <- parseWebAuthnJsonBody @PasskeyWire.PasskeyAuthenticationRequest
        credential <- case WebAuthnJson.wjDecodeCredentialAuthentication (PasskeyWire.passkeyAuthenticationCredential credentialPayload) of
            Left errorMessage -> do
                clearAuthenticationSession
                jsonError status422 errorMessage
            Right credential -> pure credential

        clearAuthenticationSession

        let CredentialId credentialId = cIdentifier credential
        passkey <-
            query @Passkey
                |> filterWhere (#credentialId, Binary credentialId)
                |> fetchOneOrNothing
                >>= maybe (jsonError status422 "No account matched that passkey.") pure
        user <- fetch (Id passkey.userId :: Id User)

        let verification =
                verifyAuthenticationResponse
                    allowedOrigins
                    rpIdHashFromRequest
                    Nothing
                    (credentialEntryForPasskey passkey)
                    (authenticationCredentialOptions challenge)
                    credential

        authenticationResult <- case verification of
            Validation.Failure errors -> jsonError status422 (validationErrors errors)
            Validation.Success result -> pure result

        case arSignatureCounterResult authenticationResult of
            SignatureCounterPotentiallyCloned -> pure ()
            SignatureCounterUpdated newSignCount ->
                passkey
                    |> set #signCount (fromIntegral (unSignatureCounter newSignCount))
                    |> updateRecordDiscardResult
            SignatureCounterZero -> pure ()

        Sessions.beforeLogin user
        LoginSupport.login user
        markUserPasskeyVerified user.id
        now <- getCurrentTime
        passkey
            |> set #lastUsedAt (Just now)
            |> updateRecordDiscardResult
        _ <-
            recordUserAuthenticationAuditEvent
                user
                LoginSucceededAudit
                ( Aeson.object
                    [ "authMethod" Aeson..= ("passkey" :: Text)
                    , "email" Aeson..= user.email
                    , "passkeyId" Aeson..= inputValue (get #id passkey)
                    ]
                )
        redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
        renderJson
            ( PasskeyWire.PasskeyAuthenticated
                (unpackId (get #id user))
                (fromMaybe (Sessions.afterLoginRedirectPath @User) redirectUrl)
            )

    action currentAction@BeginPasskeyStepUpAuthenticationAction = runBepis currentAction BepisMutationAction do
        ensureIsUser
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            auditPasskeyStepUpFailure "no_passkey"
            jsonError status422 "Add a passkey before verifying privileged access."
        challenge <- liftIO generateChallenge
        setSession stepUpAuthenticationChallengeSessionKey (unChallenge challenge)
        renderJson $
            PasskeyWire.authenticationOptionsWire $
                authenticationCredentialOptionsForPasskeys challenge passkeys

    action currentAction@FinishPasskeyStepUpAuthenticationAction = runBepis currentAction BepisMutationAction do
        ensureIsUser
        challenge <- sessionChallenge stepUpAuthenticationChallengeSessionKey
        credentialPayload <- parseWebAuthnJsonBody @PasskeyWire.PasskeyAuthenticationRequest
        credential <- case WebAuthnJson.wjDecodeCredentialAuthentication (PasskeyWire.passkeyAuthenticationCredential credentialPayload) of
            Left errorMessage -> do
                clearStepUpAuthenticationSession
                auditPasskeyStepUpFailure "decode_failed"
                jsonError status422 errorMessage
            Right credential -> pure credential

        clearStepUpAuthenticationSession

        let CredentialId credentialId = cIdentifier credential
        passkey <-
            query @Passkey
                |> filterWhere (#credentialId, Binary credentialId)
                |> fetchOneOrNothing
                >>= \case
                    Nothing -> do
                        auditPasskeyStepUpFailure "credential_not_found"
                        jsonError status422 "No account matched that passkey."
                    Just passkey -> pure passkey
        when (passkey.userId /= unpackId currentUser.id) do
            auditPasskeyStepUpFailure "wrong_account"
            jsonError status422 "That passkey belongs to a different account."

        let verification =
                verifyAuthenticationResponse
                    allowedOrigins
                    rpIdHashFromRequest
                    (Just (userHandleForUserId currentUser.id))
                    (credentialEntryForPasskey passkey)
                    (authenticationCredentialOptionsForPasskeys challenge [passkey])
                    credential

        authenticationResult <- case verification of
            Validation.Failure errors -> do
                auditPasskeyStepUpFailure "verification_failed"
                jsonError status422 (validationErrors errors)
            Validation.Success result -> pure result

        case arSignatureCounterResult authenticationResult of
            SignatureCounterPotentiallyCloned -> pure ()
            SignatureCounterUpdated newSignCount ->
                passkey
                    |> set #signCount (fromIntegral (unSignatureCounter newSignCount))
                    |> updateRecordDiscardResult
            SignatureCounterZero -> pure ()

        now <- getCurrentTime
        passkey
            |> set #lastUsedAt (Just now)
            |> updateRecordDiscardResult
        markCurrentUserPasskeyVerified
        void $
            recordUserAuthenticationAuditEvent
                currentUser
                PasskeyStepUpSucceededAudit
                ( Aeson.object
                    [ "authMethod" Aeson..= ("passkey" :: Text)
                    , "passkeyId" Aeson..= inputValue (get #id passkey)
                    ]
                )
        redirectUrl <- getSessionAndClear passkeyStepUpRedirectSessionKey
        let safeRedirectUrl = redirectUrl >>= safePasskeyReturnPath
        renderJson
            ( PasskeyWire.PasskeyAuthenticated
                (unpackId currentUser.id)
                (fromMaybe (Sessions.afterLoginRedirectPath @User) safeRedirectUrl)
            )

    action currentAction@NewPasskeySetupAction = runBepis currentAction BepisFormAction do
        rawToken <- setupTokenParamOrRedirect
        setupToken <- findActivePasskeySetupToken rawToken >>= maybe invalidSetupLink pure
        targetUser <- fetchEligiblePasskeySetupTarget setupToken >>= maybe invalidSetupLink pure
        let targetEmail = targetUser.email
        let beginUrl = appendQueryParams (pathTo BeginPasskeySetupRegistrationAction) [("token", rawToken)]
        render NewSetupView { .. }

    action currentAction@BeginPasskeySetupRegistrationAction = runBepis currentAction BepisMutationAction do
        rawToken <- setupTokenParamOrJsonError
        setupToken <- findActivePasskeySetupToken rawToken >>= maybe (jsonError status422 "This passkey setup link is invalid or has expired.") pure
        targetUser <- fetchEligiblePasskeySetupTarget setupToken >>= maybe (jsonError status422 "This passkey setup link is invalid or has expired.") pure
        existingPasskeys <- fetchPasskeysForUser targetUser.id
        challenge <- liftIO generateChallenge
        setSession setupRegistrationChallengeSessionKey (unChallenge challenge)
        setSession setupRegistrationTokenIdSessionKey (inputValue setupToken.id)
        setSession setupRegistrationUserIdSessionKey (inputValue targetUser.id)

        renderJson $
            PasskeyWire.registrationOptionsWire $
                registrationCredentialOptions
                    challenge
                    targetUser.id
                    targetUser.email
                    (map passkeyCredentialDescriptor existingPasskeys)

    action currentAction@FinishPasskeySetupRegistrationAction = runBepis currentAction BepisMutationAction do
        challenge <- sessionChallenge setupRegistrationChallengeSessionKey
        setupTokenId <- sessionPasskeySetupTokenId setupRegistrationTokenIdSessionKey
        pendingUserId <- sessionUserId setupRegistrationUserIdSessionKey
        setupToken <- activeSetupTokenById setupTokenId >>= maybe (jsonError status422 "This passkey setup link is invalid or has expired.") pure
        when (pendingUserId /= Id setupToken.userId) do
            clearSetupRegistrationSession
            jsonError status422 "The pending passkey setup is invalid."

        targetUser <- fetchEligiblePasskeySetupTarget setupToken >>= maybe (jsonError status422 "This passkey setup link is invalid or has expired.") pure
        registrationRequest <- parseWebAuthnJsonBody @PasskeyWire.PasskeyRegistrationRequest
        passkeyName <- normalizeSubmittedPasskeyName (PasskeyWire.passkeyRegistrationName registrationRequest)
        credential <- case WebAuthnJson.wjDecodeCredentialRegistration (PasskeyWire.passkeyRegistrationCredential registrationRequest) of
            Left errorMessage -> do
                clearSetupRegistrationSession
                jsonError status422 errorMessage
            Right credential -> pure credential
        existingPasskeys <- fetchPasskeysForUser targetUser.id
        currentDateTime <- liftIO (timeConvert <$> getCurrentTime)
        let verification =
                verifyRegistrationResponse
                    allowedOrigins
                    rpIdHashFromRequest
                    mempty
                    currentDateTime
                    (registrationCredentialOptions challenge targetUser.id targetUser.email (map passkeyCredentialDescriptor existingPasskeys))
                    credential

        clearSetupRegistrationSession
        registrationResult <- case verification of
            Validation.Failure errors -> jsonError status422 (validationErrors errors)
            Validation.Success result -> pure result

        let entry = rrEntry registrationResult
            credentialId = unCredentialId (get #ceCredentialId entry)
        maybeCompleted <- withPasskeySetupTokenLock (unpackId setupTokenId) do
            lockedToken <- activeSetupTokenById setupTokenId
            case lockedToken of
                Just activeToken
                    | pendingUserId == Id activeToken.userId -> do
                        maybeEligibleUser <- fetchEligiblePasskeySetupTarget activeToken
                        when (isNothing maybeEligibleUser) do
                            jsonError status422 "This passkey setup link is invalid or has expired."
                        credentialAlreadyExists <-
                            query @Passkey
                                |> filterWhere (#credentialId, Binary credentialId)
                                |> fetchExists
                        when credentialAlreadyExists do
                            jsonError status409 "This passkey is already registered."
                        _ <- createPasskeyRecord targetUser.id passkeyName entry
                        now <- getCurrentTime
                        activeToken
                            |> set #consumedAt (Just now)
                            |> set #deliveryTokenCiphertext Nothing
                            |> updateRecordDiscardResult
                        pure True
                _ -> pure False
        if fromMaybe False maybeCompleted
            then
                renderJson
                    ( PasskeyWire.PasskeySetupRegistered
                        (unpackId targetUser.id)
                        (pathTo NewSessionAction)
                    )
            else jsonError status422 "This passkey setup link is invalid or has expired."

registrationChallengeSessionKey :: ByteString
registrationChallengeSessionKey = "passkey-registration-challenge"

registrationUserIdSessionKey :: ByteString
registrationUserIdSessionKey = "passkey-registration-user-id"

authenticationChallengeSessionKey :: ByteString
authenticationChallengeSessionKey = "passkey-authentication-challenge"

stepUpAuthenticationChallengeSessionKey :: ByteString
stepUpAuthenticationChallengeSessionKey = "passkey-step-up-authentication-challenge"

setupRegistrationChallengeSessionKey :: ByteString
setupRegistrationChallengeSessionKey = "passkey-setup-registration-challenge"

setupRegistrationTokenIdSessionKey :: ByteString
setupRegistrationTokenIdSessionKey = "passkey-setup-registration-token-id"

setupRegistrationUserIdSessionKey :: ByteString
setupRegistrationUserIdSessionKey = "passkey-setup-registration-user-id"

parseWebAuthnJsonBody ::
    (?request :: Request, Aeson.FromJSON payload) =>
    IO payload
parseWebAuthnJsonBody = do
    jsonValue <- requestBodyJSON
    case Aeson.fromJSON jsonValue of
        Aeson.Error errorMessage -> jsonError status400 (cs errorMessage)
        Aeson.Success payload    -> pure payload

sessionChallenge :: (?request :: Request) => ByteString -> IO Challenge
sessionChallenge sessionKey =
    getSession @ByteString sessionKey >>= \case
        Just challenge -> pure (Challenge challenge)
        Nothing -> jsonError status422 "This passkey request has expired. Please try again."

sessionUserId :: (?request :: Request) => ByteString -> IO (Id User)
sessionUserId sessionKey =
    getSession @Text sessionKey >>= \case
        Just userIdText ->
            case UUID.fromText userIdText of
                Just userId -> pure (Id userId)
                Nothing -> jsonError status422 "The pending passkey registration is invalid."
        Nothing -> jsonError status422 "This passkey request has expired. Please try again."

sessionPasskeySetupTokenId :: (?request :: Request) => ByteString -> IO (Id PasskeySetupToken)
sessionPasskeySetupTokenId sessionKey =
    getSession @Text sessionKey >>= \case
        Just tokenIdText ->
            case UUID.fromText tokenIdText of
                Just tokenId -> pure (Id tokenId)
                Nothing -> jsonError status422 "The pending passkey setup is invalid."
        Nothing -> jsonError status422 "This passkey setup request has expired. Please try again."

setupTokenParamOrRedirect :: (?request :: Request) => IO Text
setupTokenParamOrRedirect =
    maybe invalidSetupLink pure (paramOrNothing @Text "token")

setupTokenParamOrJsonError :: (?request :: Request) => IO Text
setupTokenParamOrJsonError =
    maybe (jsonError status422 "This passkey setup link is invalid or has expired.") pure (paramOrNothing @Text "token")

invalidSetupLink :: (?request :: Request) => IO a
invalidSetupLink =
    terminateAfterIhpResponseControl do
        setErrorMessage "This passkey setup link is invalid or has expired."
        redirectTo NewSessionAction

fetchPasskeysForUser :: (?modelContext :: ModelContext) => Id User -> IO [Passkey]
fetchPasskeysForUser userId =
    query @Passkey
        |> filterWhere (#userId, unpackId userId)
        |> fetch

fetchEligiblePasskeySetupTarget ::
    (?modelContext :: ModelContext) =>
    PasskeySetupToken ->
    IO (Maybe User)
fetchEligiblePasskeySetupTarget setupToken = do
    maybeUser <- fetchEligibleAccountSecurityRecipient setupToken.userId setupToken.sentToEmail
    authorityIsCurrent <- passkeySetupTokenAuthorityIsCurrent setupToken
    pure (if authorityIsCurrent then maybeUser else Nothing)

activeSetupTokenById :: (?modelContext :: ModelContext) => Id PasskeySetupToken -> IO (Maybe PasskeySetupToken)
activeSetupTokenById setupTokenId =
    query @PasskeySetupToken
        |> filterWhere (#id, setupTokenId)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

normalizeSubmittedPasskeyName :: (?request :: Request) => Maybe Text -> IO Text
normalizeSubmittedPasskeyName maybeName = do
    let submittedName = maybe "Passkey" Text.strip maybeName
        normalizedName = if Text.null submittedName then "Passkey" else submittedName
    when (Text.length normalizedName > 120) do
        jsonError status422 "Passkey name must be 120 characters or fewer."
    pure normalizedName

createPasskeyRecord ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Text ->
    CredentialEntry ->
    IO Passkey
createPasskeyRecord userId passkeyName entry =
    newRecord @Passkey
        |> set #userId (unpackId userId)
        |> set #credentialId (Binary (unCredentialId entry.ceCredentialId))
        |> set #publicKey (Binary (unPublicKeyBytes entry.cePublicKeyBytes))
        |> set #signCount (fromIntegral (unSignatureCounter entry.ceSignCounter))
        |> set #name passkeyName
        |> createRecord

clearRegistrationSession :: (?request :: Request) => IO ()
clearRegistrationSession = do
    deleteSession registrationChallengeSessionKey
    deleteSession registrationUserIdSessionKey

clearAuthenticationSession :: (?request :: Request) => IO ()
clearAuthenticationSession =
    deleteSession authenticationChallengeSessionKey

clearStepUpAuthenticationSession :: (?request :: Request) => IO ()
clearStepUpAuthenticationSession =
    deleteSession stepUpAuthenticationChallengeSessionKey

clearSetupRegistrationSession :: (?request :: Request) => IO ()
clearSetupRegistrationSession = do
    deleteSession setupRegistrationChallengeSessionKey
    deleteSession setupRegistrationTokenIdSessionKey
    deleteSession setupRegistrationUserIdSessionKey

jsonError :: (?request :: Request) => Status -> Text -> IO a
jsonError statusCode errorMessage =
    terminateAfterIhpResponseControl $
        renderJsonWithStatusCode statusCode (PasskeyWire.PasskeyFailure errorMessage)

jsonRedirectError :: (?request :: Request) => Status -> Text -> Text -> IO a
jsonRedirectError statusCode errorMessage redirectTo =
    terminateAfterIhpResponseControl $
        renderJsonWithStatusCode statusCode
            (PasskeyWire.PasskeyRedirectFailure errorMessage redirectTo)

auditPasskeyStepUpFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO ()
auditPasskeyStepUpFailure reason =
    void $
        recordUserAuthenticationAuditEvent
            currentUser
            PasskeyStepUpFailedAudit
            ( Aeson.object
                [ "authMethod" Aeson..= ("passkey" :: Text)
                , "reason" Aeson..= reason
                ]
            )

validationErrors :: Show problem => NonEmpty.NonEmpty problem -> Text
validationErrors problems =
    Text.intercalate "; " (map (cs . show) (NonEmpty.toList problems))
