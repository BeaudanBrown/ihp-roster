{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE NamedFieldPuns   #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}

module Application.Helper.FrontendContract.Wire.Passkey
    ( PasskeyAuthenticationOptions
    , PasskeyAuthenticationRequest (..)
    , PasskeyErrorResponse (..)
    , PasskeyFinishResponse (..)
    , PasskeyRegistrationOptions
    , PasskeyRegistrationRequest (..)
    , authenticationOptionsWire
    , registrationOptionsWire
    ) where

import qualified Application.Helper.FrontendContract.Passkey as Contract
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Crypto.WebAuthn.Cose.SignAlg as Cose
import qualified Crypto.WebAuthn.Encoding.Internal.WebAuthnJson as WebAuthnWire
import qualified Crypto.WebAuthn.Encoding.Strings as WebAuthnStrings
import qualified Crypto.WebAuthn.Encoding.WebAuthnJson as WebAuthnJson
import Crypto.WebAuthn.Model.Kinds (CeremonyKind (Authentication, Registration))
import Crypto.WebAuthn.Model.Types
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Base64.URL as Base64Url
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.UUID as UUID
import IHP.Prelude

-- Exact begin response carriers ------------------------------------------------

data PasskeyRelyingPartyWire = PasskeyRelyingPartyWire
    { relyingPartyId   :: !Text
    , relyingPartyName :: !Text
    }
    deriving (Eq, Show)

data PasskeyUserEntityWire = PasskeyUserEntityWire
    { userEntityId          :: !Text
    , userEntityDisplayName :: !Text
    , userEntityName        :: !Text
    }
    deriving (Eq, Show)

data PasskeyCredentialParameterWire = PasskeyCredentialParameterWire
    { credentialParameterType      :: !CredentialType
    , credentialParameterAlgorithm :: !Int
    }
    deriving (Eq, Show)

data PasskeyCredentialDescriptorWire = PasskeyCredentialDescriptorWire
    { credentialDescriptorType :: !CredentialType
    , credentialDescriptorId   :: !Text
    }
    deriving (Eq, Show)

data PasskeyAuthenticatorSelectionWire = PasskeyAuthenticatorSelectionWire
    { selectionAuthenticatorAttachment :: !(Maybe AuthenticatorAttachment)
    , selectionResidentKey             :: !ResidentKeyRequirement
    , selectionRequireResidentKey      :: !Bool
    , selectionUserVerification        :: !UserVerificationRequirement
    }
    deriving (Eq, Show)

data PasskeyRegistrationOptions = PasskeyRegistrationOptions
    { registrationOptionsRelyingParty          :: !PasskeyRelyingPartyWire
    , registrationOptionsUser                  :: !PasskeyUserEntityWire
    , registrationOptionsChallenge             :: !Text
    , registrationOptionsParameters            :: ![PasskeyCredentialParameterWire]
    , registrationOptionsTimeout               :: !Int
    , registrationOptionsExcludedCredentials   :: ![PasskeyCredentialDescriptorWire]
    , registrationOptionsAuthenticatorSelection :: !PasskeyAuthenticatorSelectionWire
    , registrationOptionsAttestation           :: !AttestationConveyancePreference
    }
    deriving (Eq, Show)

data PasskeyAuthenticationOptions = PasskeyAuthenticationOptions
    { authenticationOptionsChallenge          :: !Text
    , authenticationOptionsTimeout            :: !Int
    , authenticationOptionsRelyingPartyId     :: !Text
    , authenticationOptionsAllowedCredentials :: ![PasskeyCredentialDescriptorWire]
    , authenticationOptionsUserVerification   :: !UserVerificationRequirement
    }
    deriving (Eq, Show)

registrationOptionsWire :: CredentialOptions 'Registration -> PasskeyRegistrationOptions
registrationOptionsWire CredentialOptionsRegistration
    { corRp
    , corUser
    , corChallenge
    , corPubKeyCredParams
    , corTimeout
    , corExcludeCredentials
    , corAuthenticatorSelection
    , corAttestation
    , corExtensions
    } =
        requireNoExtensions "registration extensions" corExtensions `seq`
            PasskeyRegistrationOptions
                { registrationOptionsRelyingParty = relyingPartyWire corRp
                , registrationOptionsUser = userEntityWire corUser
                , registrationOptionsChallenge = challengeText corChallenge
                , registrationOptionsParameters = fmap credentialParameterWire corPubKeyCredParams
                , registrationOptionsTimeout = timeoutValue "registration timeout" corTimeout
                , registrationOptionsExcludedCredentials = fmap credentialDescriptorWire corExcludeCredentials
                , registrationOptionsAuthenticatorSelection =
                    requiredOption "registration authenticator selection" corAuthenticatorSelection
                        |> authenticatorSelectionWire
                , registrationOptionsAttestation = corAttestation
                }

authenticationOptionsWire :: CredentialOptions 'Authentication -> PasskeyAuthenticationOptions
authenticationOptionsWire CredentialOptionsAuthentication
    { coaChallenge
    , coaTimeout
    , coaRpId
    , coaAllowCredentials
    , coaUserVerification
    , coaExtensions
    } =
        requireNoExtensions "authentication extensions" coaExtensions `seq`
            PasskeyAuthenticationOptions
                { authenticationOptionsChallenge = challengeText coaChallenge
                , authenticationOptionsTimeout = timeoutValue "authentication timeout" coaTimeout
                , authenticationOptionsRelyingPartyId =
                    case requiredOption "authentication relying-party id" coaRpId of
                        RpId value -> value
                , authenticationOptionsAllowedCredentials = fmap credentialDescriptorWire coaAllowCredentials
                , authenticationOptionsUserVerification = coaUserVerification
                }

relyingPartyWire :: CredentialRpEntity -> PasskeyRelyingPartyWire
relyingPartyWire CredentialRpEntity { creId, creName = RelyingPartyName name } =
    PasskeyRelyingPartyWire
        { relyingPartyId =
            case requiredOption "registration relying-party id" creId of
                RpId value -> value
        , relyingPartyName = name
        }

userEntityWire :: CredentialUserEntity -> PasskeyUserEntityWire
userEntityWire CredentialUserEntity
    { cueId = UserHandle userHandle
    , cueDisplayName = UserAccountDisplayName displayName
    , cueName = UserAccountName name
    } =
        PasskeyUserEntityWire
            { userEntityId = base64UrlText userHandle
            , userEntityDisplayName = displayName
            , userEntityName = name
            }

credentialParameterWire :: CredentialParameters -> PasskeyCredentialParameterWire
credentialParameterWire CredentialParameters { cpTyp, cpAlg } =
    PasskeyCredentialParameterWire
        { credentialParameterType = cpTyp
        , credentialParameterAlgorithm = fromIntegral (Cose.fromCoseSignAlg cpAlg)
        }

credentialDescriptorWire :: CredentialDescriptor -> PasskeyCredentialDescriptorWire
credentialDescriptorWire CredentialDescriptor
    { cdTyp
    , cdId = CredentialId credentialId
    , cdTransports
    } =
        requireNoDescriptorTransports cdTransports `seq`
            PasskeyCredentialDescriptorWire
                { credentialDescriptorType = cdTyp
                , credentialDescriptorId = base64UrlText credentialId
                }

authenticatorSelectionWire :: AuthenticatorSelectionCriteria -> PasskeyAuthenticatorSelectionWire
authenticatorSelectionWire AuthenticatorSelectionCriteria
    { ascAuthenticatorAttachment
    , ascResidentKey
    , ascUserVerification
    } =
        PasskeyAuthenticatorSelectionWire
            { selectionAuthenticatorAttachment = ascAuthenticatorAttachment
            , selectionResidentKey = ascResidentKey
            , selectionRequireResidentKey = ascResidentKey == ResidentKeyRequirementRequired
            , selectionUserVerification = ascUserVerification
            }

challengeText :: Challenge -> Text
challengeText (Challenge challenge) = base64UrlText challenge

timeoutValue :: Text -> Maybe Timeout -> Int
timeoutValue label maybeTimeout =
    case requiredOption label maybeTimeout of
        Timeout value -> fromIntegral value

requiredOption :: Text -> Maybe value -> value
requiredOption label =
    fromMaybe (error (cs ("Passkey wire invariant requires " <> label)))

requireNoExtensions :: Text -> Maybe AuthenticationExtensionsClientInputs -> ()
requireNoExtensions _ Nothing = ()
requireNoExtensions label (Just _) =
    error (cs ("Passkey wire contract does not declare " <> label))

requireNoDescriptorTransports :: Maybe [AuthenticatorTransport] -> ()
requireNoDescriptorTransports Nothing = ()
requireNoDescriptorTransports (Just _) =
    error "Passkey begin credential descriptors must not carry transports"

-- Exact finish request carriers ----------------------------------------------

data PasskeyAttestationResponseWire = PasskeyAttestationResponseWire
    { attestationClientDataJson :: !Text
    , attestationObject         :: !Text
    , attestationTransports     :: ![Text]
    }
    deriving (Eq, Show)

data PasskeyAssertionResponseWire = PasskeyAssertionResponseWire
    { assertionClientDataJson    :: !Text
    , assertionAuthenticatorData :: !Text
    , assertionSignature         :: !Text
    , assertionUserHandle        :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PasskeyRegistrationRequest = PasskeyRegistrationRequest
    { passkeyRegistrationCredential :: !WebAuthnJson.WJCredentialRegistration
    , passkeyRegistrationName       :: !(Maybe Text)
    }
    deriving (Eq, Show)

newtype PasskeyAuthenticationRequest = PasskeyAuthenticationRequest
    { passkeyAuthenticationCredential :: WebAuthnJson.WJCredentialAuthentication
    }
    deriving (Eq, Show)

instance Aeson.ToJSON PasskeyRegistrationRequest where
    toJSON PasskeyRegistrationRequest { passkeyRegistrationCredential, passkeyRegistrationName } =
        case passkeyRegistrationCredential of
            WebAuthnJson.WJCredentialRegistration
                (WebAuthnWire.PublicKeyCredential rawId response clientExtensionResults) ->
                    recordValue @Contract.PasskeyRegistrationRequest
                        ( requiredField @Contract.RawId (base64UrlWireText rawId)
                            &: requiredField @Contract.Response (attestationResponseFromWebAuthn response)
                            &: requiredField @Contract.ClientExtensionResults (Aeson.toJSON clientExtensionResults)
                            &: optionalField @Contract.Name passkeyRegistrationName
                            &: noFields
                        )

instance Aeson.FromJSON PasskeyRegistrationRequest where
    parseJSON =
        parseRecord @Contract.PasskeyRegistrationRequest
            (\(rawId, (response, (clientExtensionResults, (name, ())))) -> do
                parsedRawId <- parseBase64UrlText rawId
                parsedExtensions <- Aeson.parseJSON clientExtensionResults
                pure PasskeyRegistrationRequest
                    { passkeyRegistrationCredential =
                        WebAuthnJson.WJCredentialRegistration
                            ( WebAuthnWire.PublicKeyCredential
                                parsedRawId
                                (attestationResponseToWebAuthn response)
                                parsedExtensions
                            )
                    , passkeyRegistrationName = name
                    }
            )

instance Aeson.ToJSON PasskeyAuthenticationRequest where
    toJSON PasskeyAuthenticationRequest { passkeyAuthenticationCredential } =
        case passkeyAuthenticationCredential of
            WebAuthnJson.WJCredentialAuthentication
                (WebAuthnWire.PublicKeyCredential rawId response clientExtensionResults) ->
                    recordValue @Contract.PasskeyAuthenticationRequest
                        ( requiredField @Contract.RawId (base64UrlWireText rawId)
                            &: requiredField @Contract.Response (assertionResponseFromWebAuthn response)
                            &: requiredField @Contract.ClientExtensionResults (Aeson.toJSON clientExtensionResults)
                            &: noFields
                        )

instance Aeson.FromJSON PasskeyAuthenticationRequest where
    parseJSON =
        parseRecord @Contract.PasskeyAuthenticationRequest
            (\(rawId, (response, (clientExtensionResults, ()))) -> do
                parsedRawId <- parseBase64UrlText rawId
                parsedExtensions <- Aeson.parseJSON clientExtensionResults
                pure PasskeyAuthenticationRequest
                    { passkeyAuthenticationCredential =
                        WebAuthnJson.WJCredentialAuthentication
                            ( WebAuthnWire.PublicKeyCredential
                                parsedRawId
                                (assertionResponseToWebAuthn response)
                                parsedExtensions
                            )
                    }
            )

attestationResponseFromWebAuthn :: WebAuthnWire.AuthenticatorAttestationResponse -> PasskeyAttestationResponseWire
attestationResponseFromWebAuthn
    (WebAuthnWire.AuthenticatorAttestationResponse clientDataJSON attestation transports) =
        PasskeyAttestationResponseWire
            { attestationClientDataJson = base64UrlWireText clientDataJSON
            , attestationObject = base64UrlWireText attestation
            , attestationTransports = fromMaybe [] transports
            }

attestationResponseToWebAuthn :: PasskeyAttestationResponseWire -> WebAuthnWire.AuthenticatorAttestationResponse
attestationResponseToWebAuthn PasskeyAttestationResponseWire
    { attestationClientDataJson
    , attestationObject
    , attestationTransports
    } =
        WebAuthnWire.AuthenticatorAttestationResponse
            (unsafeParsedBase64UrlText attestationClientDataJson)
            (unsafeParsedBase64UrlText attestationObject)
            (Just attestationTransports)

assertionResponseFromWebAuthn :: WebAuthnWire.AuthenticatorAssertionResponse -> PasskeyAssertionResponseWire
assertionResponseFromWebAuthn
    (WebAuthnWire.AuthenticatorAssertionResponse clientDataJSON authenticatorData signature userHandle) =
        PasskeyAssertionResponseWire
            { assertionClientDataJson = base64UrlWireText clientDataJSON
            , assertionAuthenticatorData = base64UrlWireText authenticatorData
            , assertionSignature = base64UrlWireText signature
            , assertionUserHandle = fmap base64UrlWireText userHandle
            }

assertionResponseToWebAuthn :: PasskeyAssertionResponseWire -> WebAuthnWire.AuthenticatorAssertionResponse
assertionResponseToWebAuthn PasskeyAssertionResponseWire
    { assertionClientDataJson
    , assertionAuthenticatorData
    , assertionSignature
    , assertionUserHandle
    } =
        WebAuthnWire.AuthenticatorAssertionResponse
            (unsafeParsedBase64UrlText assertionClientDataJson)
            (unsafeParsedBase64UrlText assertionAuthenticatorData)
            (unsafeParsedBase64UrlText assertionSignature)
            (fmap unsafeParsedBase64UrlText assertionUserHandle)

-- Exact finish and error response carriers -----------------------------------

data PasskeyFinishResponse
    = PasskeyAuthenticated !UUID.UUID !Text
    | PasskeyRegistered !UUID.UUID !(Maybe Text)
    | PasskeySetupRegistered !UUID.UUID !Text
    deriving (Eq, Show)

data PasskeyErrorResponse
    = PasskeyFailure !Text
    | PasskeyRedirectFailure !Text !Text
    deriving (Eq, Show)

instance Aeson.ToJSON PasskeyFinishResponse where
    toJSON (PasskeyAuthenticated userId redirectTo) =
        taggedUnionValue @Contract.PasskeyFinishResponse @Contract.Authenticated
            ( requiredField @Contract.UserId userId
                &: requiredField @Contract.RedirectTo redirectTo
                &: noFields
            )
    toJSON (PasskeyRegistered userId recoveryCode) =
        taggedUnionValue @Contract.PasskeyFinishResponse @Contract.Registered
            ( requiredField @Contract.UserId userId
                &: nullableField @Contract.RecoveryCode recoveryCode
                &: noFields
            )
    toJSON (PasskeySetupRegistered userId redirectTo) =
        taggedUnionValue @Contract.PasskeyFinishResponse @Contract.SetupRegistered
            ( requiredField @Contract.UserId userId
                &: requiredField @Contract.RedirectTo redirectTo
                &: noFields
            )

instance Aeson.FromJSON PasskeyFinishResponse where
    parseJSON =
        parseTaggedUnion @Contract.PasskeyFinishResponse
            ( unionCase @Contract.Authenticated
                (\(userId, (redirectTo, ())) -> pure (PasskeyAuthenticated userId redirectTo))
                |: unionCase @Contract.Registered
                    (\(userId, (recoveryCode, ())) -> pure (PasskeyRegistered userId recoveryCode))
                |: unionCase @Contract.SetupRegistered
                    (\(userId, (redirectTo, ())) -> pure (PasskeySetupRegistered userId redirectTo))
                |: noUnionCases
            )

instance Aeson.ToJSON PasskeyErrorResponse where
    toJSON (PasskeyFailure errorMessage) =
        taggedUnionValue @Contract.PasskeyErrorResponse @Contract.Failure
            ( requiredField @Contract.Error errorMessage
                &: noFields
            )
    toJSON (PasskeyRedirectFailure errorMessage redirectTo) =
        taggedUnionValue @Contract.PasskeyErrorResponse @Contract.Redirect
            ( requiredField @Contract.Error errorMessage
                &: requiredField @Contract.RedirectTo redirectTo
                &: noFields
            )

instance Aeson.FromJSON PasskeyErrorResponse where
    parseJSON =
        parseTaggedUnion @Contract.PasskeyErrorResponse
            ( unionCase @Contract.Failure
                (\(errorMessage, ()) -> pure (PasskeyFailure errorMessage))
                |: unionCase @Contract.Redirect
                    (\(errorMessage, (redirectTo, ())) -> pure (PasskeyRedirectFailure errorMessage redirectTo))
                |: noUnionCases
            )

-- Referenced schema carriers --------------------------------------------------

instance ContractReference Contract.PasskeyCredentialType where
    type ContractReferenceValue Contract.PasskeyCredentialType = CredentialType
    contractReferenceJson = Aeson.String . WebAuthnStrings.encodeCredentialType
    parseContractReference = parseWebAuthnText "PasskeyCredentialType" WebAuthnStrings.decodeCredentialType

instance ContractReference Contract.PasskeyAuthenticatorAttachment where
    type ContractReferenceValue Contract.PasskeyAuthenticatorAttachment = AuthenticatorAttachment
    contractReferenceJson = Aeson.String . WebAuthnStrings.encodeAuthenticatorAttachment
    parseContractReference = parseWebAuthnText "PasskeyAuthenticatorAttachment" WebAuthnStrings.decodeAuthenticatorAttachment

instance ContractReference Contract.PasskeyResidentKeyRequirement where
    type ContractReferenceValue Contract.PasskeyResidentKeyRequirement = ResidentKeyRequirement
    contractReferenceJson = Aeson.String . WebAuthnStrings.encodeResidentKeyRequirement
    parseContractReference = parseWebAuthnText "PasskeyResidentKeyRequirement" WebAuthnStrings.decodeResidentKeyRequirement

instance ContractReference Contract.PasskeyUserVerificationRequirement where
    type ContractReferenceValue Contract.PasskeyUserVerificationRequirement = UserVerificationRequirement
    contractReferenceJson = Aeson.String . WebAuthnStrings.encodeUserVerificationRequirement
    parseContractReference = parseWebAuthnText "PasskeyUserVerificationRequirement" WebAuthnStrings.decodeUserVerificationRequirement

instance ContractReference Contract.PasskeyAttestationConveyancePreference where
    type ContractReferenceValue Contract.PasskeyAttestationConveyancePreference = AttestationConveyancePreference
    contractReferenceJson = Aeson.String . WebAuthnStrings.encodeAttestationConveyancePreference
    parseContractReference = parseWebAuthnText "PasskeyAttestationConveyancePreference" WebAuthnStrings.decodeAttestationConveyancePreference

instance ContractReference Contract.PasskeyRelyingParty where
    type ContractReferenceValue Contract.PasskeyRelyingParty = PasskeyRelyingPartyWire
    contractReferenceJson PasskeyRelyingPartyWire { relyingPartyId, relyingPartyName } =
        recordValue @Contract.PasskeyRelyingParty
            ( requiredField @Contract.Id relyingPartyId
                &: requiredField @Contract.Name relyingPartyName
                &: noFields
            )
    parseContractReference =
        parseRecord @Contract.PasskeyRelyingParty
            (\(relyingPartyId, (relyingPartyName, ())) -> pure PasskeyRelyingPartyWire { relyingPartyId, relyingPartyName })

instance ContractReference Contract.PasskeyUserEntity where
    type ContractReferenceValue Contract.PasskeyUserEntity = PasskeyUserEntityWire
    contractReferenceJson PasskeyUserEntityWire { userEntityId, userEntityDisplayName, userEntityName } =
        recordValue @Contract.PasskeyUserEntity
            ( requiredField @Contract.Id userEntityId
                &: requiredField @Contract.DisplayName userEntityDisplayName
                &: requiredField @Contract.Name userEntityName
                &: noFields
            )
    parseContractReference =
        parseRecord @Contract.PasskeyUserEntity
            (\(userEntityId, (userEntityDisplayName, (userEntityName, ()))) ->
                pure PasskeyUserEntityWire { userEntityId, userEntityDisplayName, userEntityName }
            )

instance ContractReference Contract.PasskeyCredentialParameter where
    type ContractReferenceValue Contract.PasskeyCredentialParameter = PasskeyCredentialParameterWire
    contractReferenceJson PasskeyCredentialParameterWire { credentialParameterType, credentialParameterAlgorithm } =
        recordValue @Contract.PasskeyCredentialParameter
            ( requiredField @Contract.Type credentialParameterType
                &: requiredField @Contract.Alg credentialParameterAlgorithm
                &: noFields
            )
    parseContractReference =
        parseRecord @Contract.PasskeyCredentialParameter
            (\(credentialParameterType, (credentialParameterAlgorithm, ())) ->
                pure PasskeyCredentialParameterWire { credentialParameterType, credentialParameterAlgorithm }
            )

instance ContractReference Contract.PasskeyCredentialDescriptor where
    type ContractReferenceValue Contract.PasskeyCredentialDescriptor = PasskeyCredentialDescriptorWire
    contractReferenceJson PasskeyCredentialDescriptorWire { credentialDescriptorType, credentialDescriptorId } =
        recordValue @Contract.PasskeyCredentialDescriptor
            ( requiredField @Contract.Type credentialDescriptorType
                &: requiredField @Contract.Id credentialDescriptorId
                &: noFields
            )
    parseContractReference =
        parseRecord @Contract.PasskeyCredentialDescriptor
            (\(credentialDescriptorType, (credentialDescriptorId, ())) ->
                pure PasskeyCredentialDescriptorWire { credentialDescriptorType, credentialDescriptorId }
            )

instance ContractReference Contract.PasskeyAuthenticatorSelection where
    type ContractReferenceValue Contract.PasskeyAuthenticatorSelection = PasskeyAuthenticatorSelectionWire
    contractReferenceJson PasskeyAuthenticatorSelectionWire
        { selectionAuthenticatorAttachment
        , selectionResidentKey
        , selectionRequireResidentKey
        , selectionUserVerification
        } =
            recordValue @Contract.PasskeyAuthenticatorSelection
                ( optionalField @Contract.AuthenticatorAttachment selectionAuthenticatorAttachment
                    &: requiredField @Contract.ResidentKey selectionResidentKey
                    &: requiredField @Contract.RequireResidentKey selectionRequireResidentKey
                    &: requiredField @Contract.UserVerification selectionUserVerification
                    &: noFields
                )
    parseContractReference =
        parseRecord @Contract.PasskeyAuthenticatorSelection
            (\(selectionAuthenticatorAttachment, (selectionResidentKey, (selectionRequireResidentKey, (selectionUserVerification, ())))) ->
                pure PasskeyAuthenticatorSelectionWire
                    { selectionAuthenticatorAttachment
                    , selectionResidentKey
                    , selectionRequireResidentKey
                    , selectionUserVerification
                    }
            )

instance ContractReference Contract.PasskeyAttestationResponse where
    type ContractReferenceValue Contract.PasskeyAttestationResponse = PasskeyAttestationResponseWire
    contractReferenceJson PasskeyAttestationResponseWire
        { attestationClientDataJson
        , attestationObject
        , attestationTransports
        } =
            recordValue @Contract.PasskeyAttestationResponse
                ( requiredField @Contract.ClientDataJSON attestationClientDataJson
                    &: requiredField @Contract.AttestationObject attestationObject
                    &: requiredField @Contract.Transports attestationTransports
                    &: noFields
                )
    parseContractReference =
        parseRecord @Contract.PasskeyAttestationResponse
            (\(attestationClientDataJson, (attestationObject, (attestationTransports, ()))) -> do
                _ <- parseBase64UrlText attestationClientDataJson
                _ <- parseBase64UrlText attestationObject
                pure PasskeyAttestationResponseWire
                    { attestationClientDataJson
                    , attestationObject
                    , attestationTransports
                    }
            )

instance ContractReference Contract.PasskeyAssertionResponse where
    type ContractReferenceValue Contract.PasskeyAssertionResponse = PasskeyAssertionResponseWire
    contractReferenceJson PasskeyAssertionResponseWire
        { assertionClientDataJson
        , assertionAuthenticatorData
        , assertionSignature
        , assertionUserHandle
        } =
            recordValue @Contract.PasskeyAssertionResponse
                ( requiredField @Contract.ClientDataJSON assertionClientDataJson
                    &: requiredField @Contract.AuthenticatorData assertionAuthenticatorData
                    &: requiredField @Contract.Signature assertionSignature
                    &: nullableField @Contract.UserHandle assertionUserHandle
                    &: noFields
                )
    parseContractReference =
        parseRecord @Contract.PasskeyAssertionResponse
            (\(assertionClientDataJson, (assertionAuthenticatorData, (assertionSignature, (assertionUserHandle, ())))) -> do
                _ <- parseBase64UrlText assertionClientDataJson
                _ <- parseBase64UrlText assertionAuthenticatorData
                _ <- parseBase64UrlText assertionSignature
                forM_ assertionUserHandle parseBase64UrlText
                pure PasskeyAssertionResponseWire
                    { assertionClientDataJson
                    , assertionAuthenticatorData
                    , assertionSignature
                    , assertionUserHandle
                    }
            )

instance Aeson.ToJSON PasskeyRegistrationOptions where
    toJSON PasskeyRegistrationOptions
        { registrationOptionsRelyingParty
        , registrationOptionsUser
        , registrationOptionsChallenge
        , registrationOptionsParameters
        , registrationOptionsTimeout
        , registrationOptionsExcludedCredentials
        , registrationOptionsAuthenticatorSelection
        , registrationOptionsAttestation
        } =
            recordValue @Contract.PasskeyRegistrationOptions
                ( requiredField @Contract.Rp registrationOptionsRelyingParty
                    &: requiredField @Contract.User registrationOptionsUser
                    &: requiredField @Contract.Challenge registrationOptionsChallenge
                    &: requiredField @Contract.PubKeyCredParams registrationOptionsParameters
                    &: requiredField @Contract.Timeout registrationOptionsTimeout
                    &: requiredField @Contract.ExcludeCredentials registrationOptionsExcludedCredentials
                    &: requiredField @Contract.AuthenticatorSelection registrationOptionsAuthenticatorSelection
                    &: requiredField @Contract.Attestation registrationOptionsAttestation
                    &: noFields
                )

instance Aeson.FromJSON PasskeyRegistrationOptions where
    parseJSON =
        parseRecord @Contract.PasskeyRegistrationOptions
            (\(registrationOptionsRelyingParty, (registrationOptionsUser, (registrationOptionsChallenge, (registrationOptionsParameters, (registrationOptionsTimeout, (registrationOptionsExcludedCredentials, (registrationOptionsAuthenticatorSelection, (registrationOptionsAttestation, ())))))))) ->
                pure PasskeyRegistrationOptions
                    { registrationOptionsRelyingParty
                    , registrationOptionsUser
                    , registrationOptionsChallenge
                    , registrationOptionsParameters
                    , registrationOptionsTimeout
                    , registrationOptionsExcludedCredentials
                    , registrationOptionsAuthenticatorSelection
                    , registrationOptionsAttestation
                    }
            )

instance Aeson.ToJSON PasskeyAuthenticationOptions where
    toJSON PasskeyAuthenticationOptions
        { authenticationOptionsChallenge
        , authenticationOptionsTimeout
        , authenticationOptionsRelyingPartyId
        , authenticationOptionsAllowedCredentials
        , authenticationOptionsUserVerification
        } =
            recordValue @Contract.PasskeyAuthenticationOptions
                ( requiredField @Contract.Challenge authenticationOptionsChallenge
                    &: requiredField @Contract.Timeout authenticationOptionsTimeout
                    &: requiredField @Contract.RpId authenticationOptionsRelyingPartyId
                    &: requiredField @Contract.AllowCredentials authenticationOptionsAllowedCredentials
                    &: requiredField @Contract.UserVerification authenticationOptionsUserVerification
                    &: noFields
                )

instance Aeson.FromJSON PasskeyAuthenticationOptions where
    parseJSON =
        parseRecord @Contract.PasskeyAuthenticationOptions
            (\(authenticationOptionsChallenge, (authenticationOptionsTimeout, (authenticationOptionsRelyingPartyId, (authenticationOptionsAllowedCredentials, (authenticationOptionsUserVerification, ()))))) ->
                pure PasskeyAuthenticationOptions
                    { authenticationOptionsChallenge
                    , authenticationOptionsTimeout
                    , authenticationOptionsRelyingPartyId
                    , authenticationOptionsAllowedCredentials
                    , authenticationOptionsUserVerification
                    }
            )

parseWebAuthnText :: Text -> (Text -> Either Text value) -> Aeson.Value -> AesonTypes.Parser value
parseWebAuthnText label decode =
    Aeson.withText (cs label) (either (fail . cs) pure . decode)

base64UrlText :: ByteString -> Text
base64UrlText = TextEncoding.decodeUtf8 . Base64Url.encodeUnpadded

base64UrlWireText :: WebAuthnWire.Base64UrlString -> Text
base64UrlWireText (WebAuthnWire.Base64UrlString value) = base64UrlText value

parseBase64UrlText :: Text -> AesonTypes.Parser WebAuthnWire.Base64UrlString
parseBase64UrlText value =
    case Base64Url.decode (TextEncoding.encodeUtf8 value) of
        Left errorMessage -> fail errorMessage
        Right bytes       -> pure (WebAuthnWire.Base64UrlString bytes)

unsafeParsedBase64UrlText :: Text -> WebAuthnWire.Base64UrlString
unsafeParsedBase64UrlText value =
    case AesonTypes.parseEither parseBase64UrlText value of
        Left errorMessage -> error (cs errorMessage)
        Right parsed      -> parsed
