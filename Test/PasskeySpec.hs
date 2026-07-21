{-# LANGUAGE DataKinds #-}

module Test.PasskeySpec where

import Application.Helper.FrontendContract.Passkey.Runtime
import Application.Helper.FrontendContract.Wire.Passkey
import Control.Exception (evaluate)
import Crypto.WebAuthn.Cose.SignAlg (CoseHashAlgECDSA (CoseHashAlgECDSASHA256),
                                     CoseSignAlg (CoseSignAlgECDSA))
import Crypto.WebAuthn.Model.Kinds (CeremonyKind (Authentication, Registration))
import Crypto.WebAuthn.Model.Types
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString as ByteString
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Passkey contract runtime" do
    it "renders an exact generated login flow with a mount-local status relationship" do
        passkeyLoginAttrs "/begin" "/finish" (Just "/after")
            `shouldBe`
                [ ("data-bepis-passkey-login", "true")
                , ( "data-bepis-passkey-flow-config"
                  , "{\"beginUrl\":\"/begin\",\"cancelledMessage\":\"No passkey was selected.\",\"failureMessage\":\"Passkey request failed.\",\"finishUrl\":\"/finish\",\"pendingLabel\":\"Please wait\",\"statusKey\":\"status\",\"successMessage\":\"Signed in.\",\"successRedirect\":\"/after\",\"tag\":\"login\",\"unsupportedMessage\":\"Passkeys are not supported in this browser.\",\"waitingMessage\":\"Waiting for your passkey...\"}"
                  )
                ]
        passkeyActionButtonAttrs
            `shouldBe` [("data-bepis-passkey-action-button", "true")]
        passkeyStatusAttrs
            `shouldBe` [("data-bepis-passkey-status", "status")]

    it "renders exact registration, recovery, and closed setup-prompt roles" do
        passkeyRegistrationAttrs "/register" "/finish-registration" Nothing
            `shouldBe`
                [ ("data-bepis-passkey-registration", "true")
                , ( "data-bepis-passkey-flow-config"
                  , "{\"beginUrl\":\"/register\",\"cancelledMessage\":\"Passkey registration was cancelled.\",\"failureMessage\":\"Passkey request failed.\",\"finishUrl\":\"/finish-registration\",\"pendingLabel\":\"Please wait\",\"statusKey\":\"status\",\"successMessage\":\"Passkey added.\",\"tag\":\"registration\",\"unsupportedMessage\":\"Passkeys are not supported in this browser.\",\"waitingMessage\":\"Waiting for your passkey...\"}"
                  )
                ]
        passkeySetupPromptAttrs "user-1" PasskeyAdditionalDevice
            `shouldBe`
                [ ("data-bepis-passkey-setup-prompt", "true")
                , ("data-bepis-passkey-flow-config", "{\"promptUserKey\":\"user-1\",\"setupPromptMode\":\"additional-device\",\"tag\":\"setup-prompt\"}")
                ]
        passkeyDeviceNameAttrs
            `shouldBe` [("data-bepis-passkey-device-name", "true")]
        passkeyRecoveryAttrs
            `shouldBe` [("data-bepis-passkey-recovery", "status")]
        passkeyDismissalAttrs
            `shouldBe` [("data-bepis-passkey-dismissal", "true")]
        fmap passkeySetupPromptModeValue [PasskeyFirstPasskey, PasskeyAdditionalDevice]
            `shouldBe` ["first-passkey", "additional-device"]

    it "builds exact registration and authentication begin options from WebAuthn domain values" do
        Aeson.toJSON (registrationOptionsWire sampleRegistrationOptions)
            `shouldBe` Aeson.object
                [ "rp" Aeson..= Aeson.object
                    [ "id" Aeson..= ("example.test" :: Text)
                    , "name" Aeson..= ("Bepis" :: Text)
                    ]
                , "user" Aeson..= Aeson.object
                    [ "id" Aeson..= ("dXNlci1pZA" :: Text)
                    , "displayName" Aeson..= ("person@example.test" :: Text)
                    , "name" Aeson..= ("person@example.test" :: Text)
                    ]
                , "challenge" Aeson..= ("AQID" :: Text)
                , "pubKeyCredParams" Aeson..=
                    [ Aeson.object
                        [ "type" Aeson..= ("public-key" :: Text)
                        , "alg" Aeson..= (-7 :: Int)
                        ]
                    ]
                , "timeout" Aeson..= (60000 :: Int)
                , "excludeCredentials" Aeson..=
                    [ Aeson.object
                        [ "type" Aeson..= ("public-key" :: Text)
                        , "id" Aeson..= ("BAU" :: Text)
                        ]
                    ]
                , "authenticatorSelection" Aeson..= Aeson.object
                    [ "residentKey" Aeson..= ("required" :: Text)
                    , "requireResidentKey" Aeson..= True
                    , "userVerification" Aeson..= ("preferred" :: Text)
                    ]
                , "attestation" Aeson..= ("none" :: Text)
                ]
        Aeson.toJSON (authenticationOptionsWire sampleAuthenticationOptions)
            `shouldBe` Aeson.object
                [ "challenge" Aeson..= ("AQID" :: Text)
                , "timeout" Aeson..= (60000 :: Int)
                , "rpId" Aeson..= ("example.test" :: Text)
                , "allowCredentials" Aeson..=
                    [ Aeson.object
                        [ "type" Aeson..= ("public-key" :: Text)
                        , "id" Aeson..= ("BAU" :: Text)
                        ]
                    ]
                , "userVerification" Aeson..= ("preferred" :: Text)
                ]

    it "parses exact serialized registration and authentication credentials" do
        parseRegistrationRequest validRegistrationRequest
            `shouldSatisfy` isRight
        fmap Aeson.toJSON (parseRegistrationRequest validRegistrationRequest)
            `shouldBe` Right validRegistrationRequest
        parseRegistrationRequest (addObjectField "extra" Aeson.Null validRegistrationRequest)
            `shouldSatisfy` isLeft
        parseRegistrationRequest registrationRequestWithMalformedTransports
            `shouldSatisfy` isLeft
        parseRegistrationRequest (replaceObjectField "clientExtensionResults" (Aeson.String "not-an-object") validRegistrationRequest)
            `shouldSatisfy` isLeft

        parseAuthenticationRequest validAuthenticationRequest
            `shouldSatisfy` isRight
        fmap Aeson.toJSON (parseAuthenticationRequest validAuthenticationRequest)
            `shouldBe` Right validAuthenticationRequest
        parseAuthenticationRequest authenticationRequestWithoutUserHandle
            `shouldSatisfy` isLeft
        parseAuthenticationRequest (addObjectField "id" (Aeson.String "legacy-id") validAuthenticationRequest)
            `shouldSatisfy` isLeft

    it "builds and parses exact tagged finish and structured error envelopes" do
        let userId = fixtureUserId
        let registered = PasskeyRegistered userId Nothing
        let redirectFailure = PasskeyRedirectFailure "Verify first." "/PasskeyStepUp"
        Aeson.toJSON registered
            `shouldBe` Aeson.object
                [ "tag" Aeson..= ("registered" :: Text)
                , "userId" Aeson..= UUID.toText userId
                , "recoveryCode" Aeson..= Aeson.Null
                ]
        Aeson.fromJSON (Aeson.toJSON registered) `shouldBe` Aeson.Success registered
        Aeson.toJSON redirectFailure
            `shouldBe` Aeson.object
                [ "tag" Aeson..= ("redirect" :: Text)
                , "error" Aeson..= ("Verify first." :: Text)
                , "redirectTo" Aeson..= ("/PasskeyStepUp" :: Text)
                ]
        Aeson.fromJSON (Aeson.toJSON redirectFailure) `shouldBe` Aeson.Success redirectFailure
        (Aeson.fromJSON (addObjectField "message" (Aeson.String "legacy") (Aeson.toJSON registered)) :: Aeson.Result PasskeyFinishResponse)
            `shouldSatisfy` isAesonError
        (Aeson.fromJSON (Aeson.object ["tag" Aeson..= ("redirect" :: Text), "error" Aeson..= ("missing target" :: Text)]) :: Aeson.Result PasskeyErrorResponse)
            `shouldSatisfy` isAesonError

    it "rejects empty Haskell-owned flow URLs before rendering browser configuration" do
        evaluate (attrsTextLength (passkeyLoginAttrs " " "/finish" Nothing))
            `shouldThrow` errorCall "Passkey begin URL must not be empty"
        evaluate (attrsTextLength (passkeyRegistrationAttrs "/begin" "" Nothing))
            `shouldThrow` errorCall "Passkey finish URL must not be empty"

    it "rejects empty optional redirects and prompt user keys" do
        evaluate (attrsTextLength (passkeyRegistrationAttrs "/begin" "/finish" (Just " ")))
            `shouldThrow` errorCall "Passkey success redirect must not be empty"
        evaluate (attrsTextLength (passkeySetupPromptAttrs "" PasskeyFirstPasskey))
            `shouldThrow` errorCall "Passkey prompt user key must not be empty"

sampleRegistrationOptions :: CredentialOptions 'Registration
sampleRegistrationOptions = CredentialOptionsRegistration
    { corRp = CredentialRpEntity
        { creId = Just (RpId "example.test")
        , creName = RelyingPartyName "Bepis"
        }
    , corUser = CredentialUserEntity
        { cueId = UserHandle "user-id"
        , cueDisplayName = UserAccountDisplayName "person@example.test"
        , cueName = UserAccountName "person@example.test"
        }
    , corChallenge = Challenge (ByteString.pack [1, 2, 3])
    , corPubKeyCredParams =
        [ CredentialParameters CredentialTypePublicKey (CoseSignAlgECDSA CoseHashAlgECDSASHA256)
        ]
    , corTimeout = Just (Timeout 60000)
    , corExcludeCredentials = [sampleCredentialDescriptor]
    , corAuthenticatorSelection = Just AuthenticatorSelectionCriteria
        { ascAuthenticatorAttachment = Nothing
        , ascResidentKey = ResidentKeyRequirementRequired
        , ascUserVerification = UserVerificationRequirementPreferred
        }
    , corAttestation = AttestationConveyancePreferenceNone
    , corExtensions = Nothing
    }

sampleAuthenticationOptions :: CredentialOptions 'Authentication
sampleAuthenticationOptions = CredentialOptionsAuthentication
    { coaChallenge = Challenge (ByteString.pack [1, 2, 3])
    , coaTimeout = Just (Timeout 60000)
    , coaRpId = Just (RpId "example.test")
    , coaAllowCredentials = [sampleCredentialDescriptor]
    , coaUserVerification = UserVerificationRequirementPreferred
    , coaExtensions = Nothing
    }

sampleCredentialDescriptor :: CredentialDescriptor
sampleCredentialDescriptor = CredentialDescriptor
    { cdTyp = CredentialTypePublicKey
    , cdId = CredentialId (ByteString.pack [4, 5])
    , cdTransports = Nothing
    }

validRegistrationRequest :: Aeson.Value
validRegistrationRequest = Aeson.object
    [ "rawId" Aeson..= ("AQ" :: Text)
    , "response" Aeson..= Aeson.object
        [ "clientDataJSON" Aeson..= ("Ag" :: Text)
        , "attestationObject" Aeson..= ("Aw" :: Text)
        , "transports" Aeson..= (["internal"] :: [Text])
        ]
    , "clientExtensionResults" Aeson..= Aeson.object []
    , "name" Aeson..= ("Laptop" :: Text)
    ]

registrationRequestWithMalformedTransports :: Aeson.Value
registrationRequestWithMalformedTransports =
    replaceObjectField
        "response"
        ( Aeson.object
            [ "clientDataJSON" Aeson..= ("Ag" :: Text)
            , "attestationObject" Aeson..= ("Aw" :: Text)
            , "transports" Aeson..= ("internal" :: Text)
            ]
        )
        validRegistrationRequest

validAuthenticationRequest :: Aeson.Value
validAuthenticationRequest = Aeson.object
    [ "rawId" Aeson..= ("AQ" :: Text)
    , "response" Aeson..= Aeson.object
        [ "clientDataJSON" Aeson..= ("Ag" :: Text)
        , "authenticatorData" Aeson..= ("Aw" :: Text)
        , "signature" Aeson..= ("BA" :: Text)
        , "userHandle" Aeson..= Aeson.Null
        ]
    , "clientExtensionResults" Aeson..= Aeson.object []
    ]

authenticationRequestWithoutUserHandle :: Aeson.Value
authenticationRequestWithoutUserHandle =
    replaceObjectField
        "response"
        ( Aeson.object
            [ "clientDataJSON" Aeson..= ("Ag" :: Text)
            , "authenticatorData" Aeson..= ("Aw" :: Text)
            , "signature" Aeson..= ("BA" :: Text)
            ]
        )
        validAuthenticationRequest

parseRegistrationRequest :: Aeson.Value -> Either String PasskeyRegistrationRequest
parseRegistrationRequest = AesonTypes.parseEither Aeson.parseJSON

parseAuthenticationRequest :: Aeson.Value -> Either String PasskeyAuthenticationRequest
parseAuthenticationRequest = AesonTypes.parseEither Aeson.parseJSON

fixtureUserId :: UUID.UUID
fixtureUserId =
    fromMaybe (error "invalid passkey user fixture")
        (UUID.fromText "11111111-1111-1111-1111-111111111111")

addObjectField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
addObjectField name value (Aeson.Object object) =
    Aeson.Object (KeyMap.insert (AesonKey.fromText name) value object)
addObjectField _ _ value = value

replaceObjectField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
replaceObjectField = addObjectField

isAesonError :: Aeson.Result value -> Bool
isAesonError (Aeson.Error _) = True
isAesonError _               = False

attrsTextLength :: [(Text, Text)] -> Int
attrsTextLength = Text.length . Text.concat . fmap snd
