{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendTimePickerIncompleteConfig where

import qualified Application.Helper.FrontendContract.TimePicker as TimePicker
import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude

incompleteTimePickerConfig =
    recordValue @TimePicker.TimePickerConfig
        ( requiredField @TimePicker.RangeStart "06:00"
            &: requiredField @TimePicker.RangeEnd "05:45"
            &: requiredField @TimePicker.StepMinutes 15
            &: noFields
        )
