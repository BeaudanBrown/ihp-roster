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
import qualified Data.Text as Text
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
    , htmxTrigger = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionTriggerIR value <- options]
    , htmxInclude = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionIncludeIR value <- options]
    , htmxSync = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionSyncIR value <- options]
    , htmxIndicator = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionIndicatorIR value <- options]
    , htmxConfirm = listToMaybe [value | IR.HtmxActionConfirmIR value <- options]
    , htmxSelect = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionSelectIR value <- options]
    , htmxTarget = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionTargetIR value <- options]
    , htmxSwap = listToMaybe [IR.htmxSyntaxText value | IR.HtmxActionSwapIR value <- options]
    , htmxPushUrl = listToMaybe [convertPushUrl value | IR.HtmxActionPushUrlIR value <- options]
    , htmxCustom = [HtmxActionCustom marker reason | IR.HtmxActionCustomHtmxIR marker reason <- options]
    }
    where
        method = \case
            IR.HtmxActionMethodIR value -> Just (convertMethod value)
            _ -> Nothing

htmxActionMetadataFromSurfaceOptions :: [IR.OptionIR] -> HtmxActionMetadata
htmxActionMetadataFromSurfaceOptions =
    htmxActionMetadataFromOptions . IR.optionHtmxActionOptions

convertMethod :: IR.HtmxMethodIR -> HtmxMethod
convertMethod = \case
    IR.HtmxGetIR -> HtmxGet
    IR.HtmxPostIR -> HtmxPost
    IR.HtmxPutIR -> HtmxPut
    IR.HtmxPatchIR -> HtmxPatch
    IR.HtmxDeleteIR -> HtmxDelete

convertPushUrl :: IR.HtmxPushUrlIR -> HtmxPushUrl
convertPushUrl = \case
    IR.HtmxPushUrlTrueIR -> HtmxPushUrlTrue
    IR.HtmxPushUrlFalseIR -> HtmxPushUrlFalse

htmxActionOptionAttrPairs :: HtmxActionMetadata -> [(Text, Text)]
htmxActionOptionAttrPairs metadata =
    maybePair "hx-trigger" metadata.htmxTrigger
        <> maybePair "hx-include" metadata.htmxInclude
        <> maybePair "hx-sync" metadata.htmxSync
        <> maybePair "hx-indicator" metadata.htmxIndicator
        <> maybePair "hx-confirm" metadata.htmxConfirm
        <> maybePair "hx-select" metadata.htmxSelect
        <> maybePair "hx-target" metadata.htmxTarget
        <> maybePair "hx-swap" metadata.htmxSwap
        <> maybePair "hx-push-url" (fmap htmxPushUrlText metadata.htmxPushUrl)

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

htmxPushUrlText :: HtmxPushUrl -> Text
htmxPushUrlText = \case
    HtmxPushUrlTrue -> "true"
    HtmxPushUrlFalse -> "false"

maybePair :: Text -> Maybe Text -> [(Text, Text)]
maybePair name = \case
    Nothing -> []
    Just value -> [(name, value)]
