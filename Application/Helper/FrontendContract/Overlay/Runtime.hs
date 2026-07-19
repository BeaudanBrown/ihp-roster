{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Overlay.Runtime
    ( OverlayDom (..)
    , canonicalOverlayDom
    , dialogAutoSubmitOnceAttr
    , dialogBackdropAttrs
    , dialogCloseAttrs
    , dialogMountAttrs
    , dialogSubmitAttrs
    , toastCloseAttrs
    , toastMountAttrs
    ) where

import qualified Application.Helper.FrontendContract.Overlay as Contract
import Application.Helper.FrontendContract.Values (domAttrValue, domIdValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

data OverlayDom = OverlayDom
    { overlayDialogMountId               :: !Text
    , overlayToastMountId                :: !Text
    , overlayDialogMountAttribute        :: !Text
    , overlayDialogBackdropAttribute     :: !Text
    , overlayDialogCloseAttribute        :: !Text
    , overlayDialogSubmitAttribute       :: !Text
    , overlayDialogSubmitConfigAttribute :: !Text
    , overlayDialogAutoSubmitAttribute   :: !Text
    , overlayToastMountAttribute         :: !Text
    , overlayToastCloseAttribute         :: !Text
    , overlayToastConfigAttribute        :: !Text
    }
    deriving (Eq, Show)

canonicalOverlayDom :: OverlayDom
canonicalOverlayDom = OverlayDom
    { overlayDialogMountId = domIdValue @Contract.DialogOverlayMount
    , overlayToastMountId = domIdValue @Contract.ToastOverlayMount
    , overlayDialogMountAttribute = domAttrValue @Contract.DialogMount
    , overlayDialogBackdropAttribute = domAttrValue @Contract.DialogBackdrop
    , overlayDialogCloseAttribute = domAttrValue @Contract.DialogClose
    , overlayDialogSubmitAttribute = domAttrValue @Contract.DialogSubmit
    , overlayDialogSubmitConfigAttribute = domAttrValue @Contract.DialogSubmitConfig
    , overlayDialogAutoSubmitAttribute = domAttrValue @Contract.DialogAutoSubmitOnce
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

dialogSubmitAttrs :: Text -> [(Text, Text)]
dialogSubmitAttrs loadingLabel =
    roleAttrs canonicalOverlayDom.overlayDialogSubmitAttribute
        <> [(canonicalOverlayDom.overlayDialogSubmitConfigAttribute, dialogSubmitConfigJson loadingLabel)]

toastMountAttrs :: Int -> [(Text, Text)]
toastMountAttrs autoHideMs =
    roleAttrs canonicalOverlayDom.overlayToastMountAttribute
        <> [(canonicalOverlayDom.overlayToastConfigAttribute, toastConfigJson autoHideMs)]

toastCloseAttrs :: [(Text, Text)]
toastCloseAttrs = roleAttrs canonicalOverlayDom.overlayToastCloseAttribute

dialogAutoSubmitOnceAttr :: (Text, Text)
dialogAutoSubmitOnceAttr = (canonicalOverlayDom.overlayDialogAutoSubmitAttribute, "true")

dialogSubmitConfigJson :: Text -> Text
dialogSubmitConfigJson loadingLabel
    | Text.null (Text.strip loadingLabel) = error "Dialog submit loading label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.DialogSubmitConfig
        (requiredField @Contract.LoadingLabel loadingLabel &: noFields)

toastConfigJson :: Int -> Text
toastConfigJson autoHideMs
    | autoHideMs < 0 = error "Toast auto-hide duration must not be negative"
    | otherwise = encodeContractValue $ recordValue @Contract.ToastConfig
        (requiredField @Contract.AutoHideMs autoHideMs &: noFields)

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
