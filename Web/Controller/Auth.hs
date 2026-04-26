module Web.Controller.Auth where

import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import Application.Helper.Passkeys
import qualified Crypto.WebAuthn.Encoding.WebAuthnJson as WebAuthnJson
import Crypto.WebAuthn.Model.Types
import Crypto.WebAuthn.Operation.Authentication
import Crypto.WebAuthn.Operation.CredentialEntry (CredentialEntry (..))
import Crypto.WebAuthn.Operation.Registration
import Control.Monad (void)
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

instance Controller AuthController where
    action BeginPasskeyRegistrationAction = do
        ensureIsUser
        existingPasskeys <-
            query @Passkey
                |> filterWhere (#userId, unpackId (get #id currentUser))
                |> fetch
        when (currentUserRequiresMandatoryPasskey && not (null existingPasskeys)) do
            verified <- isCurrentUserPasskeyVerified
            unless verified do
                setSession passkeyStepUpRedirectSessionKey profileSecurityPath
                jsonRedirectError status403 "Verify with your passkey before adding another passkey." (pathTo PasskeyStepUpAction)
        challenge <- liftIO generateChallenge
        setSession registrationChallengeSessionKey (unChallenge challenge)
        setSession registrationUserIdSessionKey (inputValue (get #id currentUser))

        renderJson $
            WebAuthnJson.wjEncodeCredentialOptionsRegistration $
                registrationCredentialOptions
                    challenge
                    (get #id currentUser)
                    currentUser.email
                    (map passkeyCredentialDescriptor existingPasskeys)

    action FinishPasskeyRegistrationAction = do
        ensureIsUser
        challenge <- sessionChallenge registrationChallengeSessionKey
        pendingUserId <- sessionUserId registrationUserIdSessionKey
        when (pendingUserId /= get #id currentUser) do
            clearRegistrationSession
            jsonError status422 "The pending passkey registration is invalid."

        credentialPayload <- parseWebAuthnJsonBody @WebAuthnJson.WJCredentialRegistration
        credential <- case WebAuthnJson.wjDecodeCredentialRegistration credentialPayload of
            Left errorMessage -> do
                clearRegistrationSession
                jsonError status422 errorMessage
            Right credential -> pure credential

        existingPasskeys <-
            query @Passkey
                |> filterWhere (#userId, unpackId (get #id currentUser))
                |> fetch
        when (currentUserRequiresMandatoryPasskey && not (null existingPasskeys)) do
            verified <- isCurrentUserPasskeyVerified
            unless verified do
                clearRegistrationSession
                setSession passkeyStepUpRedirectSessionKey profileSecurityPath
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

        _ <- createPasskeyRecord (get #id currentUser) entry
        markCurrentUserPasskeyVerified
        renderJson
            ( Aeson.object
                [ "ok" Aeson..= True
                , "message" Aeson..= ("Passkey added." :: Text)
                , "userId" Aeson..= inputValue (get #id currentUser)
                ]
            )

    action BeginPasskeyAuthenticationAction = do
        challenge <- liftIO generateChallenge
        setSession authenticationChallengeSessionKey (unChallenge challenge)
        renderJson $
            WebAuthnJson.wjEncodeCredentialOptionsAuthentication $
                authenticationCredentialOptions challenge

    action FinishPasskeyAuthenticationAction = do
        challenge <- sessionChallenge authenticationChallengeSessionKey
        credentialPayload <- parseWebAuthnJsonBody @WebAuthnJson.WJCredentialAuthentication
        credential <- case WebAuthnJson.wjDecodeCredentialAuthentication credentialPayload of
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
                "login_succeeded"
                ( Aeson.object
                    [ "authMethod" Aeson..= ("passkey" :: Text)
                    , "email" Aeson..= user.email
                    , "passkeyId" Aeson..= inputValue (get #id passkey)
                    ]
                )
        redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
        renderJson
            ( Aeson.object
                [ "ok" Aeson..= True
                , "redirectTo" Aeson..= fromMaybe (Sessions.afterLoginRedirectPath @User) redirectUrl
                , "userId" Aeson..= inputValue (get #id user)
                ]
            )

    action BeginPasskeyStepUpAuthenticationAction = do
        ensureIsUser
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            auditPasskeyStepUpFailure "no_passkey"
            jsonError status422 "Add a passkey before verifying privileged access."
        challenge <- liftIO generateChallenge
        setSession stepUpAuthenticationChallengeSessionKey (unChallenge challenge)
        renderJson $
            WebAuthnJson.wjEncodeCredentialOptionsAuthentication $
                authenticationCredentialOptionsForPasskeys challenge passkeys

    action FinishPasskeyStepUpAuthenticationAction = do
        ensureIsUser
        challenge <- sessionChallenge stepUpAuthenticationChallengeSessionKey
        credentialPayload <- parseWebAuthnJsonBody @WebAuthnJson.WJCredentialAuthentication
        credential <- case WebAuthnJson.wjDecodeCredentialAuthentication credentialPayload of
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
                "passkey_step_up_succeeded"
                ( Aeson.object
                    [ "authMethod" Aeson..= ("passkey" :: Text)
                    , "passkeyId" Aeson..= inputValue (get #id passkey)
                    ]
                )
        redirectUrl <- getSessionAndClear passkeyStepUpRedirectSessionKey
        renderJson
            ( Aeson.object
                [ "ok" Aeson..= True
                , "redirectTo" Aeson..= fromMaybe (Sessions.afterLoginRedirectPath @User) redirectUrl
                , "userId" Aeson..= inputValue currentUser.id
                ]
            )

registrationChallengeSessionKey :: ByteString
registrationChallengeSessionKey = "passkey-registration-challenge"

registrationUserIdSessionKey :: ByteString
registrationUserIdSessionKey = "passkey-registration-user-id"

authenticationChallengeSessionKey :: ByteString
authenticationChallengeSessionKey = "passkey-authentication-challenge"

stepUpAuthenticationChallengeSessionKey :: ByteString
stepUpAuthenticationChallengeSessionKey = "passkey-step-up-authentication-challenge"

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

createPasskeyRecord ::
    (?modelContext :: ModelContext) =>
    Id User ->
    CredentialEntry ->
    IO Passkey
createPasskeyRecord userId entry =
    newRecord @Passkey
        |> set #userId (unpackId userId)
        |> set #credentialId (Binary (unCredentialId entry.ceCredentialId))
        |> set #publicKey (Binary (unPublicKeyBytes entry.cePublicKeyBytes))
        |> set #signCount (fromIntegral (unSignatureCounter entry.ceSignCounter))
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

jsonError :: (?request :: Request) => Status -> Text -> IO a
jsonError statusCode errorMessage =
    renderJsonWithStatusCode statusCode (Aeson.object ["error" Aeson..= errorMessage])
        >> error "unreachable"

jsonRedirectError :: (?request :: Request) => Status -> Text -> Text -> IO a
jsonRedirectError statusCode errorMessage redirectTo =
    renderJsonWithStatusCode statusCode
        (Aeson.object ["error" Aeson..= errorMessage, "redirectTo" Aeson..= redirectTo])
        >> error "unreachable"

auditPasskeyStepUpFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO ()
auditPasskeyStepUpFailure reason =
    void $
        recordUserAuthenticationAuditEvent
            currentUser
            "passkey_step_up_failed"
            ( Aeson.object
                [ "authMethod" Aeson..= ("passkey" :: Text)
                , "reason" Aeson..= reason
                ]
            )

validationErrors :: Show error => NonEmpty.NonEmpty error -> Text
validationErrors errors =
    Text.intercalate "; " (map (cs . show) (NonEmpty.toList errors))
