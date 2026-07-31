{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.TimePicker.Runtime
    ( TimePickerBrowserConfig (..)
    , TimePickerDom (..)
    , TimePickerOptionValue (..)
    , canonicalTimePickerDom
    , timePickerClearAttrs
    , timePickerConfigJson
    , timePickerFieldAttrs
    , timePickerKeyboardAttrs
    , timePickerLabelAttrs
    , timePickerOptionAttrs
    , timePickerOptionsAttrs
    , timePickerStepDownAttrs
    , timePickerStepUpAttrs
    , timePickerTriggerAttrs
    , timePickerValueAttrs
    ) where

import qualified Application.Helper.FrontendContract.TimePicker as Contract
import Application.Helper.FrontendContract.Values (domAttrValue, domIdValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay)
import IHP.Prelude

data TimePickerBrowserConfig = TimePickerBrowserConfig
    { browserTimePickerRangeStart  :: !Text
    , browserTimePickerRangeEnd    :: !Text
    , browserTimePickerStepMinutes :: !Int
    , browserTimePickerEmptyLabel  :: !Text
    }
    deriving (Eq, Show)

data TimePickerOptionValue = TimePickerOptionValue
    { timePickerOptionValue :: !Text
    , timePickerOptionLabel :: !Text
    }
    deriving (Eq, Show)

data TimePickerDom = TimePickerDom
    { timePickerModalId           :: !Text
    , timePickerModalTitleId      :: !Text
    , timePickerFieldAttribute    :: !Text
    , timePickerConfigAttribute   :: !Text
    , timePickerTriggerAttribute  :: !Text
    , timePickerKeyboardAttribute :: !Text
    , timePickerValueAttribute    :: !Text
    , timePickerLabelAttribute    :: !Text
    , timePickerStepDownAttribute :: !Text
    , timePickerStepUpAttribute   :: !Text
    , timePickerOptionsAttribute  :: !Text
    , timePickerOptionAttribute   :: !Text
    , timePickerClearAttribute    :: !Text
    }
    deriving (Eq, Show)

canonicalTimePickerDom :: TimePickerDom
canonicalTimePickerDom = TimePickerDom
    { timePickerModalId = domIdValue @Contract.TimePickerModal
    , timePickerModalTitleId = domIdValue @Contract.TimePickerModalTitle
    , timePickerFieldAttribute = domAttrValue @Contract.TimePickerField
    , timePickerConfigAttribute = domAttrValue @Contract.TimePickerConfig
    , timePickerTriggerAttribute = domAttrValue @Contract.TimePickerTrigger
    , timePickerKeyboardAttribute = domAttrValue @Contract.TimePickerKeyboard
    , timePickerValueAttribute = domAttrValue @Contract.TimePickerValue
    , timePickerLabelAttribute = domAttrValue @Contract.TimePickerLabel
    , timePickerStepDownAttribute = domAttrValue @Contract.TimePickerStepDown
    , timePickerStepUpAttribute = domAttrValue @Contract.TimePickerStepUp
    , timePickerOptionsAttribute = domAttrValue @Contract.TimePickerOptions
    , timePickerOptionAttribute = domAttrValue @Contract.TimePickerOption
    , timePickerClearAttribute = domAttrValue @Contract.TimePickerClear
    }

timePickerFieldAttrs :: TimePickerBrowserConfig -> [(Text, Text)]
timePickerFieldAttrs config =
    roleAttrs canonicalTimePickerDom.timePickerFieldAttribute
        <> [(canonicalTimePickerDom.timePickerConfigAttribute, timePickerConfigJson config)]

timePickerTriggerAttrs :: [(Text, Text)]
timePickerTriggerAttrs = roleAttrs canonicalTimePickerDom.timePickerTriggerAttribute

timePickerKeyboardAttrs :: [(Text, Text)]
timePickerKeyboardAttrs = roleAttrs canonicalTimePickerDom.timePickerKeyboardAttribute

timePickerValueAttrs :: [(Text, Text)]
timePickerValueAttrs = roleAttrs canonicalTimePickerDom.timePickerValueAttribute

timePickerLabelAttrs :: [(Text, Text)]
timePickerLabelAttrs = roleAttrs canonicalTimePickerDom.timePickerLabelAttribute

timePickerStepDownAttrs :: [(Text, Text)]
timePickerStepDownAttrs = roleAttrs canonicalTimePickerDom.timePickerStepDownAttribute

timePickerStepUpAttrs :: [(Text, Text)]
timePickerStepUpAttrs = roleAttrs canonicalTimePickerDom.timePickerStepUpAttribute

timePickerOptionsAttrs :: [(Text, Text)]
timePickerOptionsAttrs = roleAttrs canonicalTimePickerDom.timePickerOptionsAttribute

timePickerOptionAttrs :: TimePickerOptionValue -> [(Text, Text)]
timePickerOptionAttrs option =
    [(canonicalTimePickerDom.timePickerOptionAttribute, timePickerOptionJson option)]

timePickerClearAttrs :: [(Text, Text)]
timePickerClearAttrs = roleAttrs canonicalTimePickerDom.timePickerClearAttribute

timePickerConfigJson :: TimePickerBrowserConfig -> Text
timePickerConfigJson TimePickerBrowserConfig { browserTimePickerRangeStart, browserTimePickerRangeEnd, browserTimePickerStepMinutes, browserTimePickerEmptyLabel }
    | not (validTimeValue browserTimePickerRangeStart) = error "Time picker range start must use HH:MM"
    | not (validTimeValue browserTimePickerRangeEnd) = error "Time picker range end must use HH:MM"
    | browserTimePickerStepMinutes <= 0 || browserTimePickerStepMinutes > 24 * 60 = error "Time picker step must be between 1 and 1440 minutes"
    | Text.null (Text.strip browserTimePickerEmptyLabel) = error "Time picker empty label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.TimePickerConfig
        ( requiredField @Contract.RangeStart browserTimePickerRangeStart
            &: requiredField @Contract.RangeEnd browserTimePickerRangeEnd
            &: requiredField @Contract.StepMinutes browserTimePickerStepMinutes
            &: requiredField @Contract.EmptyLabel browserTimePickerEmptyLabel
            &: noFields
        )

timePickerOptionJson :: TimePickerOptionValue -> Text
timePickerOptionJson TimePickerOptionValue { timePickerOptionValue, timePickerOptionLabel }
    | not (validTimeValue timePickerOptionValue) = error "Time picker option value must use HH:MM"
    | Text.null (Text.strip timePickerOptionLabel) = error "Time picker option label must not be empty"
    | otherwise = encodeContractValue $ recordValue @Contract.TimePickerOption
        ( requiredField @Contract.Value timePickerOptionValue
            &: requiredField @Contract.Label timePickerOptionLabel
            &: noFields
        )

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]

validTimeValue :: Text -> Bool
validTimeValue value = isJust (parseTimeM True defaultTimeLocale "%H:%M" (cs value) :: Maybe TimeOfDay)

encodeContractValue :: Aeson.Value -> Text
encodeContractValue = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
