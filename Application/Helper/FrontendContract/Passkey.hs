{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Passkey
    ( PasskeyContract
    , Passkey
    , PasskeyFlowConfig
    , Login
    , Registration
    , SetupPrompt
    , BeginUrl
    , FinishUrl
    , SuccessRedirect
    , StatusKey
    , WaitingMessage
    , SuccessMessage
    , UnsupportedMessage
    , FailureMessage
    , PendingLabel
    , CancelledMessage
    , PromptUserKey
    , SetupPromptMode
    , PasskeySetupPromptMode
    , FirstPasskey
    , AdditionalDevice
    , PasskeyFirstPasskeyMode
    , PasskeyAdditionalDeviceMode
    , PasskeyCredentialType
    , PublicKey
    , PasskeyAuthenticatorAttachment
    , Platform
    , CrossPlatform
    , PasskeyResidentKeyRequirement
    , PasskeyUserVerificationRequirement
    , Discouraged
    , Preferred
    , Required
    , PasskeyAttestationConveyancePreference
    , None
    , Indirect
    , Direct
    , Enterprise
    , PasskeyRelyingParty
    , PasskeyUserEntity
    , PasskeyCredentialParameter
    , PasskeyCredentialDescriptor
    , PasskeyAuthenticatorSelection
    , PasskeyRegistrationOptions
    , PasskeyAuthenticationOptions
    , PasskeyAttestationResponse
    , PasskeyRegistrationRequest
    , PasskeyAssertionResponse
    , PasskeyAuthenticationRequest
    , PasskeyFinishResponse
    , Authenticated
    , Registered
    , SetupRegistered
    , PasskeyErrorResponse
    , Failure
    , Redirect
    , Rp
    , User
    , Id
    , Name
    , DisplayName
    , Challenge
    , PubKeyCredParams
    , Timeout
    , ExcludeCredentials
    , AuthenticatorSelection
    , Attestation
    , Type
    , Alg
    , AuthenticatorAttachment
    , ResidentKey
    , RequireResidentKey
    , UserVerification
    , RpId
    , AllowCredentials
    , RawId
    , Response
    , ClientDataJSON
    , AttestationObject
    , Transports
    , AuthenticatorData
    , Signature
    , UserHandle
    , ClientExtensionResults
    , UserId
    , RedirectTo
    , RecoveryCode
    , Error
    , PasskeyLogin
    , PasskeyRegistration
    , PasskeySetupPrompt
    , PasskeyActionButton
    , PasskeyDeviceName
    , PasskeyStatus
    , PasskeyRecovery
    , PasskeyDismissal
    ) where

import Application.Helper.FrontendContract.DSL
import Prelude (String)

-- | Passkey workflow DOM, local configuration, and every app-owned JSON shape
-- crossing the Haskell/browser boundary. Native WebAuthn platform objects and
-- extension-result semantics remain inside the focused TypeScript adapter.
data Passkey

-- Local DOM flow configuration ------------------------------------------------

data PasskeyFlowConfig
data Login
data Registration
data SetupPrompt

data BeginUrl
data FinishUrl
data SuccessRedirect
data StatusKey
data WaitingMessage
data SuccessMessage
data UnsupportedMessage
data FailureMessage
data PendingLabel
data CancelledMessage
data PromptUserKey
data SetupPromptMode

data PasskeySetupPromptMode
data FirstPasskey
data AdditionalDevice

data PasskeyFirstPasskeyMode
data PasskeyAdditionalDeviceMode

type PasskeyStatusFields =
    '[ Field BeginUrl 'WireText
     , Field FinishUrl 'WireText
     , OptionalField SuccessRedirect 'WireText
     , Field StatusKey 'WireText
     , Field WaitingMessage 'WireText
     , Field SuccessMessage 'WireText
     , Field UnsupportedMessage 'WireText
     , Field FailureMessage 'WireText
     , Field PendingLabel 'WireText
     , Field CancelledMessage 'WireText
     ]

-- Exact passkey wire DTOs -----------------------------------------------------

data PasskeyCredentialType
data PublicKey

data PasskeyAuthenticatorAttachment
data Platform
data CrossPlatform

data PasskeyResidentKeyRequirement
data PasskeyUserVerificationRequirement
data Discouraged
data Preferred
data Required

data PasskeyAttestationConveyancePreference
data None
data Indirect
data Direct
data Enterprise

data PasskeyRelyingParty
data PasskeyUserEntity
data PasskeyCredentialParameter
data PasskeyCredentialDescriptor
data PasskeyAuthenticatorSelection
data PasskeyRegistrationOptions
data PasskeyAuthenticationOptions

data PasskeyAttestationResponse
data PasskeyRegistrationRequest
data PasskeyAssertionResponse
data PasskeyAuthenticationRequest

data PasskeyFinishResponse
data Authenticated
data Registered
data SetupRegistered

data PasskeyErrorResponse
data Failure
data Redirect

data Rp
data User
data Id
data Name
data DisplayName
data Challenge
data PubKeyCredParams
data Timeout
data ExcludeCredentials
data AuthenticatorSelection
data Attestation
data Type
data Alg
data AuthenticatorAttachment
data ResidentKey
data RequireResidentKey
data UserVerification
data RpId
data AllowCredentials
data RawId
data Response

