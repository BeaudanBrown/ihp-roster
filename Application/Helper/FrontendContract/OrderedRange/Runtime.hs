{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.OrderedRange.Runtime
    ( OrderedRangeBrowserConfig (..)
    , OrderedRangeBrowserState (..)
    , OrderedRangeCrossingPolicy (..)
    , OrderedRangeDom (..)
    , canonicalOrderedRangeDom
    , orderedRangeAvailabilityAttrs
    , orderedRangeConfigJson
    , orderedRangeEndAttrs
    , orderedRangePositionStyle
    , orderedRangeRootAttrs
    , orderedRangeStartAttrs
    , orderedRangeStateJson
    ) where

import qualified Application.Helper.FrontendContract.OrderedRange as Contract
import Application.Helper.FrontendContract.Values (constantValue, domAttrValue,
                                                   enumLiteralValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Numeric (showFFloat)

-- | The only currently supported endpoint-crossing behavior. Adding another
-- constructor requires a generated contract case and exhaustive browser
-- implementation.
data OrderedRangeCrossingPolicy
    = ClampOtherEndpoint
    deriving (Eq, Show)

-- | Semantic range configuration supplied by Haskell. Labels correspond in
-- order to @[minimumValue, minimumValue + stepValue .. maximumValue]@.
data OrderedRangeBrowserConfig = OrderedRangeBrowserConfig
    { orderedRangeMinimumValue      :: !Int
    , orderedRangeMaximumValue      :: !Int
    , orderedRangeStepValue         :: !Int
    , orderedRangeDefaultStartValue :: !Int
    , orderedRangeDefaultEndValue   :: !Int
    , orderedRangeValueLabels       :: ![Text]
    , orderedRangeCrossingPolicy    :: !OrderedRangeCrossingPolicy
    }
    deriving (Eq, Show)

-- | Initial authoritative state. Subsequent browser changes are disposable
-- presentation until the named native range inputs are submitted and validated
-- by the server.
data OrderedRangeBrowserState = OrderedRangeBrowserState
    { orderedRangeStartValue :: !Int
    , orderedRangeEndValue   :: !Int
    , orderedRangeAvailable  :: !Bool
    }
    deriving (Eq, Show)

data OrderedRangeDom = OrderedRangeDom
    { orderedRangeRootAttribute            :: !Text
    , orderedRangeConfigAttribute          :: !Text
    , orderedRangeStateAttribute           :: !Text
    , orderedRangeStartAttribute           :: !Text
    , orderedRangeEndAttribute             :: !Text
    , orderedRangeAvailabilityAttribute    :: !Text
    , orderedRangeStartPositionCssProperty :: !Text
    , orderedRangeEndPositionCssProperty   :: !Text
    }
    deriving (Eq, Show)

canonicalOrderedRangeDom :: OrderedRangeDom
canonicalOrderedRangeDom = OrderedRangeDom
    { orderedRangeRootAttribute = domAttrValue @Contract.OrderedRangeRoot
    , orderedRangeConfigAttribute = domAttrValue @Contract.OrderedRangeConfig
    , orderedRangeStateAttribute = domAttrValue @Contract.OrderedRangeState
    , orderedRangeStartAttribute = domAttrValue @Contract.OrderedRangeStart
    , orderedRangeEndAttribute = domAttrValue @Contract.OrderedRangeEnd
    , orderedRangeAvailabilityAttribute = domAttrValue @Contract.OrderedRangeAvailability
    , orderedRangeStartPositionCssProperty = constantValue @Contract.OrderedRangeStartPositionProperty
    , orderedRangeEndPositionCssProperty = constantValue @Contract.OrderedRangeEndPositionProperty
    }

orderedRangeRootAttrs :: OrderedRangeBrowserConfig -> OrderedRangeBrowserState -> [(Text, Text)]
orderedRangeRootAttrs config state =
    [ (canonicalOrderedRangeDom.orderedRangeRootAttribute, "true")
    , (canonicalOrderedRangeDom.orderedRangeConfigAttribute, orderedRangeConfigJson config)
    , (canonicalOrderedRangeDom.orderedRangeStateAttribute, orderedRangeStateJson config state)
    ]

orderedRangeStartAttrs :: OrderedRangeBrowserConfig -> [(Text, Text)]
orderedRangeStartAttrs = endpointAttrs canonicalOrderedRangeDom.orderedRangeStartAttribute

orderedRangeEndAttrs :: OrderedRangeBrowserConfig -> [(Text, Text)]
orderedRangeEndAttrs = endpointAttrs canonicalOrderedRangeDom.orderedRangeEndAttribute

orderedRangeAvailabilityAttrs :: [(Text, Text)]
orderedRangeAvailabilityAttrs =
    [(canonicalOrderedRangeDom.orderedRangeAvailabilityAttribute, "true")]

endpointAttrs :: Text -> OrderedRangeBrowserConfig -> [(Text, Text)]
endpointAttrs role config =
    case validateOrderedRangeConfig config of
        OrderedRangeBrowserConfig { orderedRangeMinimumValue, orderedRangeMaximumValue, orderedRangeStepValue } ->
            [ (role, "true")
            , ("min", tshow orderedRangeMinimumValue)
            , ("max", tshow orderedRangeMaximumValue)
            , ("step", tshow orderedRangeStepValue)
            ]

orderedRangeConfigJson :: OrderedRangeBrowserConfig -> Text
orderedRangeConfigJson config =
    case validateOrderedRangeConfig config of
        OrderedRangeBrowserConfig { orderedRangeMinimumValue, orderedRangeMaximumValue, orderedRangeStepValue, orderedRangeDefaultStartValue, orderedRangeDefaultEndValue, orderedRangeValueLabels, orderedRangeCrossingPolicy } ->
            encodeContractValue $ recordValue @Contract.OrderedRangeConfig
                ( requiredField @Contract.MinimumValue orderedRangeMinimumValue
                    &: requiredField @Contract.MaximumValue orderedRangeMaximumValue
                    &: requiredField @Contract.StepValue orderedRangeStepValue
                    &: requiredField @Contract.DefaultStartValue orderedRangeDefaultStartValue
                    &: requiredField @Contract.DefaultEndValue orderedRangeDefaultEndValue
                    &: requiredField @Contract.ValueLabels orderedRangeValueLabels
                    &: requiredField @Contract.CrossingPolicy orderedRangeCrossingPolicy
                    &: noFields
                )

orderedRangeStateJson :: OrderedRangeBrowserConfig -> OrderedRangeBrowserState -> Text
orderedRangeStateJson config state =
    case validateOrderedRangeState config state of
        OrderedRangeBrowserState { orderedRangeStartValue, orderedRangeEndValue, orderedRangeAvailable } ->
            encodeContractValue $ recordValue @Contract.OrderedRangeState
                ( requiredField @Contract.StartValue orderedRangeStartValue
                    &: requiredField @Contract.EndValue orderedRangeEndValue
                    &: requiredField @Contract.Available orderedRangeAvailable
                    &: noFields
                )

orderedRangePositionStyle :: OrderedRangeBrowserConfig -> OrderedRangeBrowserState -> Text
orderedRangePositionStyle config state =
    case (validateOrderedRangeConfig config, validateOrderedRangeState config state) of
        (validConfig, validState) ->
            canonicalOrderedRangeDom.orderedRangeStartPositionCssProperty
                <> ": "
                <> positionPercent validConfig validState.orderedRangeStartValue
                <> "; "
                <> canonicalOrderedRangeDom.orderedRangeEndPositionCssProperty
                <> ": "
                <> positionPercent validConfig validState.orderedRangeEndValue
                <> ";"

positionPercent :: OrderedRangeBrowserConfig -> Int -> Text
positionPercent OrderedRangeBrowserConfig { orderedRangeMinimumValue, orderedRangeMaximumValue } value =
    cs (showFFloat (Just 3) percent "%")
  where
    spanValues = orderedRangeMaximumValue - orderedRangeMinimumValue
    percent = (fromIntegral (value - orderedRangeMinimumValue) / fromIntegral spanValues) * (100 :: Double)

validateOrderedRangeConfig :: OrderedRangeBrowserConfig -> OrderedRangeBrowserConfig
validateOrderedRangeConfig config@OrderedRangeBrowserConfig { orderedRangeMinimumValue, orderedRangeMaximumValue, orderedRangeStepValue, orderedRangeDefaultStartValue, orderedRangeDefaultEndValue, orderedRangeValueLabels }
    | orderedRangeMinimumValue >= orderedRangeMaximumValue = error "Ordered range minimum value must be less than maximum value"
    | orderedRangeStepValue <= 0 = error "Ordered range step value must be positive"
    | (orderedRangeMaximumValue - orderedRangeMinimumValue) `mod` orderedRangeStepValue /= 0 = error "Ordered range step must evenly divide the allowed range"
    | length orderedRangeValueLabels /= length allowedValues = error "Ordered range labels must cover every allowed value"
    | any (Text.null . Text.strip) orderedRangeValueLabels = error "Ordered range labels must not be empty"
    | orderedRangeDefaultStartValue `notElem` allowedValues = error "Ordered range default start value is outside the allowed range"
    | orderedRangeDefaultEndValue `notElem` allowedValues = error "Ordered range default end value is outside the allowed range"
    | orderedRangeDefaultStartValue > orderedRangeDefaultEndValue = error "Ordered range default start value must not exceed default end value"
    | otherwise = config
  where
    allowedValues = [orderedRangeMinimumValue, orderedRangeMinimumValue + orderedRangeStepValue .. orderedRangeMaximumValue]

validateOrderedRangeState :: OrderedRangeBrowserConfig -> OrderedRangeBrowserState -> OrderedRangeBrowserState
validateOrderedRangeState rawConfig state@OrderedRangeBrowserState { orderedRangeStartValue, orderedRangeEndValue }
    | orderedRangeStartValue `notElem` allowedValues = error "Ordered range start value is outside the allowed range"
    | orderedRangeEndValue `notElem` allowedValues = error "Ordered range end value is outside the allowed range"
    | orderedRangeStartValue > orderedRangeEndValue = error "Ordered range start value must not exceed end value"
    | otherwise = state
  where
    config = validateOrderedRangeConfig rawConfig
    allowedValues = [config.orderedRangeMinimumValue, config.orderedRangeMinimumValue + config.orderedRangeStepValue .. config.orderedRangeMaximumValue]

instance ContractReference Contract.OrderedRangeCrossingPolicy where
    type ContractReferenceValue Contract.OrderedRangeCrossingPolicy = OrderedRangeCrossingPolicy
    contractReferenceJson = Aeson.String . crossingPolicyText
    parseContractReference = Aeson.withText "OrderedRangeCrossingPolicy" \value ->
        if value == crossingPolicyText ClampOtherEndpoint
            then pure ClampOtherEndpoint
            else fail "Unknown OrderedRangeCrossingPolicy"

crossingPolicyText :: OrderedRangeCrossingPolicy -> Text
crossingPolicyText ClampOtherEndpoint
    | generatedCaseValue == exportedPolicyValue = generatedCaseValue
    | otherwise = error "Ordered range crossing policy constant disagrees with its generated enum case"
  where
    generatedCaseValue = enumLiteralValue @Contract.OrderedRangeCrossingPolicy @Contract.ClampOtherEndpoint
    exportedPolicyValue = constantValue @Contract.OrderedRangeClampOtherEndpoint

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
