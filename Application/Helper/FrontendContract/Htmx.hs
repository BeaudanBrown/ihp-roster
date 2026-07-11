{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Htmx
    ( HtmxActionCustom (..)
    , HtmxActionMetadata (..)
    , HtmxMethod (..)
    , HtmxPushUrl (..)
    , defaultHtmxActionMetadata
    , htmxActionConfigJson
    , htmxActionMetadataFromOptions
    , htmxActionMetadataFromSurfaceOptions
    , htmxActionOptionAttrPairs
    , htmxCustomAttrPairs
    , htmxMethodAttr
    , htmxMethodAttrSegment
    , htmxMethodFromText
    , htmxMethodText
    , htmxStandardMethodText
    ) where

import qualified Application.Helper.FrontendContract.IR as IR
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import IHP.Prelude

-- | Shared generated HTMX request method vocabulary used by contract-owned
-- request primitives. Surface/AppShell/legacy overlay may keep namespaced DSL
-- constructors, but they should lower to this value model before rendering or
-- serialising browser-visible request metadata.
data HtmxMethod
    = HtmxGet
    | HtmxPost
    | HtmxPut
    | HtmxPatch
    | HtmxDelete
    deriving (Eq, Show)

data HtmxPushUrl
    = HtmxPushUrlTrue
    | HtmxPushUrlFalse
    deriving (Eq, Show)

data HtmxActionCustom = HtmxActionCustom
    { customMarker :: !Text
    , customReason :: !Text
    }
    deriving (Eq, Show)

data HtmxActionMetadata = HtmxActionMetadata
    { htmxMethod    :: !(Maybe HtmxMethod)
    , htmxTrigger   :: !(Maybe Text)
    , htmxInclude   :: !(Maybe Text)
    , htmxSync      :: !(Maybe Text)
    , htmxIndicator :: !(Maybe Text)
    , htmxConfirm   :: !(Maybe Text)
    , htmxSelect    :: !(Maybe Text)
    , htmxTarget    :: !(Maybe Text)
    , htmxSwap      :: !(Maybe Text)
    , htmxPushUrl   :: !(Maybe HtmxPushUrl)
    , htmxCustom    :: ![HtmxActionCustom]
    }
    deriving (Eq, Show)

defaultHtmxActionMetadata :: HtmxActionMetadata
defaultHtmxActionMetadata = HtmxActionMetadata
    { htmxMethod = Nothing
    , htmxTrigger = Nothing
    , htmxInclude = Nothing
    , htmxSync = Nothing
    , htmxIndicator = Nothing
    , htmxConfirm = Nothing
    , htmxSelect = Nothing
    , htmxTarget = Nothing
    , htmxSwap = Nothing
    , htmxPushUrl = Nothing
    , htmxCustom = []
    }

htmxActionMetadataFromOptions :: [IR.HtmxActionOptionIR] -> HtmxActionMetadata
htmxActionMetadataFromOptions options = HtmxActionMetadata
    { htmxMethod = listToMaybe (mapMaybe method options)
    , htmxTrigger = listToMaybe [value | IR.HtmxActionTriggerIR value <- options]
    , htmxInclude = listToMaybe [value | IR.HtmxActionIncludeIR value <- options]
    , htmxSync = listToMaybe [value | IR.HtmxActionSyncIR value <- options]
    , htmxIndicator = listToMaybe [value | IR.HtmxActionIndicatorIR value <- options]
    , htmxConfirm = listToMaybe [value | IR.HtmxActionConfirmIR value <- options]
    , htmxSelect = listToMaybe [value | IR.HtmxActionSelectIR value <- options]
    , htmxTarget = listToMaybe [value | IR.HtmxActionTargetIR value <- options]
    , htmxSwap = listToMaybe [value | IR.HtmxActionSwapIR value <- options]
    , htmxPushUrl = listToMaybe [if value then HtmxPushUrlTrue else HtmxPushUrlFalse | IR.HtmxActionPushUrlIR value <- options]
    , htmxCustom = [HtmxActionCustom marker reason | IR.HtmxActionCustomHtmxIR marker reason <- options]
    }
    where
        method = \case
            IR.HtmxActionMethodIR value -> htmxMethodFromText value
            _ -> Nothing

htmxActionMetadataFromSurfaceOptions :: [SurfaceIR.OptionIR] -> HtmxActionMetadata
htmxActionMetadataFromSurfaceOptions options = HtmxActionMetadata
    { htmxMethod = listToMaybe (mapMaybe method options)
    , htmxTrigger = listToMaybe [value | SurfaceIR.HtmxTriggerOption value <- options]
    , htmxInclude = listToMaybe [value | SurfaceIR.HtmxIncludeOption value <- options]
    , htmxSync = listToMaybe [value | SurfaceIR.HtmxSyncOption value <- options]
    , htmxIndicator = listToMaybe [value | SurfaceIR.HtmxIndicatorOption value <- options]
    , htmxConfirm = listToMaybe [value | SurfaceIR.HtmxConfirmOption value <- options]
    , htmxSelect = listToMaybe [value | SurfaceIR.HtmxSelectOption value <- options]
    , htmxTarget = listToMaybe [value | SurfaceIR.HtmxTargetOption value <- options]
    , htmxSwap = listToMaybe [value | SurfaceIR.HtmxSwapOption value <- options]
    , htmxPushUrl = listToMaybe [convertPushUrl value | SurfaceIR.HtmxPushUrlOption value <- options]
    , htmxCustom = [HtmxActionCustom marker reason | SurfaceIR.CustomHtmxOption marker reason <- options]
    }
    where
        method = \case
            SurfaceIR.HtmxMethodOption value -> Just (convertMethod value)
            _ -> Nothing

convertMethod :: SurfaceIR.HtmxMethodIR -> HtmxMethod
convertMethod = \case
    SurfaceIR.HtmxGetIR -> HtmxGet
    SurfaceIR.HtmxPostIR -> HtmxPost
    SurfaceIR.HtmxPutIR -> HtmxPut
    SurfaceIR.HtmxPatchIR -> HtmxPatch
    SurfaceIR.HtmxDeleteIR -> HtmxDelete

convertPushUrl :: SurfaceIR.HtmxPushUrlIR -> HtmxPushUrl
convertPushUrl = \case
    SurfaceIR.HtmxPushUrlTrueIR -> HtmxPushUrlTrue
    SurfaceIR.HtmxPushUrlFalseIR -> HtmxPushUrlFalse

htmxActionOptionAttrPairs :: HtmxActionMetadata -> [(Text, Text)]
htmxActionOptionAttrPairs metadata =
    maybePair "hx-trigger" metadata.htmxTrigger
        <> maybePair "hx-include" metadata.htmxInclude
        <> maybePair "hx-sync" metadata.htmxSync
        <> maybePair "hx-indicator" metadata.htmxIndicator
        <> maybePair "hx-confirm" metadata.htmxConfirm
        <> maybePair "hx-select" (fmap htmxSelector metadata.htmxSelect)
        <> maybePair "hx-target" (fmap htmxSelector metadata.htmxTarget)
        <> maybePair "hx-swap" metadata.htmxSwap
        <> maybePair "hx-push-url" (fmap htmxPushUrlText metadata.htmxPushUrl)

htmxSelector :: Text -> Text
htmxSelector value
    | any (`Text.isPrefixOf` value) ["#", ".", "["] = value
    | otherwise = "#" <> value

htmxCustomAttrPairs :: HtmxActionMetadata -> Text -> Text -> [(Text, Text)] -> [(Text, Text)]
htmxCustomAttrPairs metadata actionName marker attrs
    | marker `elem` declaredMarkers = attrs
    | otherwise = error ("undeclared custom HTMX marker " <> cs marker <> " for action " <> cs actionName)
    where
        declaredMarkers = fmap (.customMarker) metadata.htmxCustom

htmxMethodAttr :: HtmxMethod -> Text
htmxMethodAttr method = "hx-" <> htmxMethodAttrSegment method

htmxMethodAttrSegment :: HtmxMethod -> Text
htmxMethodAttrSegment = \case
    HtmxGet -> "get"
    HtmxPost -> "post"
    HtmxPut -> "put"
    HtmxPatch -> "patch"
    HtmxDelete -> "delete"

htmxMethodText :: HtmxMethod -> Text
htmxMethodText = Text.toUpper . htmxMethodAttrSegment

htmxMethodFromText :: Text -> Maybe HtmxMethod
htmxMethodFromText = \case
    "get" -> Just HtmxGet
    "post" -> Just HtmxPost
    "put" -> Just HtmxPut
    "patch" -> Just HtmxPatch
    "delete" -> Just HtmxDelete
    _ -> Nothing

htmxStandardMethodText :: HtmxMethod -> Text
htmxStandardMethodText = \case
    HtmxGet -> "get"
    HtmxPost -> "post"
    HtmxPut -> "post"
    HtmxPatch -> "post"
    HtmxDelete -> "post"

htmxActionConfigJson :: Text -> [Text] -> HtmxActionMetadata -> Text
htmxActionConfigJson name fields metadata =
    Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode (htmxActionConfigToJson name fields metadata)))

