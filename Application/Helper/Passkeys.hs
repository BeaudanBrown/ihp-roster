{-# LANGUAGE PackageImports #-}

module Application.Helper.Passkeys
    ( allowedOrigins
    , authenticationCredentialOptions
    , credentialEntryForPasskey
    , passkeyCredentialDescriptor
    , passkeyRelyingPartyName
    , registrationCredentialOptions
    , rpIdHashFromRequest
    , rpIdTextFromHost
    , rpIdTextFromRequest
    , userHandleForUserUuid
    , userHandleForUserId
    )
where

import qualified "crypton" Crypto.Hash as Hash
import Crypto.WebAuthn.Cose.SignAlg
import Crypto.WebAuthn.Model.Kinds (CeremonyKind (Authentication, Registration))
import Crypto.WebAuthn.Model.Types
import Crypto.WebAuthn.Operation.CredentialEntry
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import Database.PostgreSQL.Simple.Types (Binary (Binary))
import Generated.Types
import IHP.InputValue (inputValue)
import IHP.Prelude
import Network.Wai (Request)
import qualified Network.Wai as Wai

passkeyRelyingPartyName :: RelyingPartyName
passkeyRelyingPartyName = RelyingPartyName "Bepis"

rpIdTextFromHost :: Text -> Text
rpIdTextFromHost = Text.takeWhile (\char -> char /= ':' && char /= '/')

rpIdTextFromRequest :: (?request :: Request) => Text
rpIdTextFromRequest = rpIdTextFromHost requestHostTextFromWai

rpIdHashFromRequest :: (?request :: Request) => RpIdHash
rpIdHashFromRequest = RpIdHash (Hash.hash (Text.encodeUtf8 rpIdTextFromRequest))

allowedOrigins :: (?request :: Request) => NonEmpty Origin
allowedOrigins = Origin (requestSchemeTextFromWai <> "://" <> requestHostTextFromWai) :| []

requestHostTextFromWai :: (?request :: Request) => Text
requestHostTextFromWai =
    maybe rpId (Text.decodeUtf8) (Wai.requestHeaderHost ?request)
  where
    rpId = "localhost"

requestSchemeTextFromWai :: (?request :: Request) => Text
requestSchemeTextFromWai =
    if Wai.isSecure ?request then "https" else "http"

userHandleForUserId :: Id User -> UserHandle
userHandleForUserId userId = UserHandle (cs (inputValue userId))

userHandleForUserUuid :: UUID.UUID -> UserHandle
userHandleForUserUuid userId = UserHandle (cs (UUID.toText userId))

registrationCredentialOptions ::
    (?request :: Request) =>
    Challenge ->
    Id User ->
    Text ->
    [CredentialDescriptor] ->
    CredentialOptions 'Registration
registrationCredentialOptions challenge userId displayName excludeCredentials =
    CredentialOptionsRegistration
        { corRp =
            CredentialRpEntity
                { creId = Just (RpId rpIdTextFromRequest)
                , creName = passkeyRelyingPartyName
                }
        , corUser =
            CredentialUserEntity
                { cueId = userHandleForUserId userId
                , cueDisplayName = UserAccountDisplayName displayName
                , cueName = UserAccountName displayName
                }
        , corChallenge = challenge
        , corPubKeyCredParams =
            [ CredentialParameters CredentialTypePublicKey (CoseSignAlgECDSA CoseHashAlgECDSASHA256)
            , CredentialParameters CredentialTypePublicKey CoseSignAlgEdDSA
            , CredentialParameters CredentialTypePublicKey (CoseSignAlgRSA CoseHashAlgRSASHA256)
            ]
        , corTimeout = Just (Timeout 60000)
        , corExcludeCredentials = excludeCredentials
        , corAuthenticatorSelection =
            Just
                AuthenticatorSelectionCriteria
                    { ascAuthenticatorAttachment = Nothing
                    , ascResidentKey = ResidentKeyRequirementPreferred
                    , ascUserVerification = UserVerificationRequirementPreferred
                    }
        , corAttestation = AttestationConveyancePreferenceNone
        , corExtensions = Nothing
        }

authenticationCredentialOptions ::
    (?request :: Request) =>
    Challenge ->
    CredentialOptions 'Authentication
authenticationCredentialOptions challenge =
    CredentialOptionsAuthentication
        { coaChallenge = challenge
        , coaTimeout = Just (Timeout 60000)
        , coaRpId = Just (RpId rpIdTextFromRequest)
        , coaAllowCredentials = []
        , coaUserVerification = UserVerificationRequirementPreferred
        , coaExtensions = Nothing
        }

passkeyCredentialDescriptor :: Passkey -> CredentialDescriptor
passkeyCredentialDescriptor Passkey { credentialId = Binary credentialId } =
    CredentialDescriptor
        { cdTyp = CredentialTypePublicKey
        , cdId = CredentialId credentialId
        , cdTransports = Nothing
        }

credentialEntryForPasskey :: Passkey -> CredentialEntry
credentialEntryForPasskey Passkey { userId, credentialId = Binary credentialId, publicKey = Binary publicKey, signCount } =
    CredentialEntry
        { ceCredentialId = CredentialId credentialId
        , ceUserHandle = userHandleForUserUuid userId
        , cePublicKeyBytes = PublicKeyBytes publicKey
        , ceSignCounter = fromIntegral signCount
        , ceTransports = []
        }