-- The external WebAuthn spelling is clientDataJSON. Splitting the acronym in
-- the private marker keeps that exact lower-camel field under normal naming.
data ClientDataJ_S_O_N_Field
{-# ANN type ClientDataJ_S_O_N_Field ("HLint: ignore Use camelCase" :: String) #-}
type ClientDataJSON = ClientDataJ_S_O_N_Field

data AttestationObject
data Transports
data AuthenticatorData
data Signature
data UserHandle
data ClientExtensionResults
data UserId
data RedirectTo
data RecoveryCode
data Error

data PasskeyLogin
data PasskeyRegistration
data PasskeySetupPrompt
data PasskeyActionButton
data PasskeyDeviceName
data PasskeyStatus
data PasskeyRecovery
data PasskeyDismissal

type PasskeyContract =
    Global Passkey
        '[ BrowserGuardSchema (Enum PasskeySetupPromptMode '[FirstPasskey, AdditionalDevice])
         , BrowserInboundSchema (TaggedUnion PasskeyFlowConfig
            '[ Case Login PasskeyStatusFields
             , Case Registration PasskeyStatusFields
             , Case SetupPrompt
                '[ Field PromptUserKey 'WireText
                 , Field SetupPromptMode ('WireRef PasskeySetupPromptMode)
                 ]
             ])
         , BrowserGuardSchema (Enum PasskeyCredentialType '[PublicKey])
         , BrowserGuardSchema (Enum PasskeyAuthenticatorAttachment '[Platform, CrossPlatform])
         , BrowserGuardSchema (Enum PasskeyResidentKeyRequirement '[Discouraged, Preferred, Required])
         , BrowserGuardSchema (Enum PasskeyUserVerificationRequirement '[Discouraged, Preferred, Required])
         , BrowserGuardSchema (Enum PasskeyAttestationConveyancePreference '[None, Indirect, Direct, Enterprise])
         , BrowserGuardSchema (Record PasskeyRelyingParty
            '[ Field Id 'WireText
             , Field Name 'WireText
             ])
         , BrowserGuardSchema (Record PasskeyUserEntity
            '[ Field Id 'WireText
             , Field DisplayName 'WireText
             , Field Name 'WireText
             ])
         , BrowserGuardSchema (Record PasskeyCredentialParameter
            '[ Field Type ('WireRef PasskeyCredentialType)
             , Field Alg 'WireInt
             ])
         , BrowserGuardSchema (Record PasskeyCredentialDescriptor
            '[ Field Type ('WireRef PasskeyCredentialType)
             , Field Id 'WireText
             ])
         , BrowserGuardSchema (Record PasskeyAuthenticatorSelection
            '[ OptionalField AuthenticatorAttachment ('WireRef PasskeyAuthenticatorAttachment)
             , Field ResidentKey ('WireRef PasskeyResidentKeyRequirement)
             , Field RequireResidentKey 'WireBool
             , Field UserVerification ('WireRef PasskeyUserVerificationRequirement)
             ])
         , BrowserInboundSchema (Record PasskeyRegistrationOptions
            '[ Field Rp ('WireRef PasskeyRelyingParty)
             , Field User ('WireRef PasskeyUserEntity)
             , Field Challenge 'WireText
             , Field PubKeyCredParams ('WireList ('WireRef PasskeyCredentialParameter))
             , Field Timeout 'WireInt
             , Field ExcludeCredentials ('WireList ('WireRef PasskeyCredentialDescriptor))
             , Field AuthenticatorSelection ('WireRef PasskeyAuthenticatorSelection)
             , Field Attestation ('WireRef PasskeyAttestationConveyancePreference)
             ])
         , BrowserInboundSchema (Record PasskeyAuthenticationOptions
            '[ Field Challenge 'WireText
             , Field Timeout 'WireInt
             , Field RpId 'WireText
             , Field AllowCredentials ('WireList ('WireRef PasskeyCredentialDescriptor))
             , Field UserVerification ('WireRef PasskeyUserVerificationRequirement)
             ])
         , BrowserTypeSchema (Record PasskeyAttestationResponse
            '[ Field ClientDataJSON 'WireText
             , Field AttestationObject 'WireText
             , Field Transports ('WireList 'WireText)
             ])
         , BrowserOutboundSchema (Record PasskeyRegistrationRequest
            '[ Field RawId 'WireText
             , Field Response ('WireRef PasskeyAttestationResponse)
             , Field ClientExtensionResults 'WireUnknown
             , OptionalField Name 'WireText
             ])
         , BrowserTypeSchema (Record PasskeyAssertionResponse
            '[ Field ClientDataJSON 'WireText
             , Field AuthenticatorData 'WireText
             , Field Signature 'WireText
             , NullableField UserHandle 'WireText
             ])
         , BrowserOutboundSchema (Record PasskeyAuthenticationRequest
            '[ Field RawId 'WireText
             , Field Response ('WireRef PasskeyAssertionResponse)
             , Field ClientExtensionResults 'WireUnknown
             ])
         , BrowserInboundSchema (TaggedUnion PasskeyFinishResponse
            '[ Case Authenticated
                '[ Field UserId 'WireUUID
                 , Field RedirectTo 'WireText
                 ]
             , Case Registered
                '[ Field UserId 'WireUUID
                 , NullableField RecoveryCode 'WireText
                 ]
             , Case SetupRegistered
                '[ Field UserId 'WireUUID
                 , Field RedirectTo 'WireText
                 ]
             ])
         , BrowserInboundSchema (TaggedUnion PasskeyErrorResponse
            '[ Case Failure
                '[ Field Error 'WireText
                 ]
             , Case Redirect
                '[ Field Error 'WireText
                 , Field RedirectTo 'WireText
                 ]
             ])
         , Constant PasskeyFirstPasskeyMode "first-passkey"
         , Constant PasskeyAdditionalDeviceMode "additional-device"
         , DomAttr PasskeyLogin
         , DomAttr PasskeyRegistration
         , DomAttr PasskeySetupPrompt
         , DomAttr PasskeyActionButton
         , DomAttr PasskeyDeviceName
         , DomAttr PasskeyStatus
         , DomAttr PasskeyRecovery
         , DomAttr PasskeyDismissal
         , DomAttr PasskeyFlowConfig
         ]
