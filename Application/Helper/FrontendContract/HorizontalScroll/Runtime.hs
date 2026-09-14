{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.HorizontalScroll.Runtime
    ( HorizontalSnapConfig (..)
    , HorizontalSnapGroupSource (..)
    , HorizontalDragConfig (..)
    , HorizontalScrollDom (..)
    , canonicalHorizontalScrollDom
    , horizontalSnapAttrs
    , horizontalDragAttrs
    ) where

import Application.Error.Parser (parserFailure)
import Application.Error.Startup (startupInvariantFailure)
import qualified Application.Helper.FrontendContract.HorizontalScroll as Contract
import Application.Helper.FrontendContract.Values (domAttrValue,
                                                   enumLiteralValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

-- | Equal groups may be supplied directly or read from one Haskell-owned CSS
-- custom property on a local ancestor.
data HorizontalSnapGroupSource
    = HorizontalSnapGroupCount !Int
    | HorizontalSnapGroupProperty
        { horizontalSnapGroupProperty      :: !Text
        , horizontalSnapGroupScopeSelector :: !Text
        }
    deriving (Eq, Show)

data HorizontalSnapConfig
    = HorizontalSnapNearestItem !Text
    | HorizontalSnapEqualGroups !HorizontalSnapGroupSource
    deriving (Eq, Show)

newtype HorizontalDragConfig = HorizontalDragConfig
    { horizontalDragIgnoreSelector :: Maybe Text
    }
    deriving (Eq, Show)

data HorizontalScrollDom = HorizontalScrollDom
    { horizontalScrollSnapAttribute :: !Text
    , horizontalSnapConfigAttribute :: !Text
    , horizontalScrollDragAttribute :: !Text
    , horizontalDragConfigAttribute :: !Text
    }
    deriving (Eq, Show)

data HorizontalSnapWireConfig = HorizontalSnapWireConfig
    { wireSnapMode           :: !Text
    , wireItemSelector       :: !(Maybe Text)
    , wireGroupCount         :: !(Maybe Int)
    , wireGroupProperty      :: !(Maybe Text)
    , wireGroupScopeSelector :: !(Maybe Text)
    }

canonicalHorizontalScrollDom :: HorizontalScrollDom
canonicalHorizontalScrollDom = HorizontalScrollDom
    { horizontalScrollSnapAttribute = domAttrValue @Contract.HorizontalScrollSnap
    , horizontalSnapConfigAttribute = domAttrValue @Contract.HorizontalSnapConfig
    , horizontalScrollDragAttribute = domAttrValue @Contract.HorizontalScrollDrag
    , horizontalDragConfigAttribute = domAttrValue @Contract.HorizontalDragConfig
    }

horizontalSnapAttrs :: HorizontalSnapConfig -> [(Text, Text)]
horizontalSnapAttrs config =
    [ (canonicalHorizontalScrollDom.horizontalScrollSnapAttribute, "true")
    , (canonicalHorizontalScrollDom.horizontalSnapConfigAttribute, horizontalSnapConfigJson config)
    ]

horizontalDragAttrs :: HorizontalDragConfig -> [(Text, Text)]
horizontalDragAttrs config =
    [ (canonicalHorizontalScrollDom.horizontalScrollDragAttribute, "true")
    , (canonicalHorizontalScrollDom.horizontalDragConfigAttribute, horizontalDragConfigJson config)
    ]

horizontalSnapConfigJson :: HorizontalSnapConfig -> Text
horizontalSnapConfigJson rawConfig =
    encodeContractValue $ case validateSnapConfig rawConfig of
        HorizontalSnapNearestItem itemSelector ->
            horizontalSnapConfigValue HorizontalSnapWireConfig
                { wireSnapMode = enumLiteralValue @Contract.HorizontalSnapMode @Contract.NearestItem
                , wireItemSelector = Just itemSelector
                , wireGroupCount = Nothing
                , wireGroupProperty = Nothing
                , wireGroupScopeSelector = Nothing
                }
        HorizontalSnapEqualGroups (HorizontalSnapGroupCount groupCount) ->
            horizontalSnapConfigValue HorizontalSnapWireConfig
                { wireSnapMode = enumLiteralValue @Contract.HorizontalSnapMode @Contract.EqualGroups
                , wireItemSelector = Nothing
                , wireGroupCount = Just groupCount
                , wireGroupProperty = Nothing
                , wireGroupScopeSelector = Nothing
                }
        HorizontalSnapEqualGroups (HorizontalSnapGroupProperty { horizontalSnapGroupProperty, horizontalSnapGroupScopeSelector }) ->
            horizontalSnapConfigValue HorizontalSnapWireConfig
                { wireSnapMode = enumLiteralValue @Contract.HorizontalSnapMode @Contract.EqualGroups
                , wireItemSelector = Nothing
                , wireGroupCount = Nothing
                , wireGroupProperty = Just horizontalSnapGroupProperty
                , wireGroupScopeSelector = Just horizontalSnapGroupScopeSelector
                }

horizontalSnapConfigValue :: HorizontalSnapWireConfig -> Aeson.Value
horizontalSnapConfigValue HorizontalSnapWireConfig { .. } =
    recordValue @Contract.HorizontalSnapConfig
        ( requiredField @Contract.SnapMode wireSnapMode
            &: nullableField @Contract.ItemSelector wireItemSelector
            &: nullableField @Contract.GroupCount wireGroupCount
            &: nullableField @Contract.GroupProperty wireGroupProperty
            &: nullableField @Contract.GroupScopeSelector wireGroupScopeSelector
            &: noFields
        )

horizontalDragConfigJson :: HorizontalDragConfig -> Text
horizontalDragConfigJson (HorizontalDragConfig rawIgnoreSelector) =
    encodeContractValue $ recordValue @Contract.HorizontalDragConfig
        (nullableField @Contract.IgnoreSelector (validateOptionalSelector "Horizontal drag ignore selector" rawIgnoreSelector) &: noFields)

validateSnapConfig :: HorizontalSnapConfig -> HorizontalSnapConfig
validateSnapConfig config = case config of
    HorizontalSnapNearestItem selector ->
        HorizontalSnapNearestItem (validateRequiredText "Horizontal snap item selector" selector)
    HorizontalSnapEqualGroups (HorizontalSnapGroupCount count)
        | count <= 0 -> startupInvariantFailure "Horizontal snap group count must be positive"
        | otherwise -> config
    HorizontalSnapEqualGroups (HorizontalSnapGroupProperty { horizontalSnapGroupProperty, horizontalSnapGroupScopeSelector }) ->
        HorizontalSnapEqualGroups HorizontalSnapGroupProperty
            { horizontalSnapGroupProperty = validateRequiredText "Horizontal snap group property" horizontalSnapGroupProperty
            , horizontalSnapGroupScopeSelector = validateRequiredText "Horizontal snap group scope selector" horizontalSnapGroupScopeSelector
            }

validateOptionalSelector :: Text -> Maybe Text -> Maybe Text
validateOptionalSelector _ Nothing = Nothing
validateOptionalSelector label (Just value) = Just (validateRequiredText label value)

validateRequiredText :: Text -> Text -> Text
validateRequiredText label value
    | Text.null (Text.strip value) = startupInvariantFailure (cs label <> " must not be empty")
    | otherwise = value

instance ContractReference Contract.HorizontalSnapMode where
    type ContractReferenceValue Contract.HorizontalSnapMode = Text
    contractReferenceJson = Aeson.String
    parseContractReference = Aeson.withText "HorizontalSnapMode" \value ->
        if value `elem` horizontalSnapModeValues
            then pure value
            else parserFailure "Unknown HorizontalSnapMode"

horizontalSnapModeValues :: [Text]
horizontalSnapModeValues =
    [ enumLiteralValue @Contract.HorizontalSnapMode @Contract.EqualGroups
    , enumLiteralValue @Contract.HorizontalSnapMode @Contract.NearestItem
    ]


encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
