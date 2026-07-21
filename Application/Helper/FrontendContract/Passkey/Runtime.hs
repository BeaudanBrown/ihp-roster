{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}

module Application.Helper.FrontendContract.Passkey.Runtime
    ( PasskeyDom (..)
    , PasskeySetupPromptMode (..)
    , canonicalPasskeyDom
    , passkeyActionButtonAttrs
    , passkeyDeviceNameAttrs
    , passkeyDismissalAttrs
    , passkeyLoginAttrs
    , passkeyRecoveryAttrs
    , passkeyRegistrationAttrs
    , passkeySetupPromptAttrs
    , passkeySetupPromptModeFromValue
    , passkeySetupPromptModeValue
    , passkeyStatusAttrs
    ) where

import qualified Application.Helper.FrontendContract.Passkey as Contract
import Application.Helper.FrontendContract.Values (domAttrValue,
                                                   enumLiteralValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

data PasskeySetupPromptMode
    = PasskeyFirstPasskey
    | PasskeyAdditionalDevice
    deriving (Eq, Show)

data PasskeyDom = PasskeyDom
    { passkeyLoginAttribute        :: !Text
    , passkeyRegistrationAttribute :: !Text
    , passkeySetupPromptAttribute  :: !Text
    , passkeyActionButtonAttribute :: !Text
    , passkeyDeviceNameAttribute   :: !Text
    , passkeyStatusAttribute       :: !Text
    , passkeyRecoveryAttribute     :: !Text
    , passkeyDismissalAttribute    :: !Text
    , passkeyFlowConfigAttribute   :: !Text
    }
    deriving (Eq, Show)

canonicalPasskeyDom :: PasskeyDom
canonicalPasskeyDom = PasskeyDom
    { passkeyLoginAttribute = domAttrValue @Contract.PasskeyLogin
    , passkeyRegistrationAttribute = domAttrValue @Contract.PasskeyRegistration
    , passkeySetupPromptAttribute = domAttrValue @Contract.PasskeySetupPrompt
    , passkeyActionButtonAttribute = domAttrValue @Contract.PasskeyActionButton
    , passkeyDeviceNameAttribute = domAttrValue @Contract.PasskeyDeviceName
    , passkeyStatusAttribute = domAttrValue @Contract.PasskeyStatus
    , passkeyRecoveryAttribute = domAttrValue @Contract.PasskeyRecovery
    , passkeyDismissalAttribute = domAttrValue @Contract.PasskeyDismissal
    , passkeyFlowConfigAttribute = domAttrValue @Contract.PasskeyFlowConfig
    }

passkeyLoginAttrs :: Text -> Text -> Maybe Text -> [(Text, Text)]
passkeyLoginAttrs beginUrl finishUrl successRedirect =
    roleAttrs canonicalPasskeyDom.passkeyLoginAttribute
        <> configAttrs (loginFlowConfig beginUrl finishUrl successRedirect)

passkeyRegistrationAttrs :: Text -> Text -> Maybe Text -> [(Text, Text)]
passkeyRegistrationAttrs beginUrl finishUrl successRedirect =
    roleAttrs canonicalPasskeyDom.passkeyRegistrationAttribute
        <> configAttrs (registrationFlowConfig beginUrl finishUrl successRedirect)

passkeySetupPromptAttrs :: Text -> PasskeySetupPromptMode -> [(Text, Text)]
passkeySetupPromptAttrs promptUserKey setupPromptMode =
    roleAttrs canonicalPasskeyDom.passkeySetupPromptAttribute
        <> configAttrs
            ( taggedUnionValue @Contract.PasskeyFlowConfig @Contract.SetupPrompt
                ( requiredField @Contract.PromptUserKey (requiredText "Passkey prompt user key" promptUserKey)
                    &: requiredField @Contract.SetupPromptMode setupPromptMode
                    &: noFields
                )
            )

passkeyActionButtonAttrs :: [(Text, Text)]
passkeyActionButtonAttrs = roleAttrs canonicalPasskeyDom.passkeyActionButtonAttribute

passkeyDeviceNameAttrs :: [(Text, Text)]
passkeyDeviceNameAttrs = roleAttrs canonicalPasskeyDom.passkeyDeviceNameAttribute

passkeyStatusAttrs :: [(Text, Text)]
passkeyStatusAttrs = [(canonicalPasskeyDom.passkeyStatusAttribute, statusRelationshipKey)]

passkeyRecoveryAttrs :: [(Text, Text)]
passkeyRecoveryAttrs = [(canonicalPasskeyDom.passkeyRecoveryAttribute, statusRelationshipKey)]

passkeyDismissalAttrs :: [(Text, Text)]
passkeyDismissalAttrs = roleAttrs canonicalPasskeyDom.passkeyDismissalAttribute

loginFlowConfig :: Text -> Text -> Maybe Text -> Aeson.Value
loginFlowConfig beginUrl finishUrl successRedirect =
    taggedUnionValue @Contract.PasskeyFlowConfig @Contract.Login
        ( statusFlowFields
            beginUrl
            finishUrl
            successRedirect
            "Signed in."
            "No passkey was selected."
        )

registrationFlowConfig :: Text -> Text -> Maybe Text -> Aeson.Value
registrationFlowConfig beginUrl finishUrl successRedirect =
    taggedUnionValue @Contract.PasskeyFlowConfig @Contract.Registration
        ( statusFlowFields
            beginUrl
            finishUrl
            successRedirect
            "Passkey added."
            "Passkey registration was cancelled."
        )

statusFlowFields beginUrl finishUrl successRedirect successMessage cancelledMessage =
    requiredField @Contract.BeginUrl (requiredText "Passkey begin URL" beginUrl)
        &: requiredField @Contract.FinishUrl (requiredText "Passkey finish URL" finishUrl)
        &: optionalField @Contract.SuccessRedirect (requiredText "Passkey success redirect" <$> successRedirect)
        &: requiredField @Contract.StatusKey statusRelationshipKey
        &: requiredField @Contract.WaitingMessage "Waiting for your passkey..."
        &: requiredField @Contract.SuccessMessage successMessage
        &: requiredField @Contract.UnsupportedMessage "Passkeys are not supported in this browser."
        &: requiredField @Contract.FailureMessage "Passkey request failed."
        &: requiredField @Contract.PendingLabel "Please wait"
        &: requiredField @Contract.CancelledMessage cancelledMessage
        &: noFields

instance ContractReference Contract.PasskeySetupPromptMode where
    type ContractReferenceValue Contract.PasskeySetupPromptMode = PasskeySetupPromptMode
    contractReferenceJson = Aeson.String . setupPromptModeText
    parseContractReference = Aeson.withText "PasskeySetupPromptMode" \value ->
        maybe (fail "Unknown PasskeySetupPromptMode") pure (passkeySetupPromptModeFromValue value)

passkeySetupPromptModeFromValue :: Text -> Maybe PasskeySetupPromptMode
passkeySetupPromptModeFromValue value
    | value == setupPromptModeText PasskeyFirstPasskey = Just PasskeyFirstPasskey
    | value == setupPromptModeText PasskeyAdditionalDevice = Just PasskeyAdditionalDevice
    | otherwise = Nothing

passkeySetupPromptModeValue :: PasskeySetupPromptMode -> Text
passkeySetupPromptModeValue = setupPromptModeText

setupPromptModeText :: PasskeySetupPromptMode -> Text
setupPromptModeText PasskeyFirstPasskey =
    enumLiteralValue @Contract.PasskeySetupPromptMode @Contract.FirstPasskey
setupPromptModeText PasskeyAdditionalDevice =
    enumLiteralValue @Contract.PasskeySetupPromptMode @Contract.AdditionalDevice

requiredText :: Text -> Text -> Text
requiredText label value
    | Text.null (Text.strip value) = error (cs label <> " must not be empty")
    | otherwise = value

statusRelationshipKey :: Text
statusRelationshipKey = "status"

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]

configAttrs :: Aeson.Value -> [(Text, Text)]
configAttrs value =
    [(canonicalPasskeyDom.passkeyFlowConfigAttribute, encodeContractValue value)]

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
