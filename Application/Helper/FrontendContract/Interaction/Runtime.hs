module Application.Helper.FrontendContract.Interaction.Runtime
    ( dragIntervalAttrs
    , dragAxisAttrs
    , dragPositionAttrs
    , dragTargetPreviewAttrs
    , nativeContextMenuDisabledAttrs
    ) where

import qualified Application.Helper.FrontendContract.Interaction as Contract
import Application.Helper.FrontendContract.Values (domAttrValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

-- | Coordinates are arbitrary integer units in a shared axis. The feature
-- supplies every permitted start and its complete display label; the browser
-- selects a position but never calculates business boundaries or display copy.
dragIntervalAttrs :: Int -> Int -> [(Int, Text)] -> [(Text, Text)]
dragIntervalAttrs range extent choices =
    [(domAttrValue @Contract.DragIntervalConfig, encode config)]
  where
    config = recordValue @Contract.DragIntervalConfig
        ( requiredField @Contract.RangeSize range
            &: requiredField @Contract.Extent extent
            &: requiredField @Contract.Positions (map fst choices)
            &: requiredField @Contract.Labels (map snd choices)
            &: noFields
        )
    encode = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode

-- | Reserve browser context menus for an explicitly marked interaction region,
-- including its background and subsequently replaced descendants.
nativeContextMenuDisabledAttrs :: [(Text, Text)]
nativeContextMenuDisabledAttrs = [(domAttrValue @Contract.NativeContextMenuDisabled, "true")]

dragAxisAttrs :: [(Text, Text)]
dragAxisAttrs = [(domAttrValue @Contract.DragAxis, "true")]

-- | Opt a plain-text hover preview into disposable interval landing feedback.
dragTargetPreviewAttrs :: [(Text, Text)]
dragTargetPreviewAttrs = [(domAttrValue @Contract.DragTargetPreview, "true")]

dragPositionAttrs :: Int -> [(Text, Text)]
dragPositionAttrs position = [(domAttrValue @Contract.DragPosition, tshow position)]