htmxActionConfigToJson :: Text -> [Text] -> HtmxActionMetadata -> Aeson.Value
htmxActionConfigToJson name fields metadata =
    Aeson.object
        [ "name" Aeson..= name
        , "fields" Aeson..= fields
        , "htmx" Aeson..= Aeson.object
            [ "method" Aeson..= fmap htmxMethodAttrSegment metadata.htmxMethod
            , "trigger" Aeson..= metadata.htmxTrigger
            , "include" Aeson..= metadata.htmxInclude
            , "sync" Aeson..= metadata.htmxSync
            , "indicator" Aeson..= metadata.htmxIndicator
            , "confirm" Aeson..= metadata.htmxConfirm
            , "select" Aeson..= metadata.htmxSelect
            , "target" Aeson..= metadata.htmxTarget
            , "swap" Aeson..= metadata.htmxSwap
            , "pushUrl" Aeson..= fmap (== HtmxPushUrlTrue) metadata.htmxPushUrl
            , "custom" Aeson..= [Aeson.object ["name" Aeson..= custom.customMarker, "reason" Aeson..= custom.customReason] | custom <- metadata.htmxCustom]
            ]
        ]

htmxPushUrlText :: HtmxPushUrl -> Text
htmxPushUrlText = \case
    HtmxPushUrlTrue -> "true"
    HtmxPushUrlFalse -> "false"

maybePair :: Text -> Maybe Text -> [(Text, Text)]
maybePair name = \case
    Nothing -> []
    Just value -> [(name, value)]
