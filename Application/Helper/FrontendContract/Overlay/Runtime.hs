{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Overlay.Runtime
    ( OverlayDom (..)
    , canonicalOverlayDom
    , dialogBackdropAttrs
    , dialogCloseAttrs
    , dialogFocusRegionAttrs
    , dialogKeyboardAttrs
    , dialogMountAttrs
    , dialogSubmitAttrs
    , navigationLoadingAttrs
    , toastCloseAttrs
    , toastMountAttrs
    ) where

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
    , overlayDialogBackdropAttribute     :: !Text
    , overlayDialogCloseAttribute        :: !Text
    , overlayDialogSubmitAttribute       :: !Text
    , overlayDialogSubmitConfigAttribute :: !Text
    , overlayDialogBlockingAttribute     :: !Text
    , overlayDialogKeyboardAttribute     :: !Text
    , overlayDialogFocusRegionAttribute  :: !Text
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
    , overlayDialogBackdropAttribute = domAttrValue @Contract.DialogBackdrop
    , overlayDialogCloseAttribute = domAttrValue @Contract.DialogClose
    , overlayDialogSubmitAttribute = domAttrValue @Contract.DialogSubmit
    , overlayDialogSubmitConfigAttribute = domAttrValue @Contract.DialogSubmitConfig
    , overlayDialogBlockingAttribute = domAttrValue @Contract.DialogBlocking
    , overlayDialogKeyboardAttribute = domAttrValue @Contract.DialogKeyboard
    , overlayDialogFocusRegionAttribute = domAttrValue @Contract.DialogFocusRegion
    , overlayNavigationLoadingAttribute = domAttrValue @Contract.NavigationLoading
    , overlayNavigationConfigAttribute = domAttrValue @Contract.NavigationLoadingConfig
    , overlayToastMountAttribute = domAttrValue @Contract.ToastMount
    , overlayToastCloseAttribute = domAttrValue @Contract.ToastClose
    , overlayToastConfigAttribute = domAttrValue @Contract.ToastConfig
    }

dialogMountAttrs :: [(Text, Text)]
dialogMountAttrs = roleAttrs canonicalOverlayDom.overlayDialogMountAttribute

dialogBackdropAttrs :: [(Text, Text)]
dialogBackdropAttrs = roleAttrs canonicalOverlayDom.overlayDialogBackdropAttribute

dialogCloseAttrs :: [(Text, Text)]
dialogCloseAttrs = roleAttrs canonicalOverlayDom.overlayDialogCloseAttribute

dialogKeyboardAttrs :: [(Text, Text)]
dialogKeyboardAttrs = roleAttrs canonicalOverlayDom.overlayDialogKeyboardAttribute

dialogFocusRegionAttrs :: [(Text, Text)]
dialogFocusRegionAttrs = roleAttrs canonicalOverlayDom.overlayDialogFocusRegionAttribute

dialogSubmitAttrs :: Text -> [(Text, Text)]
dialogSubmitAttrs loadingLabel =
    roleAttrs canonicalOverlayDom.overlayDialogSubmitAttribute
        <> [(canonicalOverlayDom.overlayDialogSubmitConfigAttribute, dialogSubmitConfigJson loadingLabel)]

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
    | Text.null (Text.strip loadingLabel) = error "Dialog submit loading label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.DialogSubmitConfig
        (requiredField @Contract.LoadingLabel loadingLabel &: noFields)

navigationLoadingConfigJson :: Text -> Text -> Text
navigationLoadingConfigJson loadingTitle loadingMessage
    | Text.null (Text.strip loadingTitle) = error "Navigation loading title must not be empty"
    | Text.null (Text.strip loadingMessage) = error "Navigation loading message must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.NavigationLoadingConfig
        ( requiredField @Contract.LoadingTitle loadingTitle
            &: requiredField @Contract.LoadingMessage loadingMessage
            &: noFields
        )

toastConfigJson :: Int -> Text
toastConfigJson autoHideMs
    | autoHideMs < 0 = error "Toast auto-hide duration must not be negative"
    | otherwise = encodeContractValue $ recordValue @Contract.ToastConfig
        (requiredField @Contract.AutoHideMs autoHideMs &: noFields)

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
