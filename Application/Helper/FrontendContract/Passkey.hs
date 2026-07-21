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

-- | Passkey workflow DOM and local mechanical configuration. Native WebAuthn
-- objects and app-owned server request/response DTOs remain outside this slice.
data Passkey

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

data PasskeyLogin
data PasskeyRegistration
data PasskeySetupPrompt
data PasskeyActionButton
data PasskeyDeviceName
data PasskeyStatus
data PasskeyRecovery
data PasskeyDismissal

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
