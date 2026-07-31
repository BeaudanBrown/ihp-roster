{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.TimePicker
    ( TimePickerContract
    , TimePicker
    , TimePickerConfig
    , TimePickerOption
    , RangeStart
    , RangeEnd
    , StepMinutes
    , EmptyLabel
    , Value
    , Label
    , TimePickerModal
    , TimePickerModalTitle
    , TimePickerField
    , TimePickerTrigger
    , TimePickerKeyboard
    , TimePickerValue
    , TimePickerLabel
    , TimePickerStepDown
    , TimePickerStepUp
    , TimePickerOptions
    , TimePickerClear
    ) where

import Application.Helper.FrontendContract.DSL

-- | Reusable quarter-hour picker vocabulary. Haskell owns ranges, option
-- values/labels, empty-state copy, and rendered native state; the browser owns
-- only mechanical modal behavior over this exact boundary.
data TimePicker

data TimePickerConfig
data TimePickerOption

data RangeStart
data RangeEnd
data StepMinutes
data EmptyLabel

data Value
data Label

data TimePickerModal
data TimePickerModalTitle
data TimePickerField
data TimePickerTrigger
data TimePickerKeyboard
data TimePickerValue
data TimePickerLabel
data TimePickerStepDown
data TimePickerStepUp
data TimePickerOptions
data TimePickerClear

type TimePickerContract =
    Global TimePicker
        '[ BrowserInboundSchema (Record TimePickerConfig
            '[ Field RangeStart 'WireText
             , Field RangeEnd 'WireText
             , Field StepMinutes 'WireInt
             , Field EmptyLabel 'WireText
             ])
         , BrowserInboundSchema (Record TimePickerOption
            '[ Field Value 'WireText
             , Field Label 'WireText
             ])
         , DomId TimePickerModal
         , ServerDomId TimePickerModalTitle
         , DomAttr TimePickerField
         , DomAttr TimePickerConfig
         , DomAttr TimePickerTrigger
         , DomAttr TimePickerKeyboard
         , DomAttr TimePickerValue
         , DomAttr TimePickerLabel
         , DomAttr TimePickerStepDown
         , DomAttr TimePickerStepUp
         , DomAttr TimePickerOptions
         , DomAttr TimePickerOption
         , DomAttr TimePickerClear
         ]
