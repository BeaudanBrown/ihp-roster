module Application.Helper.FrontendContract.Interaction.Runtime
    ( dragIntervalAttrs
    , dragAxisAttrs
    , dragPositionAttrs
    , dragTargetPreviewAttrs
    , dragTargetPreviewStyle
    , nativeContextMenuDisabledAttrs
    ) where

import qualified Application.Helper.FrontendContract.Interaction as Contract
import Application.Helper.FrontendContract.Values (constantValue, domAttrValue)
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

-- | Opt into interval feedback, declaring whether a target-owned default is
-- available. Without one, only sources carrying their own interval can use it.
dragTargetPreviewAttrs :: Bool -> [(Text, Text)]
dragTargetPreviewAttrs hasDefault =
    [(domAttrValue @Contract.DragTargetPreview, "true")]
        <> if hasDefault then [(domAttrValue @Contract.DragTargetPreviewDefault, "true")] else []

-- | Interval offset/extent as percentages of the target's time-axis size.
-- Native hover and pointer sessions supply these same inputs to one CSS renderer.
dragTargetPreviewStyle :: Double -> Double -> Text
dragTargetPreviewStyle offsetPercent extentPercent =
    constantValue @Contract.DragPreviewOffsetProperty <> ":" <> tshow offsetPercent <> "%;"
        <> constantValue @Contract.DragPreviewExtentProperty <> ":" <> tshow extentPercent <> "%;"

dragPositionAttrs :: Int -> [(Text, Text)]
dragPositionAttrs position = [(domAttrValue @Contract.DragPosition, tshow position)]
