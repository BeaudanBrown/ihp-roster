module Web.Controller.Auth where

import Application.Helper.Audit (recordUserAuthenticationAuditEvent)
import Application.Helper.Passkeys
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
import Network.HTTP.Types.Status (Status, status400, status409, status422)
import Web.Controller.Prelude
import Web.Controller.Sessions ()

instance Controller AuthController where
    action BeginPasskeyRegistrationAction = do
        ensureIsUser
        existingPasskeys <-
            query @Passkey
                |> filterWhere (#userId, unpackId (get #id currentUser))
                |> fetch
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
                    (Just (userHandleForUserId (get #id user)))
                    (credentialEntryForPasskey passkey)
                    (authenticationCredentialOptions challenge)
                    credential

        authenticationResult <- case verification of
            Validation.Failure errors -> jsonError status422 (validationErrors errors)
            Validation.Success result -> pure result

        case arSignatureCounterResult authenticationResult of
            SignatureCounterPotentiallyCloned ->
                jsonError status422 "This passkey could not be verified safely."
            SignatureCounterUpdated newSignCount ->
                passkey
                    |> set #signCount (fromIntegral (unSignatureCounter newSignCount))
                    |> updateRecordDiscardResult
            SignatureCounterZero -> pure ()

        Sessions.beforeLogin user
        LoginSupport.login user
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

registrationChallengeSessionKey :: ByteString
registrationChallengeSessionKey = "passkey-registration-challenge"

registrationUserIdSessionKey :: ByteString
registrationUserIdSessionKey = "passkey-registration-user-id"

authenticationChallengeSessionKey :: ByteString
authenticationChallengeSessionKey = "passkey-authentication-challenge"

parseWebAuthnJsonBody ::
    (?context :: ControllerContext, Aeson.FromJSON payload) =>
    IO payload
parseWebAuthnJsonBody = do
    let jsonValue = requestBodyJSON
    case Aeson.fromJSON jsonValue of
        Aeson.Error errorMessage -> jsonError status400 (cs errorMessage)
        Aeson.Success payload    -> pure payload

sessionChallenge :: (?context :: ControllerContext) => ByteString -> IO Challenge
sessionChallenge sessionKey =
    getSession @ByteString sessionKey >>= \case
        Just challenge -> pure (Challenge challenge)
        Nothing -> jsonError status422 "This passkey request has expired. Please try again."

sessionUserId :: (?context :: ControllerContext) => ByteString -> IO (Id User)
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

clearRegistrationSession :: (?context :: ControllerContext) => IO ()
clearRegistrationSession = do
    deleteSession registrationChallengeSessionKey
    deleteSession registrationUserIdSessionKey

clearAuthenticationSession :: (?context :: ControllerContext) => IO ()
clearAuthenticationSession =
    deleteSession authenticationChallengeSessionKey

jsonError :: (?context :: ControllerContext) => Status -> Text -> IO a
jsonError statusCode errorMessage =
    renderJsonWithStatusCode statusCode (Aeson.object ["error" Aeson..= errorMessage])
        >> error "unreachable"

validationErrors :: Show error => NonEmpty.NonEmpty error -> Text
validationErrors errors =
    Text.intercalate "; " (map (cs . show) (NonEmpty.toList errors))
