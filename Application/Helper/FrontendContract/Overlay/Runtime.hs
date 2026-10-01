{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Overlay.Runtime
    ( OverlayDom (..)
    , DialogDismissalGuardConfigValue (..)
    , canonicalOverlayDom
    , dialogBackdropAttrs
    , dialogDismissalGuardAttrs
    , dialogCloseAttrs
    , dialogConfirmationAttrs
    , dialogFocusRegionAttrs
    , dialogKeyboardAttrs
    , dialogMountAttrs
    , dialogPointerDismissBlurAttrs
    , dialogSubmitAttrs
    , navigationLoadingAttrs
    , toastCloseAttrs
    , toastMountAttrs
    ) where

import Application.Error.Startup (startupInvariantFailure)
import qualified Application.Helper.FrontendContract.Overlay as Contract
import Application.Helper.FrontendContract.Values (domAttrValue, domIdValue,
                                                   eventNameValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

data OverlayDom = OverlayDom
    { overlayDialogMountId               :: !Text
    , overlayToastMountId                :: !Text
    , overlayDialogDismissedEventName    :: !Text
    , overlayDialogMountAttribute        :: !Text
    , overlayDialogConfirmationAttribute :: !Text
    , overlayDialogBackdropAttribute     :: !Text
    , overlayDialogCloseAttribute        :: !Text
    , overlayDialogSubmitAttribute       :: !Text
    , overlayDialogSubmitConfigAttribute :: !Text
    , overlayDialogDismissalGuardAttribute :: !Text
    , overlayDialogDismissalGuardConfigAttribute :: !Text
    , overlayDialogBlockingAttribute     :: !Text
    , overlayDialogKeyboardAttribute     :: !Text
    , overlayDialogFocusRegionAttribute  :: !Text
    , overlayDialogPointerDismissBlurAttribute :: !Text
    , overlayNavigationLoadingAttribute  :: !Text
    , overlayNavigationConfigAttribute   :: !Text
    , overlayToastMountAttribute         :: !Text
    , overlayToastCloseAttribute         :: !Text
    , overlayToastConfigAttribute        :: !Text
    }
    deriving (Eq, Show)

canonicalOverlayDom :: OverlayDom
canonicalOverlayDom = OverlayDom
    { overlayDialogMountId = domIdValue @Contract.DialogOverlayMount
    , overlayToastMountId = domIdValue @Contract.ToastOverlayMount
    , overlayDialogDismissedEventName = eventNameValue @Contract.DialogDismissed
    , overlayDialogMountAttribute = domAttrValue @Contract.DialogMount
    , overlayDialogConfirmationAttribute = domAttrValue @Contract.DialogConfirmation
    , overlayDialogBackdropAttribute = domAttrValue @Contract.DialogBackdrop
    , overlayDialogCloseAttribute = domAttrValue @Contract.DialogClose
    , overlayDialogSubmitAttribute = domAttrValue @Contract.DialogSubmit
    , overlayDialogSubmitConfigAttribute = domAttrValue @Contract.DialogSubmitConfig
    , overlayDialogDismissalGuardAttribute = domAttrValue @Contract.DialogDismissalGuard
    , overlayDialogDismissalGuardConfigAttribute = domAttrValue @Contract.DialogDismissalGuardConfig
    , overlayDialogBlockingAttribute = domAttrValue @Contract.DialogBlocking
    , overlayDialogKeyboardAttribute = domAttrValue @Contract.DialogKeyboard
    , overlayDialogFocusRegionAttribute = domAttrValue @Contract.DialogFocusRegion
    , overlayDialogPointerDismissBlurAttribute = domAttrValue @Contract.DialogPointerDismissBlur
    , overlayNavigationLoadingAttribute = domAttrValue @Contract.NavigationLoading
    , overlayNavigationConfigAttribute = domAttrValue @Contract.NavigationLoadingConfig
    , overlayToastMountAttribute = domAttrValue @Contract.ToastMount
    , overlayToastCloseAttribute = domAttrValue @Contract.ToastClose
    , overlayToastConfigAttribute = domAttrValue @Contract.ToastConfig
    }

dialogMountAttrs :: [(Text, Text)]
dialogMountAttrs = roleAttrs canonicalOverlayDom.overlayDialogMountAttribute

dialogConfirmationAttrs :: [(Text, Text)]
dialogConfirmationAttrs = roleAttrs canonicalOverlayDom.overlayDialogConfirmationAttribute

dialogBackdropAttrs :: [(Text, Text)]
dialogBackdropAttrs = roleAttrs canonicalOverlayDom.overlayDialogBackdropAttribute

dialogCloseAttrs :: [(Text, Text)]
dialogCloseAttrs = roleAttrs canonicalOverlayDom.overlayDialogCloseAttribute

dialogKeyboardAttrs :: [(Text, Text)]
dialogKeyboardAttrs = roleAttrs canonicalOverlayDom.overlayDialogKeyboardAttribute

dialogFocusRegionAttrs :: [(Text, Text)]
dialogFocusRegionAttrs = roleAttrs canonicalOverlayDom.overlayDialogFocusRegionAttribute

-- | Opt in only this launcher to next-frame pointer-dismiss focus cleanup.
dialogPointerDismissBlurAttrs :: [(Text, Text)]
dialogPointerDismissBlurAttrs = roleAttrs canonicalOverlayDom.overlayDialogPointerDismissBlurAttribute

dialogSubmitAttrs :: Text -> [(Text, Text)]
dialogSubmitAttrs loadingLabel =
    roleAttrs canonicalOverlayDom.overlayDialogSubmitAttribute
        <> [(canonicalOverlayDom.overlayDialogSubmitConfigAttribute, dialogSubmitConfigJson loadingLabel)]

data DialogDismissalGuardConfigValue = DialogDismissalGuardConfigValue
    { dismissalGuardFormId            :: !Text
    , dismissalGuardImmediately       :: !Bool
    , dismissalGuardConfirmationTitle :: !Text
    , dismissalGuardKeepEditingLabel  :: !Text
    , dismissalGuardDiscardLabel      :: !Text
    }
    deriving (Eq, Show)

dialogDismissalGuardAttrs :: DialogDismissalGuardConfigValue -> [(Text, Text)]
dialogDismissalGuardAttrs config =
    roleAttrs canonicalOverlayDom.overlayDialogDismissalGuardAttribute
        <> [(canonicalOverlayDom.overlayDialogDismissalGuardConfigAttribute, dialogDismissalGuardConfigJson config)]

navigationLoadingAttrs :: Text -> Text -> [(Text, Text)]
navigationLoadingAttrs loadingTitle loadingMessage =
    roleAttrs canonicalOverlayDom.overlayNavigationLoadingAttribute
        <> [(canonicalOverlayDom.overlayNavigationConfigAttribute, navigationLoadingConfigJson loadingTitle loadingMessage)]

toastMountAttrs :: Int -> [(Text, Text)]
toastMountAttrs autoHideMs =
    roleAttrs canonicalOverlayDom.overlayToastMountAttribute
        <> [(canonicalOverlayDom.overlayToastConfigAttribute, toastConfigJson autoHideMs)]

toastCloseAttrs :: [(Text, Text)]
toastCloseAttrs = roleAttrs canonicalOverlayDom.overlayToastCloseAttribute

dialogSubmitConfigJson :: Text -> Text
dialogSubmitConfigJson loadingLabel
    | Text.null (Text.strip loadingLabel) = startupInvariantFailure "Dialog submit loading label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.DialogSubmitConfig
        (requiredField @Contract.LoadingLabel loadingLabel &: noFields)

dialogDismissalGuardConfigJson :: DialogDismissalGuardConfigValue -> Text
dialogDismissalGuardConfigJson DialogDismissalGuardConfigValue { .. }
    | Text.null (Text.strip dismissalGuardFormId) = startupInvariantFailure "Dialog dismissal guard form id must not be empty"
    | Text.null (Text.strip dismissalGuardConfirmationTitle) = startupInvariantFailure "Dialog dismissal guard confirmation title must not be empty"
    | Text.null (Text.strip dismissalGuardKeepEditingLabel) = startupInvariantFailure "Dialog dismissal guard keep-editing label must not be empty"
    | Text.null (Text.strip dismissalGuardDiscardLabel) = startupInvariantFailure "Dialog dismissal guard discard label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.DialogDismissalGuardConfig
        ( requiredField @Contract.FormId dismissalGuardFormId
            &: requiredField @Contract.GuardImmediately dismissalGuardImmediately
            &: requiredField @Contract.ConfirmationTitle dismissalGuardConfirmationTitle
            &: requiredField @Contract.KeepEditingLabel dismissalGuardKeepEditingLabel
            &: requiredField @Contract.DiscardLabel dismissalGuardDiscardLabel
            &: noFields
        )

navigationLoadingConfigJson :: Text -> Text -> Text
navigationLoadingConfigJson loadingTitle loadingMessage
    | Text.null (Text.strip loadingTitle) = startupInvariantFailure "Navigation loading title must not be empty"
    | Text.null (Text.strip loadingMessage) = startupInvariantFailure "Navigation loading message must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.NavigationLoadingConfig
        ( requiredField @Contract.LoadingTitle loadingTitle
            &: requiredField @Contract.LoadingMessage loadingMessage
            &: noFields
        )

toastConfigJson :: Int -> Text
toastConfigJson autoHideMs
    | autoHideMs < 0 = startupInvariantFailure "Toast auto-hide duration must not be negative"
    | otherwise = encodeContractValue $ recordValue @Contract.ToastConfig
        (requiredField @Contract.AutoHideMs autoHideMs &: noFields)

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
